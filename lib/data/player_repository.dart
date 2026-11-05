import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import '../core/errors.dart';
import 'models.dart';

/// 播放模式：顺序播完即停 / 列表循环 / 单曲循环 / 随机。
enum PlayMode { sequential, loop, repeatOne, shuffle }

/// 播放队列快照：当前队列 + 正在播放的下标。
class QueueSnapshot {
  final List<Song> songs;
  final int index;
  const QueueSnapshot(this.songs, this.index);
}

/// 预取音源缓存条目：URL + 解析时间（供 TTL 过期判断）。
class _ResolvedUrl {
  final String url;
  final DateTime at;
  const _ResolvedUrl(this.url, this.at);
}

/// 基于 audio_service + just_audio 的播放处理器：
/// 支持后台播放、锁屏 / 通知媒体控制（Android/macOS）、
/// 播放队列（自动切歌 / 手动上下曲 / 指定曲目）、四种播放模式与平滑进度流。
class NcmAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  /// 播放器实例。**可重建**：ColorOS 等激进后台管控会在长时间挂起后冻结或
  /// 回收底层 ExoPlayer，此时旧实例的 play()/setUrl() Future 可能永不返回；
  /// 复用旧实例重装载同样会卡死。自愈流程必须销毁换新实例（见 [_rebuildPlayer]）。
  AudioPlayer _player = AudioPlayer();

  /// 当前播放器实例的 stream 订阅：换实例时统一取消并重挂（[_bindPlayer]）。
  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferedSub;

  /// 对外进度流：固定由本 handler 持有，播放器重建后 UI 订阅不会断流。
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _bufferedController =
      StreamController<Duration>.broadcast();

  /// 最近一次成功装载的音源（重建播放器时优先复用；重新解析失败时兜底）。
  String? _loadedUrl;

  /// 播放请求看门狗超时：发出起播请求后超过该时长仍未真正进入播放态即判定
  /// 播放器失效并触发重建。测试可注入更短的值。
  Duration playStartTimeout;

  /// 长时间后台后判定「底层引擎可能已僵死」的阈值：回前台时若已装载音源
  /// 超过该时长且处于暂停态，下次点播放改为重建播放器而非复用旧实例。
  /// 注意不能与 [_loadedUrlMaxAge]（直链有效期）混用，后者决定是否重解析。
  Duration staleEngineAfter;

  final Random _random = Random();
  Song? _current;
  final List<Song> _queue = [];
  int _queueIndex = -1;
  PlayMode _playMode = PlayMode.sequential;

  /// 音源解析回调（main 注入 api.songUrl），handler 不直接依赖 HTTP 层。
  Future<String?> Function(int songId)? urlResolver;

  /// 成功开播一首歌时的回调（providers 注入 HistoryNotifier.add，记录播放历史）。
  /// 单回调：只允许一个订阅方；需要多处消费时用 [songStartedStream]。
  void Function(Song song)? onSongStarted;

  /// 音源真正加载成功时的回调（providers 注入 PlaybackCacheNotifier.cacheSong，
  /// 透明落盘播放缓存，使下次冷启动断点续播可秒开、跳过缓冲与直链过期）。
  /// 正常起播与断点恢复装载两条路径都会触发；[url] 为最终装载用的音源
  /// （网络直链或本地 file://）。
  void Function(Song song, String url)? onSongLoaded;

  /// 成功开播广播流（收听统计等第二订阅方使用）。
  /// 用广播流而不是再挂一个回调：`onSongStarted` 已被播放历史独占，
  /// 后赋值者会顶掉前一个，两个功能互相抢事件。
  final StreamController<Song> _songStartedController =
      StreamController<Song>.broadcast();
  Stream<Song> get songStartedStream => _songStartedController.stream;

  /// 预取的音源 URL 缓存（id -> 解析结果）：切歌命中即跳过接口解析，
  /// 弱化慢接口下的切歌等待。网易直链 expi≈20 分钟，TTL 收紧到 10 分钟；
  /// 即便过期，_playAt 内 setUrl 失败会强刷重解析一次兜底。
  /// 缓存只按歌曲 id 关联（与队列无关），clearQueue 不清，靠 TTL 自然淘汰。
  final Map<int, _ResolvedUrl> _urlCache = {};
  static const Duration _urlCacheTtl = Duration(minutes: 10);
  static const int _urlCacheMax = 32; // 超限时按插入序淘汰最旧条目

  /// 进行中的解析（id -> Future）：预取与用户切歌撞车时复用同一请求，
  /// 避免慢接口下同一首歌重复排队解析。
  final Map<int, Future<String?>> _resolving = {};

  /// 当前已成功加载进播放器的歌曲 id。解析失败时播放器里仍是上一首的
  /// 音源——play() 与单曲循环据此判断音源归属，防止旧歌被"复活"
  /// （UI 显示新歌、耳朵却在听旧歌）。
  int? _loadedSongId;

  /// 递增式切歌序号：快速连点/自动 play 与列表起播撞车时 _playAt 会并发
  /// 执行，旧调用在每个 await 后发现序号已被更新的切歌取代即退出，保证
  /// 只有最后一次真正加载音源（否则旧调用可能后完成，出现「播的不是
  /// UI 显示的歌」，或旧失败态覆盖新调用的播放状态）。
  int _playSeq = 0;

  /// 是否有 _playAt 正在进行（play() 据此避免对在飞曲目重入切歌）。
  bool _playAtRunning = false;

  /// 最近一次在飞的 _playAt 的 Future（play() 在恢复窗口期点播时据此
  /// 等待装载完成后接管起播，而不是静默吞掉点击）。
  Future<void>? _playAtInFlight;

  /// 断点续听：待恢复的播放进度与目标曲目。音源装载成功后 seek 一次即作废；
  /// 目标不匹配的 _playAt 也会作废它，避免后续切歌误跳回旧断点。
  Duration? _pendingSeek;
  int? _pendingSeekSongId;

  /// 当前音源装载时刻：play() 据此判断是否可能已过期（断点恢复后迟迟未播、
  /// 或久置后才点播），过期先原地重载再播，防止拿失效直链硬播后无声。
  DateTime? _loadedAt;
  static const Duration _loadedUrlMaxAge = Duration(minutes: 15);

  /// 冷启动恢复态标记：restoreQueue 已完成装载，但底层音频会话/引擎在冷启动后
  /// 处于「假就绪」（playing 乐观为 true 却无声）。首次 play() 须强制重建底层
  /// （_safePlayAt 重载）而非直接 play()，否则无声且无法自愈。详见 [play]。
  bool _needsColdStartReload = false;

  /// 可疑停滞标记：play() 的播放后单次确认发现「假播放」（底层 playing 乐观
  /// 为 true、processingState 仍 ready，但音频输出被系统收回、进度不推进）时置
  /// true，使 UI 按钮回显 ▶ 而非 ⏸——否则假播放下按钮显示暂停，用户点击反而
  /// 触发 pause() 形成死锁。重载成功（_doPlayAt 装载完成）即清回 false。
  bool _suspectStall = false;

  /// 暂停代次：每次 [pause]（用户点暂停/通知栏/睡眠定时器等用户意图暂停）
  /// +1。play() 末尾的「无声自愈」兜底据此区分两种 playing=false：
  /// - audio session 激活失败，playing 在 play() 内被静默回翻——兜底要处理的
  ///   场景，此时无任何用户暂停，代次未变；
  /// - just_audio 的 play() Future 语义是「播放被暂停/停止/播完时完成」，
  ///   await play() 会挂起到用户真正按下暂停那一刻才返回——这是正常用户
  ///   暂停，绝不能触发自愈（否则暂停 1~2 秒后重装载自动复播，表现为
  ///   「点了暂停，先停一两秒又自己播起来，得再按一次才能停住」）。
  int _pauseEpoch = 0;

  /// 系统打断（来电 / 其他 App 抢焦点）标记：[ _onInterruption ] 在 begin
  /// 暂停并记住「此前在播」，end 时若仍为此标记才自动续播；用户手动
  /// 暂停/播放会清掉此标记，避免打断结束后把用户主动暂停的音乐又播起来。
  bool _interruptedPause = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// 提示音闪避（如导航播报）标记：打断 begin 且 [AudioInterruptionEvent.shouldPause]
  /// 为 false 时压低音量而非暂停，end 时还原。对应 kele-audio 的 onFocusDucked。
  bool _ducked = false;
  static const double _duckVolume = 0.3;
  StreamSubscription<void>? _becomingNoisySub;

  /// 播放失败轻提示流（广播）：_safePlayAt 兜底的失败路径不向上抛异常
  /// （防通知栏/手势回调里的未捕获异常在 release 闪退），改经此流广播，
  /// 由 UI 层统一弹 SnackBar 告知失败原因。走 playQueue 上抛的路径
  /// （列表起播）仍由各调用方自行提示，两路互不重叠。
  final StreamController<String> _playErrorController =
      StreamController<String>.broadcast();
  Stream<String> get playErrorStream => _playErrorController.stream;

  /// 音源获取超时上限（解析直链、装载音源各一步）。超时即回滚乐观播放态、
  /// 撤下 loading 并提示，避免「按钮显示在播、实际永远没声音」。
  static const Duration _sourceTimeout = Duration(seconds: 12);

  /// 乐观播放意图：用户点播放/暂停后立即写 UI，不等网络与底层起播。
  /// null = 无覆盖（按钮完全跟随真实播放态）。仅在以下时机清除/翻转：
  /// - 真实播放态与意图一致、且没有装载在飞时消费掉意图（_onPlaybackEvent）；
  /// - 装载失败 / 超时 / 平台播放错误时回滚（_rollbackPlayIntent）；
  /// - 用户再次点按时由 play()/pause() 覆写。
  bool? _playIntent;

  /// 用户最后一次显式意图（true = 想播放，false = 想暂停）。只由用户操作
  /// （play / pause / toggle、清空队列）与失败回滚改写，不会被播放事件消费。
  /// [_playIntent] 是 UI 覆盖层，真实态对齐后即清除；本字段则必须一直保留到
  /// 下一次用户操作——音源装载窗口内用户点了暂停，装载完成时正是靠它避免
  /// 「按了暂停却自己播起来」（事件里若把意图清成 null，守卫就失效了）。
  bool _userWantsPlaying = false;

  /// 乐观态看门狗：点播放后超过 [_intentTimeout] 仍未真正起播即回滚并提示，
  /// 防止底层假死时按钮长期停留在「播放中」。
  static const Duration _intentTimeout = Duration(seconds: 15);
  Timer? _intentWatchdog;

  /// 播放请求看门狗：专门盯「已经把起播请求发给平台之后」这一段。与
  /// [_intentWatchdog]（覆盖解析/装载全过程）互补——后者只保证按钮不长期
  /// 错位，前者一旦超时直接判定播放器失效并重建（结构自愈）。
  Timer? _playWatchdog;
  int _watchdogEpoch = 0;
  Duration _watchdogStartPosition = Duration.zero;

  /// 重建播放器进行中 / 连续失败次数（真正起播后清零，避免无限重建）。
  bool _healing = false;
  int _healAttempts = 0;
  static const int _maxHealAttempts = 2;

  /// 音频会话激活超时。ColorOS 冻结进程后 `AudioSession.setActive` 的平台
  /// 通道可能永不返回，play() 会卡在这一步——表现为「点播放毫无反应且无
  /// 报错」。必须带超时，超时即按「会话失联」处理。
  static const Duration _sessionTimeout = Duration(seconds: 2);

  /// 正在获取音源的歌曲 id（null = 无）。播放页封面 loading 层据此展示；
  /// 换歌时由新调用覆盖，旧请求返回后不会撤掉新歌的 loading。
  int? _preparingSongId;
  final StreamController<bool> _preparingController =
      StreamController<bool>.broadcast();

  /// 音源获取中状态流（true = 正在解析/装载当前曲）。广播流不重放，
  /// UI 订阅时的初始值用 [isPreparing] 兜底。
  Stream<bool> get loadingStream => _preparingController.stream;
  bool get isPreparing => _preparingSongId != null;

  /// 真实播放态（底层确实在出声）：按钮与歌词动效共用的唯一判据。
  /// 播完（completed）不算在播：just_audio 在播完后 playing 仍保持 true
  /// （官方语义：要等 pause/stop 才复位），与实际无声的播放器状态矛盾。
  bool get _actualPlaying =>
      _player.playing &&
      _loadedSongId != null &&
      !_suspectStall &&
      _player.processingState != ProcessingState.completed;

  /// UI 播放态：乐观意图优先，点按后立即生效，无需等音源就绪。
  bool get uiPlaying => _playIntent ?? _actualPlaying;

  final StreamController<QueueSnapshot> _queueController =
      StreamController<QueueSnapshot>.broadcast();

  /// 队列变化流（构造时先发一份空快照，保证监听方有初始值）。
  Stream<QueueSnapshot> get queueStream => _queueController.stream;
  QueueSnapshot get currentQueueSnapshot =>
      QueueSnapshot(List.unmodifiable(_queue), _queueIndex);
  List<Song> get songs => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  Song? get currentSong => _current;

  /// 当前已加载进播放器的歌曲 id（null = 音源未就绪）。UI 层据此区分
  /// 「暂停中的已加载曲目」与「起播在飞/解析失败」，避免误自动续播。
  int? get loadedSongId => _loadedSongId;
  PlayMode get playMode => _playMode;

  /// 当前播放位置（断点快照回写用；音源未装载时为 0）。
  Duration get position => _player.position;

  /// 平滑进度流（just_audio 周期性发射），供歌词同步与进度动效使用。
  /// 走 handler 自持的广播流：播放器重建后 UI 的订阅不会指向已销毁实例。
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get bufferedPositionStream => _bufferedController.stream;
  bool get isPlaying => _player.playing;

  NcmAudioHandler({
    this.playStartTimeout = const Duration(seconds: 4),
    this.staleEngineAfter = const Duration(minutes: 5),
  }) {
    _bindPlayer();
    _queueController.add(const QueueSnapshot([], -1));
  }

  /// 挂载当前播放器实例的事件订阅。播放器重建后必须重新调用。
  void _bindPlayer() {
    _playbackSub?.cancel();
    _processingSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    // 关键：这两个 stream 会发射**错误事件**（ExoPlayer 播放错误、音源
    // 加载失败等，切歌时最常见）。错误不经过 onData 回调，try/catch 拦不住；
    // 不带 onError 监听 → 错误进 zone → release 包直接闪退（Web 端实现
    // 不同不发射，所以 Web 正常）。官方文档要求必须带 onError。
    _playbackSub = _player.playbackEventStream.listen(_onPlaybackEvent,
        onError: (Object _, StackTrace __) => _onPlayerError());
    _processingSub = _player.processingStateStream.listen(_onProcessingState,
        onError: (Object _, StackTrace __) {});
    _positionSub = _player.positionStream.listen(_positionController.add,
        onError: (Object _, StackTrace __) {});
    _bufferedSub = _player.bufferedPositionStream.listen(_bufferedController.add,
        onError: (Object _, StackTrace __) {});
  }

  /// 统一日志出口：真机复现时可直接按 [player] 前缀过滤定位断点。
  void _log(String message) => debugPrint('[player] $message');

  /// 向 UI 广播一条轻提示（SnackBar）。供非 UI 层的守护逻辑（如通知权限
  /// 被拒）复用既有提示通道，避免新增一套 UI 回调。
  void notifyUser(String message) => _playErrorController.add(message);

  /// 激活音频会话 / 重新申请音频焦点。带超时——平台通道被冻结时
  /// `setActive` 的 Future 永不返回，绝不能让它把 play() 卡死。
  Future<bool> _ensureSessionActive() async {
    try {
      final session = await AudioSession.instance;
      final active = await session.setActive(true).timeout(_sessionTimeout);
      return active;
    } on TimeoutException {
      _log('session[timeout] setActive 超过 ${_sessionTimeout.inMilliseconds}ms');
      return false;
    } catch (e) {
      _log('session[error] $e');
      return false;
    }
  }

  /// 配置音频会话类别并接管系统打断（来电 / 其他 App 抢焦点）。
  /// 须在 AudioService.init 之后调用一次。此前应用从未显式配置会话类别、
  /// 也不监听打断，导致：① iOS 缺少 playback 类别保障，后台播放不稳；
  /// ② 来电等打断后播放器状态错乱（停了不续、或显示播放却无声）。
  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _interruptionSub?.cancel();
    _interruptionSub = session.interruptionEventStream.listen(_onInterruption);
    _becomingNoisySub?.cancel();
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) => _onNoisy());
  }

  /// 系统音频打断：begin 时区分两种语义——
  /// • [AudioInterruptionEvent.shouldPause] 为真（如来电、被永久抢占）：暂停并记
  ///   住，end 时若仍是此前打断引起的暂停则续播；
  /// • 为假（提示音闪避，如导航播报）：压低音量而非暂停，end 时还原。
  /// 用户手动暂停/播放会清掉 [_interruptedPause]/[_ducked]，避免打断结束后
  /// 把用户主动暂停的音乐又播起来，或误还原音量。
  Future<void> _onInterruption(AudioInterruptionEvent event) async {
    if (event.begin) {
      if (_player.playing) {
        if (event.type == AudioInterruptionType.duck) {
          // 提示音闪避（如导航播报）：压低音量而非暂停，end 时还原。
          _ducked = true;
          try {
            await _player.setVolume(_duckVolume);
          } catch (_) {}
        } else {
          // 来电等需暂停的打断（含 unknown：可能无限期暂停）：暂停并记，
          // end 时若仍是此前打断引起的暂停则续播。
          _interruptedPause = true;
          unawaited(pause());
        }
      }
    } else if (_interruptedPause) {
      _interruptedPause = false;
      unawaited(play());
    } else if (_ducked) {
      _ducked = false;
      try {
        await _player.setVolume(1.0);
      } catch (_) {}
    }
  }

  /// 音频输出设备断开（拔耳机 / 蓝牙断开）：立即暂停（不自动恢复），避免声音
  /// 突然从手机外放播出。对应 kele-audio 的 onNoisy。iOS 无此系统事件，由系统
  /// 路由切换处理；Android 经 audio_session 的 becomingNoisyEventStream 触发。
  void _onNoisy() {
    if (!_player.playing) return;
    _interruptedPause = false; // 清打断续播标记，避免随后打断结束误续播
    unawaited(pause());
  }

  /// 一首播完按播放模式决定下一曲。整段 try/catch 兜住所有边界情况。
  Future<void> _onProcessingState(ProcessingState s) async {
    if (s != ProcessingState.completed) return;
    try {
      final advanced = await _advance(auto: true);
      // 顺序模式播完最后一首：真实态已停止，必须清掉乐观在播意图，否则
      // 按钮会停在 ⏸（显示在播、实际无声）。仅在没有新的装载在飞时清理
      // （避免把自动切歌的新曲意图误清）。
      if (!advanced && !_playAtRunning) {
        _playIntent = null;
        _userWantsPlaying = false;
        _intentWatchdog?.cancel();
        _intentWatchdog = null;
        // 复位底层 playing 标志：just_audio 播完后 playing 仍为 true，
        // 不 pause 的话下次点播放会被 play() 的 `if (playing) return;` 吞掉。
        unawaited(_player.pause());
        playbackState.add(playbackState.value.copyWith(playing: false));
      }
    } catch (_) {}
  }

  /// 切下一曲的统一入口。[auto]=自然播完触发（顺序模式到队尾即停）。
  /// 返回是否发生了切歌/重播；false 表示已到队列边界（供 UI 提示）。
  Future<bool> _advance({required bool auto}) async {
    if (_queue.isEmpty) return false;
    switch (_playMode) {
      case PlayMode.repeatOne:
        if (!auto) {
          // 手动「下一首」：与按钮文案一致，按列表循环语义切歌（到尾回绕）。
          // 单曲循环只约束自然播完的自动续播（auto），否则按钮点了一直重播
          // 本曲，与 hasNext 恒 true、提示写「下一首」的 UI 契约相悖。
          await _safePlayAt((_queueIndex + 1) % _queue.length);
          return true;
        }
        // 单曲循环自动续播：不切歌，回到开头继续播。当前曲音源从未加载成功
        // 时（如解析失败），播放器里还是上一首——改走重解析，别让旧歌复活。
        if (_loadedSongId != _current?.id) {
          await _safePlayAt(_queueIndex);
        } else {
          try {
            await _player.seek(Duration.zero);
            _startPlayback('单曲循环重播');
          } catch (_) {}
        }
        return true;
      case PlayMode.shuffle:
        if (_queue.length == 1) {
          await _safePlayAt(0);
        } else {
          var i = _queueIndex;
          while (i == _queueIndex) {
            i = _random.nextInt(_queue.length);
          }
          await _safePlayAt(i);
        }
        return true;
      case PlayMode.loop:
        await _safePlayAt((_queueIndex + 1) % _queue.length);
        return true;
      case PlayMode.sequential:
        if (auto) {
          // 播完即停：不是最后一首才续播。
          if (_queueIndex < _queue.length - 1) {
            await _safePlayAt(_queueIndex + 1);
            return true;
          }
          return false;
        }
        // 手动下一首：到队尾不再重播，交由 UI 提示"没有下一曲"。
        if (_queueIndex >= _queue.length - 1) return false;
        await _safePlayAt(_queueIndex + 1);
        return true;
    }
  }

  /// 内部切歌的容错包装：切歌失败（无音源/加载异常等）不向调用方抛出，
  /// 避免通知栏回调、手势与 fire-and-forget 调用里的未捕获异常
  /// 在 release 包直接闪退。失败态已在 _playAt 中置为暂停。
  /// 但失败不能无声——经 playErrorStream 广播，UI 弹轻提示，
  /// 让用户分得清「点了没反应」与「点了但没有音源」。
  Future<void> _safePlayAt(int index) async {
    try {
      await _playAt(index);
    } catch (e) {
      _playErrorController.add(
          e is ApiException ? e.userMessage : '播放失败，请稍后重试');
    }
  }

  void _emitQueue() =>
      _queueController.add(QueueSnapshot(List.unmodifiable(_queue), _queueIndex));

  /// 写入乐观播放意图并立即刷新 UI 播放态；[playing]=true 时启动看门狗。
  void _setPlayIntent(bool playing) {
    _playIntent = playing;
    // 显式用户操作：同步更新持久意图，供装载完成后判断是否仍该起播。
    _userWantsPlaying = playing;
    _intentWatchdog?.cancel();
    _intentWatchdog = null;
    if (playing) {
      _intentWatchdog = Timer(_intentTimeout, _onIntentTimeout);
    }
    // 乐观态同时翻转播放控件（通知栏/系统控制面板），避免只有页面按钮先变、
    // 系统通知里仍显示旧图标直到真实播放事件到达。
    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
    ));
  }

  /// 看门狗：意图在播但底层迟迟未真正起播 → 回滚并提示，避免长期错位。
  void _onIntentTimeout() {
    _intentWatchdog = null;
    // 重建在飞时不要回滚：起播结果交给播放看门狗判定，否则会出现
    // 「按钮回 ▶、重建完却自己播起来」的错位。
    if (_healing) return;
    if (_playIntent != true || _actualPlaying) return;
    _rollbackPlayIntent();
    _endPreparing();
    _playErrorController.add('播放超时，请稍后重试');
  }

  /// 回滚到「暂停」：按钮立刻回 ▶；下一次真实播放事件（actual=false）
  /// 会清除意图，之后完全跟随真实态。
  void _rollbackPlayIntent() {
    _intentWatchdog?.cancel();
    _intentWatchdog = null;
    _endPlayWatchdog();
    // 回滚即「实际状态是暂停」：持久意图同步归零，避免装载完成时又起播。
    _userWantsPlaying = false;
    if (_playIntent == false) return;
    _playIntent = false;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  /// 标记某首歌开始获取音源（同一首歌重复标记不重复发事件）。
  void _markPreparing(int songId) {
    if (_preparingSongId == songId) return;
    _preparingSongId = songId;
    _preparingController.add(true);
  }

  /// 结束获取中状态。[songId] 指定时只在「仍是这首歌」时才清除，
  /// 防止被切歌取代的旧请求撤掉新歌的 loading。
  void _endPreparing([int? songId]) {
    if (songId != null && _preparingSongId != songId) return;
    if (_preparingSongId == null) return;
    _preparingSongId = null;
    _preparingController.add(false);
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    final actualPlaying = _actualPlaying;
    // 真实态与乐观意图一致 → 意图已兑现，后续完全跟随真实播放态。
    // 但音源装载在飞时不消费：装载窗口内用户点了暂停，若此时把意图清成
    // null，「装载完成后是否还该起播」的判断就会失效（暂停被无视、自动
    // 复播）。持久意图 [_userWantsPlaying] 不受此影响，消费仅关乎 UI 覆盖。
    if (_playIntent != null && _playIntent == actualPlaying && !_playAtRunning) {
      _playIntent = null;
      _intentWatchdog?.cancel();
      _intentWatchdog = null;
    }
    // 新曲音源已装载且底层开始播放：撤下封面 loading 层。
    // 用 _loadedSongId 判断（而非仅 playing），避免旧歌尚未暂停完的
    // 播放事件在装载窗口内误撤 loading。
    if (_player.playing &&
        _preparingSongId != null &&
        _loadedSongId == _preparingSongId) {
      _endPreparing();
    }
    final showingPlaying = _playIntent ?? actualPlaying;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        showingPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      // 与音源归属联动：平台层报错后 just_audio 的 playing 标志可能卡在
      // true（与实际发声脱节），后续任何播放事件都会把播放态刷回去。
      // 无有效音源（_loadedSongId 为空）或处于「假播放」可疑停滞（play()
      // 播放后确认未真正起播）时一律视为未播放，UI 回显 ▶，点播放走 play()
      // 的重装载自愈路径——避免假播放下按钮显示 ⏸、点击反而触发 pause 死锁。
      // 但用户刚点按的乐观意图优先：不必等音源就绪才切换图标。
      playing: showingPlaying,
      processingState: _toProcessingState(event.processingState),
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
    ));
  }

  AudioProcessingState _toProcessingState(ProcessingState s) {
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 平台层播放错误（ExoPlayer 解码失败、网络中断、音源被 CDN 拒绝等，
  /// 真机独有路径）：播放器已退回 idle，但 just_audio 的 playing 标志
  /// 可能仍为 true——此后每次点播放都命中 play() 开头的 `if (playing)
  /// return`，成为永久无声 no-op（真机冷启动恢复后「点不动、须关播放
  /// 条或杀进程才能修」的根因）。这里同步作废音源归属并复位播放态，
  /// 让下一次 play() 走重装载路径自愈。装载/重试进行中的错误不重复
  /// 提示（该路径已有自己的兜底与提示），只复位状态。
  void _onPlayerError() {
    _loadedSongId = null;
    _loadedAt = null;
    // 平台错误即回滚：乐观意图、loading 层都不能留下错位状态。
    _playIntent = false;
    _userWantsPlaying = false;
    _intentWatchdog?.cancel();
    _intentWatchdog = null;
    _endPlayWatchdog();
    _endPreparing();
    playbackState.add(playbackState.value.copyWith(playing: false));
    if (!_playAtRunning) _playErrorController.add('播放出错，请重试');
  }

  /// 以整队列上下文播放 [index] 处的曲目；解析/加载失败时抛
  /// [ApiException]（音源为空）或保持暂停（加载异常），由调用方提示。
  Future<void> playQueue(List<Song> songs, int index) async {
    // 空歌单不起播：先清队列会让正在播的队列凭空消失，随后 _playAt 又因
    // 下标越界静默返回，留下「媒体项与队列不一致」的错乱态。
    if (songs.isEmpty) return;
    // 显式起播新队列：作废未消费的断点（如恢复装载失败后残留的 pendingSeek）。
    _pendingSeek = null;
    _pendingSeekSongId = null;
    _queue
      ..clear()
      ..addAll(songs);
    _emitQueue();
    await _playAt(index);
  }

  /// 断点恢复：装入上次的播放队列，装载当前曲音源并 seek 到上次进度，
  /// 但**不自动出声**（App 冷启动不打扰用户，点播放即从断点继续）。
  /// 装载失败不抛出：队列与媒体项已就位，_pendingSeek 保留，
  /// 用户点播放时经 play() 重试并补上断点进度。
  Future<void> restoreQueue(
      List<Song> songs, int index, Duration position) async {
    if (songs.isEmpty || index < 0 || index >= songs.length) return;
    // 已有队列（如热重启前会话未销毁）不覆盖，避免把正在播的现场打断。
    if (_queue.isNotEmpty) return;
    _queue
      ..clear()
      ..addAll(songs);
    _emitQueue();
    _pendingSeek = position;
    _pendingSeekSongId = songs[index].id;
    try {
      await _playAt(index, autoplay: false);
      // 恢复装载成功：底层引擎在冷启动后「假就绪」（直接 play 会无声且不被
      // trulyNotPlaying 检出，因 playing 乐观为 true、processingState 非 idle）。
      // 标记首次 play 必须重建底层，而非信任已装载状态。
      _needsColdStartReload = true;
    } catch (_) {
      // 恢复态静默容错：失败提示由用户点播放时的正常路径给出。
    }
  }

  /// 装载音源：file:// 开头走本地文件（已下载歌曲的应用内缓存），
  /// 其余走网络 URL。本地文件不存在时由 setFilePath 抛错，
  /// 走既有的「强刷重解析」兜底（重解析经 urlResolver 会再次自愈/回退网络）。
  Future<void> _loadSource(String url) async {
    if (url.startsWith('file:')) {
      await _player.setFilePath(Uri.parse(url).toFilePath());
    } else {
      await _player.setUrl(url);
    }
  }

  /// 解析音源（缓存 + 并发去重）。命中未过期缓存直接返回；进行中的同 id
  /// 解析直接复用其 Future。[forceRefresh] 跳过缓存强制重解析并覆盖缓存。
  Future<String?> _resolveUrl(int id, {bool forceRefresh = false}) {
    if (!forceRefresh) {
      final hit = _urlCache[id];
      if (hit != null && DateTime.now().difference(hit.at) < _urlCacheTtl) {
        return Future.value(hit.url);
      }
      final pending = _resolving[id];
      if (pending != null) return pending;
    }
    final future = _doResolve(id);
    _resolving[id] = future;
    future.whenComplete(() {
      if (identical(_resolving[id], future)) _resolving.remove(id);
    });
    return future;
  }

  Future<String?> _doResolve(int id) async {
    try {
      final url = await urlResolver?.call(id);
      if (url != null && url.isNotEmpty) {
        if (_urlCache.length >= _urlCacheMax) {
          _urlCache.remove(_urlCache.keys.first); // Map 保序：最旧先出
        }
        _urlCache[id] = _ResolvedUrl(url, DateTime.now());
      } else {
        _urlCache.remove(id); // 解析为空不缓存，播放时会再试
      }
      return url;
    } catch (_) {
      // 解析异常不缓存：预取场景静默失败，播放时自然重试。
      _urlCache.remove(id);
      rethrow;
    }
  }

  /// 按播放模式推算下一曲并后台预解析其音源（fire-and-forget，失败静默）。
  /// 单曲循环不换歌、随机无法预测，不预取。
  void _prefetchNextUrl() {
    int? next;
    switch (_playMode) {
      case PlayMode.sequential:
        if (_queueIndex < _queue.length - 1) next = _queueIndex + 1;
      case PlayMode.loop:
        if (_queue.isNotEmpty) next = (_queueIndex + 1) % _queue.length;
      case PlayMode.repeatOne:
      case PlayMode.shuffle:
        break;
    }
    if (next == null ||
        next < 0 ||
        next >= _queue.length ||
        next == _queueIndex) {
      return;
    }
    unawaited(_resolveUrl(_queue[next].id).catchError((_) => null));
  }

  /// 内部切歌入口：包装 [_doPlayAt]，记录在飞 Future 供 play() 在恢复
  /// 窗口期等待接管。异常语义与原实现一致（由调用方决定是否容错）。
  Future<void> _playAt(int index, {bool autoplay = true}) {
    final f = _doPlayAt(index, autoplay: autoplay);
    _playAtInFlight = f;
    unawaited(f.whenComplete(() {
      if (identical(_playAtInFlight, f)) _playAtInFlight = null;
    }).catchError((Object _) {}));
    return f;
  }

  /// 内部切歌。[autoplay]=false 为断点恢复装载：只把音源加载进播放器并
  /// seek 到断点，不自动出声、不记历史（用户点播放时才真正开播）。
  Future<void> _doPlayAt(int index, {bool autoplay = true}) async {
    if (index < 0 || index >= _queue.length) return;
    // 并发切歌编号：本调用在每个 await 后确认自己仍是「最新一次切歌」，
    // 否则立即退出，把音源加载的所有权让给新调用（见 _playSeq 注释）。
    final seq = ++_playSeq;
    _playAtRunning = true;
    _queueIndex = index;
    _emitQueue();
    final song = _queue[index];
    _current = song;
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.name,
      artist: song.artistName,
      album: song.album.name,
      duration: Duration(milliseconds: song.duration),
      // 通知/锁屏封面：与 SafeNetworkImage 策略一致——music.126.net 图床优先 http
      // （Android 部分出口 https 反爬 403），失败场景再由系统端降级。
      artUri: song.coverUrl.isEmpty
          ? null
          : Uri.tryParse(song.coverUrl.contains('music.126.net')
              ? song.coverUrl.replaceFirst('https://', 'http://')
              : song.coverUrl.replaceFirst('http://', 'https://')),
    ));
    try {
      if (autoplay) {
        // 用户切歌 / 点播：按钮立即回 ⏸、封面立即盖 loading，不等解析与装载；
        // 失败/超时会在下方 catch 里回滚并提示。
        _setPlayIntent(true);
        _markPreparing(song.id);
      }
      // 加载成功前先标记「无有效音源」，防止此间 play() 复活旧音源。
      _loadedSongId = null;
      // 用户主动切歌/点播：立即停掉旧歌并把进度归零，进入「新歌加载」态。
      // 否则慢接口解析的1~2 秒里，UI 已切到新歌而旧歌还在播、
      // 进度条还在按旧歌的走，观感就是「点了没反应」。
      await _player.pause();
      if (seq != _playSeq) return;
      try {
        await _player.seek(Duration.zero);
      } catch (_) {}
      // 缓存命中时该调用近似同步返回；未命中才等接口解析。
      // 超时上限覆盖懒接口/坏网络，避免 spinner 与乐观按钮无限悬置。
      var url = await _resolveUrl(song.id).timeout(_sourceTimeout);
      if (seq != _playSeq) return;
      if (url == null || url.isEmpty) {
        throw const ApiException(null, '该歌曲暂无可用音源（可能是版权限制）');
      }
      try {
        await _loadSource(url).timeout(_sourceTimeout);
      } on TimeoutException {
        // 超时不再走「强刷重试」，直接交给外层超时回滚，避免总等待翻倍。
        rethrow;
      } catch (_) {
        if (seq != _playSeq) return;
        // 首次加载失败：大概率是缓存链接过期/服务端提前失效，
        // 强刷重解析一次再试；仍失败则抛原异常走外层容错。
        final fresh =
            await _resolveUrl(song.id, forceRefresh: true).timeout(_sourceTimeout);
        if (seq != _playSeq) return;
        if (fresh == null || fresh.isEmpty) rethrow;
        url = fresh;
        await _loadSource(url).timeout(_sourceTimeout);
      }
      if (seq != _playSeq) return;
      _loadedSongId = song.id;
      _loadedAt = DateTime.now();
      _loadedUrl = url;
      // 任何「真正装载成功」都清除冷启动恢复标记：仅 restoreQueue 的
      // autoplay=false 装载会在 _playAt 完成后重新置位（见 restoreQueue），
      // 故标记只在该特殊路径下短暂存在、由首次 play() 消费，切歌等正常
      // 装载不会残留导致重复重载。同时清除可疑停滞标记（假播放已解除）。
      _needsColdStartReload = false;
      _suspectStall = false;
      // 透明播放缓存：音源真正加载成功后登记/落盘（恢复装载与正常起播都触发）。
      onSongLoaded?.call(song, url);
      // 本地文件等无预置时长的曲目（duration=0）：装载成功后用播放器实测
      // 时长回填媒体通知 / 迷你条进度（durationStream 会重放最新值，监听一次即可）。
      if (song.duration <= 0) {
        unawaited(_player.durationStream.first.then((d) {
          if (seq != _playSeq || d == null || d <= Duration.zero) return;
          if (_current?.id != song.id) return;
          final m = mediaItem.valueOrNull;
          if (m != null &&
              (m.duration == null || m.duration! <= Duration.zero)) {
            mediaItem.add(m.copyWith(duration: d));
          }
        }).catchError((Object _) {}));
      }
      // 断点恢复：装载完成后 seek 到上次退出时的进度（仅此一次生效）。
      final seekTo = _pendingSeekSongId == song.id ? _pendingSeek : null;
      _pendingSeek = null;
      _pendingSeekSongId = null;
      if (seekTo != null) {
        try {
          await _player.seek(seekTo);
        } catch (_) {}
        if (seq != _playSeq) return;
      }
      if (!autoplay) {
        // 恢复态：停在已装载 + 断点进度，等用户点播放；不预取、不记历史。
        _playAtRunning = false;
        return;
      }
      // 用户在装载窗口内点了暂停：音源已就绪但不起播（否则会出现
      // 「按了暂停却自己播起来」）。pause() 已撤下 loading 并回 ▶。
      // 用持久意图 [_userWantsPlaying] 判断：_playIntent 可能已被播放事件
      // 消费成 null（装载窗口内的旧歌事件），不能代表用户最后一次操作。
      if (!_userWantsPlaying) {
        _endPreparing(song.id);
        _playAtRunning = false;
        return;
      }
      // 起播前重新激活音频会话/焦点（后台恢复后可能已被系统释放）。
      // 失败也继续尝试起播，由播放看门狗统一判定并自愈，避免重复提示。
      if (!await _ensureSessionActive()) {
        _log('playAt[session] 会话激活失败，仍尝试起播');
        if (seq != _playSeq) return;
      }
      // 不 await play()：just_audio 的 play() Future 只在暂停/播完时才完成，
      // 正常播放期间永不返回；播放失败由看门狗与 playbackState 体现。
      _startPlayback('装载完成起播');
      // 音源已装载完成，撤下 loading（后续真正出声由 _onPlaybackEvent 兜底）。
      _endPreparing(song.id);
      // 音源加载成功即记为一次播放（播放历史 + 收听统计）。
      onSongStarted?.call(song);
      _songStartedController.add(song);
      // 后台预取下一曲音源，弱化下一次切歌的接口等待。
      _prefetchNextUrl();
    } on TimeoutException {
      // 解析/装载超时：回滚乐观态与 loading，避免长期「显示在播却没声音」。
      if (seq == _playSeq) {
        _playAtRunning = false;
        _rollbackPlayIntent();
        _endPreparing(song.id);
        if (autoplay) _playErrorController.add('音源获取超时，请稍后重试');
      }
    } on ApiException {
      // 已被更新的切歌取代时不改播放状态（新调用拥有状态），但仍然
      // 上抛，让本次调用方结束等待。
      if (seq == _playSeq) {
        _playAtRunning = false;
        _rollbackPlayIntent();
        _endPreparing(song.id);
      }
      rethrow;
    } catch (e) {
      // 加载异常（网络/解码等）：置为暂停态，不打断整体流程。
      if (seq == _playSeq) {
        _playAtRunning = false;
        _rollbackPlayIntent();
        _endPreparing(song.id);
        // 上抛路径（playQueue）由调用方提示；此处兜住的是静默路径，
        // 必须经广播流给出失败反馈，否则用户只看到按钮回了 ▶。
        if (autoplay) _playErrorController.add('播放失败，请稍后重试');
      }
    }
    if (seq == _playSeq) _playAtRunning = false;
  }

  /// 跳到队列中的指定曲目（切歌失败静默置暂停，不抛出）。
  Future<void> skipToIndex(int index) => _safePlayAt(index);

  /// 是否存在下一曲（UI 置灰按钮用）：循环/单曲循环/随机总可切，
  /// 顺序模式需未到队尾；空队列一律 false。
  bool get hasNext {
    if (_queue.isEmpty) return false;
    switch (_playMode) {
      case PlayMode.sequential:
        return _queueIndex < _queue.length - 1;
      case PlayMode.loop:
      case PlayMode.repeatOne:
      case PlayMode.shuffle:
        return true;
    }
  }

  /// 是否存在上一曲：播放超过 3 秒总是可用（回到本曲开头），
  /// 否则需不在队首；空队列 false。
  bool get hasPrev =>
      _queue.isNotEmpty &&
      (_player.position.inSeconds >= 3 || _queueIndex > 0);

  /// 追加曲目到当前队列末尾（按 id 去重）；队列空闲/为空时直接作为新队列播放。
  Future<void> appendToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    if (_queue.isEmpty || _queueIndex < 0) {
      await playQueue(songs, 0);
      return;
    }
    final ids = _queue.map((s) => s.id).toSet();
    _queue.addAll(songs.where((s) => !ids.contains(s.id)));
    _emitQueue();
  }

  /// 下首播放：把 [songs] 插入当前曲目之后，下一曲即其中第一首（按 id 去重）。
  /// 空队列 / 空闲态直接作为新队列起播（与 [appendToQueue] 一致）。
  Future<void> insertNext(List<Song> songs) async {
    if (songs.isEmpty) return;
    if (_queue.isEmpty || _queueIndex < 0) {
      await playQueue(songs, 0);
      return;
    }
    final ids = _queue.map((s) => s.id).toSet();
    final toInsert = songs.where((s) => !ids.contains(s.id)).toList();
    if (toInsert.isEmpty) return;
    _queue.insertAll(_queueIndex + 1, toInsert);
    _emitQueue();
  }

  /// 从队列移除指定曲目；正在播放的曲目不允许移除。
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length || index == _queueIndex) return;
    _queue.removeAt(index);
    if (index < _queueIndex) _queueIndex--;
    _emitQueue();
  }

  /// 清空播放队列并停止播放（回待机态）。
  Future<void> clearQueue() async {
    _endPlayWatchdog();
    try {
      await _player.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    // 作废在飞的 _playAt：清空后其音源加载结果不得再落进播放器/状态。
    _playSeq++;
    _playAtRunning = false;
    _playIntent = null;
    _userWantsPlaying = false;
    _healAttempts = 0;
    _intentWatchdog?.cancel();
    _intentWatchdog = null;
    _endPreparing();
    _queue.clear();
    _queueIndex = -1;
    _current = null;
    _loadedSongId = null;
    _loadedAt = null;
    _loadedUrl = null;
    _pendingSeek = null;
    _pendingSeekSongId = null;
    mediaItem.add(null);
    _emitQueue();
  }

  /// 设置播放模式（UI 与持久化层同步调用）。
  void setPlayMode(PlayMode mode) => _playMode = mode;

  // -------------------------------------------------------------------------
  // 播放器自愈（结构性）：看门狗 → 销毁旧实例 → 重建 → seek 回原位 → 恢复播放
  // -------------------------------------------------------------------------

  /// 统一发起起播。不 await：just_audio 的 `play()` Future 语义是「被暂停 /
  /// 停止 / 播完才完成」，正常播放期间永不返回，await 会把调用方挂死。
  /// 起播后挂看门狗，超时未真正进入播放态即判定播放器失效并重建。
  void _startPlayback(String reason) {
    _armPlayWatchdog(reason);
    unawaited(_player.play().catchError((Object e) {
      _log('play[error] $reason: $e');
      unawaited(_autoHeal('平台起播异常($reason)'));
    }));
  }

  void _armPlayWatchdog(String reason) {
    _playWatchdog?.cancel();
    _watchdogStartPosition = _player.position;
    final epoch = ++_watchdogEpoch;
    _playWatchdog =
        Timer(playStartTimeout, () => _onPlayWatchdog(epoch, reason));
    _log('watchdog[arm] $reason timeout=${playStartTimeout.inMilliseconds}ms '
        'startPos=${_watchdogStartPosition.inMilliseconds}ms');
  }

  void _endPlayWatchdog() {
    _playWatchdog?.cancel();
    _playWatchdog = null;
    _watchdogEpoch++;
  }

  /// 看门狗超时判定：在播 + 处理态有效 + 进度推进，缺一即判失效。
  void _onPlayWatchdog(int epoch, String reason) {
    if (epoch != _watchdogEpoch) return;
    _playWatchdog = null;
    // 用户已暂停 / 已切歌：本次起播请求作废，不触发重建。
    if (!_userWantsPlaying && _playIntent != true) return;
    final playing = _player.playing;
    final state = _player.processingState;
    final progressed = _player.position - _watchdogStartPosition;
    // buffering/loading 属于正常等待（弱网下可能超过看门狗窗口），不判失效；
    // ready 态则要求进度真的前进——「假播放」的表现就是标志为真、进度不动。
    final stateOk = state == ProcessingState.ready ||
        state == ProcessingState.buffering ||
        state == ProcessingState.loading;
    final valid = playing && stateOk && progressed > Duration.zero;
    _log('watchdog[check] $reason playing=$playing state=$state '
        'progressed=${progressed.inMilliseconds}ms valid=$valid');
    if (valid) {
      _healAttempts = 0;
      return;
    }
    _playErrorController.add('播放无响应，正在自动恢复…');
    unawaited(_autoHeal('播放请求超时($reason)'));
  }

  /// 自愈入口：保存现场 → 重建播放器 → 回到原进度并恢复播放意图。
  /// 连续失败超过 [_maxHealAttempts] 次即落到明确错误态（可再点播放重试）。
  Future<void> _autoHeal(String reason) async {
    final song = _current;
    if (song == null || _queueIndex < 0) return;
    if (_healing) {
      _log('recover[skip] 已有重建在飞');
      return;
    }
    if (_healAttempts >= _maxHealAttempts) {
      _log('recover[abort] 连续 $_healAttempts 次失败');
      _failPlayback('播放器恢复失败，请点击播放重试');
      return;
    }
    final resumeAt = _player.position;
    final wantPlay = _userWantsPlaying || _playIntent == true;
    _log('recover[start] $reason wantPlay=$wantPlay '
        'pos=${resumeAt.inMilliseconds}ms');
    final ok = await _rebuildPlayer(
        resumeAt: resumeAt, autoplay: wantPlay, reason: reason);
    if (!ok) {
      _failPlayback('播放器恢复失败，请点击播放重试');
    }
  }

  /// 现场保存 + 销毁旧播放器 + 新建实例 + 重新装载音源 + seek 回原位 +
  /// （可选）恢复播放。返回 false 表示重建失败（调用方负责落错误态）。
  Future<bool> _rebuildPlayer({
    required Duration resumeAt,
    required bool autoplay,
    required String reason,
  }) async {
    final song = _current;
    if (song == null || _queueIndex < 0) return false;
    if (_healing) return false;
    _healing = true;
    _healAttempts++;
    _endPlayWatchdog();
    _log('recover[begin] reason=$reason attempt=$_healAttempts '
        'resumeAt=${resumeAt.inMilliseconds}ms song=${song.id}');
    try {
      // 音源归属先作废：重建窗口内任何 _playAt/事件都不得把它当成有效音源。
      _loadedSongId = null;
      _loadedAt = null;
      _suspectStall = true;
      await _disposeCurrentPlayer();
      _player = AudioPlayer();
      _bindPlayer();
      // 重新解析直链（跳过可能已过期的缓存）；解析失败时退回上次的音源。
      String? url;
      try {
        url = await _resolveUrl(song.id, forceRefresh: true)
            .timeout(_sourceTimeout);
      } catch (_) {
        url = null;
      }
      final fallback = _loadedUrl;
      if ((url == null || url.isEmpty) && fallback != null && fallback.isNotEmpty) {
        url = fallback;
        _log('recover[resolve] 解析失败，退回上次音源');
      }
      if (url == null || url.isEmpty) {
        _log('recover[abort] 无可装载音源');
        return false;
      }
      await _loadSource(url).timeout(_sourceTimeout);
      _loadedUrl = url;
      _loadedSongId = song.id;
      _loadedAt = DateTime.now();
      if (resumeAt > Duration.zero) {
        try {
          await _player.seek(resumeAt).timeout(_sessionTimeout);
        } catch (_) {}
      }
      _suspectStall = false;
      _log('recover[ready] pos=${_player.position.inMilliseconds}ms '
          'autoplay=$autoplay');
      if (autoplay) {
        // 重新置位乐观意图：重建可能耗时较久，避免旧意图看门狗中途回滚。
        _setPlayIntent(true);
        _startPlayback('重建后起播');
      }
      // 注意不在此清零 _healAttempts：只有真正观测到在播才算成功
      // （_onPlaybackEvent / 看门狗判定），否则连续失败会无限重建。
      return true;
    } catch (e) {
      _log('recover[error] $e');
      _suspectStall = true;
      _loadedSongId = null;
      playbackState.add(playbackState.value.copyWith(playing: false));
      return false;
    } finally {
      _healing = false;
    }
  }

  /// 拆除当前播放器：先解绑事件订阅，再尽力停/销毁。所有平台调用都带超时
  /// ——失效实例的 Future 可能永不返回，不能让拆解再次卡死自愈流程。
  Future<void> _disposeCurrentPlayer() async {
    _playbackSub?.cancel();
    _processingSub?.cancel();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _playbackSub = null;
    _processingSub = null;
    _positionSub = null;
    _bufferedSub = null;
    final old = _player;
    try {
      await old.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await old.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _log('recover[dispose] 旧播放器已拆除');
  }

  /// 落到明确的错误态：按钮回 ▶、loading 撤下、给出可重试的可见提示。
  void _failPlayback(String message) {
    _log('recover[fail] $message');
    _endPlayWatchdog();
    _suspectStall = true;
    _rollbackPlayIntent();
    _endPreparing();
    playbackState.add(playbackState.value.copyWith(playing: false));
    _playErrorController.add(message);
  }

  @override
  Future<void> play() async {
    final song = _current;
    if (song == null) return; // 队列已清空，无可播放对象
    // 乐观更新：点按瞬间回 ⏸，不等音频会话激活与音源装载。
    // 失败/超时会由 _doPlayAt 或看门狗回滚。
    _setPlayIntent(true);
    _interruptedPause = false;
    // 用户显式点播放 = 新的一次交互：重置自愈预算，保证错误态下可重试。
    _healAttempts = 0;
    // 每次起播前重新申请音频焦点 / 激活会话。长挂起（ColorOS 后台 1 小时）
    // 后系统已释放焦点，不重新激活会出现「播放成功但无声」；且平台通道可能
    // 被冻结导致 setActive 永不返回，必须带超时（见 _ensureSessionActive）。
    final sessionOk = await _ensureSessionActive();
    _log('play[request] song=${song.id} session=$sessionOk '
        'loaded=$_loadedSongId playing=${_player.playing}');
    // 等待音频会话激活期间用户可能又点了暂停：本次起播作废，保持暂停态，
    // 否则会出现「UI 显示暂停、声音却在放」的错位。
    if (!_userWantsPlaying) {
      _endPreparing(song.id);
      return;
    }
    if (!sessionOk && !_player.playing) {
      // 会话激活无响应且底层未在播：音频栈已失联，直接走结构性重建。
      _playErrorController.add('音频会话无响应，正在自动恢复…');
      await _autoHeal('音频会话激活失败');
      return;
    }
    // 当前曲音源从未加载成功（如无解灰接口的 VIP 歌曲解析失败）：
    // 播放器里装的还是上一首的音源，直接 play() 会把旧歌复活
    // （UI 已是新歌、声音却是旧歌）。改为重试解析当前曲，
    // 再次失败则保持暂停（由 _playAt 的失败态兜底）。
    if (_loadedSongId != song.id) {
      // 同曲已有一轮 _playAt 在飞（最典型：冷启动断点恢复是
      // fire-and-forget，慢网/接口冷启动下窗口可达数十秒）：等待在飞
      // 装载完成后接管起播，而不是静默吞掉本次点击——旧逻辑用户在恢复
      // 窗口内点 ▶ 毫无反应，观感即「点了不播、须关播放条才能修」。
      if (_playAtRunning) {
        // 恢复装载在飞（autoplay=false）时，本次点击要自己标记获取中，
        // 否则封面 loading 不会出现。
        _markPreparing(song.id);
        final inFlight = _playAtInFlight;
        if (inFlight != null) {
          try {
            await inFlight.timeout(_sourceTimeout + const Duration(seconds: 1));
          } catch (_) {}
        }
        // 等待期间可能已切到别的歌（快速连点/自动推进），本点击作废。
        if (_current != song) return;
        if (_loadedSongId != song.id) {
          // 在飞装载失败：重试一次（失败经 playErrorStream 提示）。
          await _safePlayAt(_queueIndex);
          return;
        }
        // 等待装载期间用户可能又点了暂停：不安播。
        if (!_userWantsPlaying) {
          _endPreparing(song.id);
          return;
        }
        // 在飞装载已按用户意图自行起播时，_player.play() 是空操作（
        // just_audio 对 playing==true 直接返回），不会产生重复平台请求。
        _startPlayback('装载窗口接管起播');
        _endPreparing(song.id);
        return;
      }
      await _safePlayAt(_queueIndex);
      return;
    }
    // 音源已装载：据冷启动恢复态 / 直链 TTL 决定「重建」还是「直接续播」。
    // 旧实现两条路径都复用同一个 AudioPlayer 重装载，而长后台后底层实例
    // 可能已僵死（setUrl/play 的 Future 永不返回），复用只会再卡死一次；
    // 故「需要重载」的场景一律换成销毁重建（换新实例）。
    var needsReload = false;
    if (_needsColdStartReload) {
      _needsColdStartReload = false;
      needsReload = true;
    } else {
      final loadedAt = _loadedAt;
      if (loadedAt != null &&
          DateTime.now().difference(loadedAt) > _loadedUrlMaxAge) {
        needsReload = true;
      }
    }
    final pauseEpochAtPlayStart = _pauseEpoch;
    if (needsReload) {
      final resumeAt = _player.position;
      _loadedSongId = null;
      _loadedAt = null;
      _log('play[rebuild] 冷启动/直链过期 resumeAt=${resumeAt.inMilliseconds}ms');
      final ok =
          await _rebuildPlayer(resumeAt: resumeAt, autoplay: true, reason: '冷启动或直链过期');
      if (!ok) {
        // 重建失败：退回旧实例重装载路径再试一次（失败经 playErrorStream 提示）。
        _pendingSeek = resumeAt;
        _pendingSeekSongId = song.id;
        await _safePlayAt(_queueIndex);
      }
    } else {
      final before = _player.position;
      // 音源已在播放器内，无需再等网络：撤下可能残留的 loading。
      _endPreparing(song.id);
      // 不 await 平台 play（just_audio 的 Future 只在暂停/播完时完成），
      // 由看门狗确认是否真的进入播放态。
      _startPlayback('直接续播');
      // 另做一次 350ms 的即时确认，覆盖「假播放」（标志为 true、进度不动）。
      unawaited(_confirmPlaybackStarted(song, pauseEpochAtPlayStart, before));
    }
  }

  /// 播放后单次确认：just_audio 在长后台/系统回收后可能进入「假播放」——
  /// 底层把 playing 乐观置 true、processingState 仍为 ready（非 idle），但
  /// 实际无音频输出（音频焦点/路由被系统收回）。此时 playing/idle 标志判断
  /// 全部失效，只能靠「播放后进度是否真推进」来识别。play() 后短延时比对
  /// position，未推进即判定底层未真正起播，强制重建解码管线（保留断点）。
  /// 仅确认一次、非循环看门狗；用户中途暂停/切歌则作废本次确认。
  Future<void> _confirmPlaybackStarted(
      Song song, int epoch, Duration before) async {
    await Future.delayed(const Duration(milliseconds: 350));
    if (_pauseEpoch != epoch || _current?.id != song.id) return;
    final progressed = _player.position > before;
    final idle = _player.processingState == ProcessingState.idle;
    if (!_player.playing || idle || !progressed) {
      // 底层未真正起播（假播放）：标记可疑停滞让 UI 先回显 ▶，再走结构性
      // 重建（保存进度 → 销毁旧实例 → 重建 → seek 回原位 → 恢复播放）。
      _log('confirm[stall] playing=${_player.playing} idle=$idle '
          'progressed=$progressed');
      _suspectStall = true;
      _playIntent = null;
      _intentWatchdog?.cancel();
      _intentWatchdog = null;
      playbackState.add(playbackState.value.copyWith(playing: false));
      await _autoHeal('播放后进度未推进');
    } else if (_suspectStall) {
      // 真在播：清除可疑停滞标记，恢复正确的播放态显示（_onPlaybackEvent
      // 后续会据此重算，此处主动刷新一次避免图标滞留 ▶）。
      _suspectStall = false;
      _healAttempts = 0;
      playbackState.add(playbackState.value.copyWith(playing: true));
    }
  }

  /// 应用从后台回到前台（AppLifecycleState.resumed）时由 QueueSnapshotStore
  /// 调用：做一次「快照 → 会话/焦点 → 状态对账 → 必要时自愈」。
  ///
  /// 这里**不做**预防性音源重载（早期实现那样）——回前台瞬间 `setUrl` 会重新
  /// 缓冲造成停顿、`autoplay=false` 还会把正在播放的音乐顺手暂停；而且把
  /// `_loadedAt` 刷成「刚刚」会废掉 play() 的直链过期判断。
  ///
  /// 但 ColorOS 这类激进后台管控会在长时间挂起后冻结进程/回收音频引擎，
  /// 回来时 UI 状态与底层真实状态可能已分叉（Dart 侧 playing 仍为 true 却无声、
  /// 会话被系统 deactivate、旧实例 Future 永不返回）。故此处以真实状态校正
  /// UI 覆盖层，并把「陈旧引擎」标记为下次起播必须重建（[_needsColdStartReload]），
  /// 从根上避免「复用僵死实例重装载 → 点播放无反应」。
  Future<void> reactivateForForeground() async {
    final song = _current;
    if (song == null || _queue.isEmpty) return;
    final loadedAge =
        _loadedAt == null ? null : DateTime.now().difference(_loadedAt!);
    // 真机复现（OPPO/ColorOS 长后台）时这行日志就是断点判据：playing /
    // processingState / position / 音源装载时长 / 双方意图是否一致。
    _log('resume[snapshot] playing=${_player.playing} '
        'state=${_player.processingState} '
        'position=${_player.position.inMilliseconds}ms '
        'loaded=$_loadedSongId loadedAge=${loadedAge?.inMinutes}min '
        'intent=$_playIntent userWants=$_userWantsPlaying '
        'hasUrl=${_loadedUrl != null}');

    // ① 重新申请音频焦点：仅当本端「在播」或「用户希望播放」时才抢焦点，
    //    用户主动暂停后回到前台不应抢占其他 App 的音乐。
    final needSession = _player.playing || _userWantsPlaying;
    if (needSession) {
      final ok = await _ensureSessionActive();
      _log('resume[session] active=$ok');
      if (!ok && _userWantsPlaying && !_player.playing) {
        _log('resume[session] 会话失联 → 重建');
        await _autoHeal('回前台音频会话失联');
        return;
      }
    }

    // ② UI 覆盖层与真实态分叉：以真实状态为准（避免按钮停在 ⏸ 而底层已停）。
    if (_playIntent != null && _playIntent != _actualPlaying) {
      _log('resume[reconcile] 意图=$_playIntent 真实=$_actualPlaying → 以真实为准');
      _playIntent = null;
      _intentWatchdog?.cancel();
      _intentWatchdog = null;
      playbackState.add(playbackState.value.copyWith(playing: _actualPlaying));
    }

    // ③ 用户意图在播、但底层实际未播（含假播放）→ 触发一次结构性修复。
    if (_userWantsPlaying && !_actualPlaying) {
      _log('resume[repair] 意图在播但真实未播 → 重建');
      await _autoHeal('回前台状态不一致');
      return;
    }

    // ④ 已暂停 + 音源陈旧：本次回前台不重载（避免正在播放时的重缓冲停顿），
    //    但标记「下次起播必须换新实例」——长时间冻结后复用旧 AudioPlayer
    //    重装载正是「点播放没反应」的根因。
    if (!_player.playing &&
        loadedAge != null &&
        loadedAge > staleEngineAfter &&
        _loadedSongId == song.id) {
      _needsColdStartReload = true;
      _log('resume[stale] 音源已装载 ${loadedAge.inMinutes}min，'
          '下次起播将重建播放器');
    }

    // ⑤ 看起来在播：确认进度是否真推进，未推进（假播放）则重建。
    if (_player.playing) {
      unawaited(_confirmPlaybackStarted(song, _pauseEpoch, _player.position));
    }
  }

  /// 播放/暂停切换（播放页与大按钮、迷你条统一入口）。
  /// 以乐观意图优先判断，快速连点不会因 UI 未重建而读到旧状态：
  /// 每次点按都在「上一次意图」上翻转（播放/暂停交替、不堆叠请求）。
  Future<void> togglePlayPause() =>
      (_playIntent ?? _actualPlaying) ? pause() : play();

  /// 记录一次用户意图暂停（代次 +1）后暂停底层播放器。
  @override
  Future<void> pause() {
    _pauseEpoch++;
    _interruptedPause = false;
    // 用户已明确暂停：本次起播请求的看门狗作废。
    _endPlayWatchdog();
    // 立即回显 ▶ 并撤下 loading：暂停不该等网络。若音源仍在装载，
    // _doPlayAt 末尾会因意图为「暂停」而不自动起播。
    _setPlayIntent(false);
    _endPreparing();
    // 平台 pause 也可能因引擎僵死而永不返回，带超时兜底（UI 已先行更新）。
    return _player.pause().timeout(const Duration(seconds: 2), onTimeout: () {});
  }
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// 下一首：按播放模式取下一曲。
  @override
  /// 下一首。返回 false 表示已到队列边界（无下一曲），供 UI 提示。
  @override
  Future<bool> skipToNext() => _advance(auto: false);

  /// 上一首：播放超过 3 秒先回到本曲开头；已在队首且播放不足 3 秒
  /// 时返回 false（没有上一曲），供 UI 提示。seek 全程容错防闪退。
  @override
  Future<bool> skipToPrevious() async {
    if (_queue.isEmpty) return false;
    if (_player.position.inSeconds >= 3) {
      try {
        await _player.seek(Duration.zero);
      } catch (_) {}
      return true;
    }
    if (_queueIndex <= 0) return false;
    await _safePlayAt(_queueIndex - 1);
    return true;
  }
}
