import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
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
  final AudioPlayer _player = AudioPlayer();
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
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  bool get isPlaying => _player.playing;

  NcmAudioHandler() {
    // 关键：这两个 stream 会发射**错误事件**（ExoPlayer 播放错误、音源
    // 加载失败等，切歌时最常见）。错误不经过 onData 回调，try/catch 拦不住；
    // 不带 onError 监听 → 错误进 zone → release 包直接闪退（Web 端实现
    // 不同不发射，所以 Web 正常）。官方文档要求必须带 onError。
    _player.playbackEventStream.listen(_onPlaybackEvent,
        onError: (Object _, StackTrace __) => _onPlayerError());
    _player.processingStateStream.listen(_onProcessingState,
        onError: (Object _, StackTrace __) {});
    _queueController.add(const QueueSnapshot([], -1));
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
      await _advance(auto: true);
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
            unawaited(_player.play());
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

  void _onPlaybackEvent(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      // 与音源归属联动：平台层报错后 just_audio 的 playing 标志可能卡在
      // true（与实际发声脱节），后续任何播放事件都会把播放态刷回去。
      // 无有效音源（_loadedSongId 为空）时一律视为未播放，UI 恒显示 ▶，
      // 点播放走 play() 的重装载自愈路径。
      playing: _player.playing && _loadedSongId != null,
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
      var url = await _resolveUrl(song.id);
      if (seq != _playSeq) return;
      if (url == null || url.isEmpty) {
        throw const ApiException(null, '该歌曲暂无可用音源（可能是版权限制）');
      }
      try {
        await _loadSource(url);
      } catch (_) {
        if (seq != _playSeq) return;
        // 首次加载失败：大概率是缓存链接过期/服务端提前失效，
        // 强刷重解析一次再试；仍失败则抛原异常走外层容错。
        final fresh = await _resolveUrl(song.id, forceRefresh: true);
        if (seq != _playSeq) return;
        if (fresh == null || fresh.isEmpty) rethrow;
        url = fresh;
        await _loadSource(url);
      }
      if (seq != _playSeq) return;
      _loadedSongId = song.id;
      _loadedAt = DateTime.now();
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
      // 不 await play()：个别平台（Web）该 Future 可能迟迟不完成，
      // 会卡住调用方的导航；播放失败由 playbackState 体现。catchError 兜底
      // 防止起播异常（音频会话/焦点未激活）成为未捕获异步错误在 release 闪退。
      unawaited(_player.play().catchError((Object _) {}));
      // 音源加载成功即记为一次播放（播放历史 + 收听统计）。
      onSongStarted?.call(song);
      _songStartedController.add(song);
      // 后台预取下一曲音源，弱化下一次切歌的接口等待。
      _prefetchNextUrl();
    } on ApiException {
      // 已被更新的切歌取代时不改播放状态（新调用拥有状态），但仍然
      // 上抛，让本次调用方结束等待。
      if (seq == _playSeq) {
        _playAtRunning = false;
        playbackState.add(playbackState.value.copyWith(playing: false));
      }
      rethrow;
    } catch (e) {
      // 加载异常（网络/解码等）：置为暂停态，不打断整体流程。
      if (seq == _playSeq) {
        playbackState.add(playbackState.value.copyWith(playing: false));
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
    await _player.stop();
    // 作废在飞的 _playAt：清空后其音源加载结果不得再落进播放器/状态。
    _playSeq++;
    _playAtRunning = false;
    _queue.clear();
    _queueIndex = -1;
    _current = null;
    _loadedSongId = null;
    _loadedAt = null;
    _pendingSeek = null;
    _pendingSeekSongId = null;
    mediaItem.add(null);
    _emitQueue();
  }

  /// 设置播放模式（UI 与持久化层同步调用）。
  void setPlayMode(PlayMode mode) => _playMode = mode;

  @override
  Future<void> play() async {
    final song = _current;
    if (song == null) return; // 队列已清空，无可播放对象
    _interruptedPause = false;
    // 长时间挂起后回到前台，iOS 音频会话会被系统 deactivate；仅重载引擎仍
    // 可能「播放成功但无声」。真正起播前重新激活会话（仅此刻激活，不提前
    // 抢后台其它音频的焦点），用户在后台续播场景（playing 已 true）亦无害。
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
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
        final inFlight = _playAtInFlight;
        if (inFlight != null) {
          try {
            await inFlight;
          } catch (_) {}
        }
        // 等待期间可能已切到别的歌（快速连点/自动推进），本点击作废。
        if (_current != song) return;
        if (_loadedSongId != song.id) {
          // 在飞装载失败：重试一次（失败经 playErrorStream 提示）。
          await _safePlayAt(_queueIndex);
          return;
        }
        await _player.play();
        return;
      }
      await _safePlayAt(_queueIndex);
      return;
    }
    // 音源装载已久（如断点恢复后放置超过 TTL 才点播）：直链大概率已失效，
    // 带当前进度原地重载一次再播，避免拿着过期直链点播无声。
    final loadedAt = _loadedAt;
    if (loadedAt != null && DateTime.now().difference(loadedAt) > _loadedUrlMaxAge) {
      _pendingSeek = _player.position;
      _pendingSeekSongId = song.id;
      await _safePlayAt(_queueIndex);
      return;
    }
    final pauseEpochAtPlayStart = _pauseEpoch;
    var playFailed = false;
    try {
      await _player.play();
    } catch (_) {
      // 冷启动/长期挂起后音频引擎未就绪：play() 可能抛异常（音频焦点/
      // 会话未激活等）。异常会被 zone 静默吞掉，导致「点了没反应、也没报错」，
      // 必须自行捕获并转入自愈，而不是把失败交给 zone。
      playFailed = true;
    }
    // 兜底：audio session 激活失败等场景下 just_audio 的 play() 会抛异常，
    // 或其 playing 被静默回翻为 false（无异常、无错误事件），甚至乐观地立即
    // 置 true 却实际无声（「图标在播、耳朵没声」的假播放）。检测到「未真正
    // 进入播放态」时作废音源归属并自愈，避免「点了永远无声」。
    // 注意：await play() 的 Future 在用户暂停时才完成（见 _pauseEpoch 注释），
    // 期间发生过用户意图暂停（代次变化）说明是正常暂停，不得触发自愈。
    final userPaused = _pauseEpoch != pauseEpochAtPlayStart;
    // 是否「真正没在播」：play() 抛异常、或 playing 为假、或引擎虽报 playing 却
    // 处于 idle（音源未真正就绪，即 just_audio 把 playing 乐观置 true 却实际无声
    // 的「假播放」）。任一成立都需重建解码管线，否则会陷入「点了永远无声、须拖动
    // 进度条才出声」的死局——旧逻辑只判断 !playing，恰好漏掉了 idle 假播放。
    final trulyNotPlaying = playFailed ||
        !_player.playing ||
        _player.processingState == ProcessingState.idle;
    if (!userPaused && trulyNotPlaying) {
      // 不再用「seek 原位置」这种 no-op 唤醒：同位置 seek 不会重建解码管线，正是
      // 此前 Bug 的根。直接重装载（重解析+重载音源，autoplay=true）并从当前进度
      // 续播，无论长/短挂起、引擎是否被系统回收都稳定出声。用户中途暂停（代次变化）
      // 则作废本次自愈，避免覆盖正常暂停。
      if (_pauseEpoch == pauseEpochAtPlayStart) {
        _pendingSeek = _player.position;
        _pendingSeekSongId = song.id;
        _loadedSongId = null;
        _loadedAt = null;
        await _safePlayAt(_queueIndex);
      }
    }
  }

  /// 应用从后台回到前台（AppLifecycleState.resumed）时由 QueueSnapshotStore
  /// 调用。
  ///
  /// 早期实现在此处对当前曲做一次「无声重载」（`_playAt(autoplay:false)` 并重置
  /// `_loadedSongId/_loadedAt`），意图是重建被系统回收的底层引擎。但实测该重载
  /// 正是播放条两个 bug 的根因：
  ///  - 回前台瞬间 `setUrl` 重新缓冲 → 切桌面再切回出现「停顿」，且 `autoplay=false`
  ///    会顺手暂停正在播放的音乐，多次切换后停在暂停态（Bug 2）；
  ///  - 它把 `_loadedAt` 刷新成「刚刚」，废掉了 play() 里「直链过期→重载」的自愈
  ///    分支，使长时间挂起后点播放走「同位置 seek」这条 no-op 自愈而彻底无声（Bug 1）。
  ///
  /// just_audio 在普通前后台切换本就能保留已加载音源与进度、跨前后台续播；真正会
  /// 丢状态的是「进程被杀冷启动」，由 restoreQueue 独立处理。故此处不再重载，让
  /// 引擎保留现场：正在播放则继续播、已暂停则保持暂停，回前台零停顿。长时间挂起后
  /// 若底层引擎确被系统回收，play() 会通过「_loadedAt 过期重载」与末尾「无声自愈」
  /// 兜底重建，无需在此预防性重载。
  Future<void> reactivateForForeground() async {
    if (_current == null || _queue.isEmpty) return;
    // 空实现：保留生命周期回调契约，但不再重载音源/重置 _loadedAt（见上方注释）。
    // 音频会话的重新激活交由 play() 开头处理，避免暂停态下抢其它 App 的音频焦点。
  }

  /// 记录一次用户意图暂停（代次 +1）后暂停底层播放器。
  @override
  Future<void> pause() {
    _pauseEpoch++;
    _interruptedPause = false;
    return _player.pause();
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
