import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
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
  void Function(Song song)? onSongStarted;

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

  /// 断点续听：待恢复的播放进度与目标曲目。音源装载成功后 seek 一次即作废；
  /// 目标不匹配的 _playAt 也会作废它，避免后续切歌误跳回旧断点。
  Duration? _pendingSeek;
  int? _pendingSeekSongId;

  /// 当前音源装载时刻：play() 据此判断是否可能已过期（断点恢复后迟迟未播、
  /// 或久置后才点播），过期先原地重载再播，防止拿失效直链硬播后无声。
  DateTime? _loadedAt;
  static const Duration _loadedUrlMaxAge = Duration(minutes: 15);

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
        onError: (Object _, StackTrace __) {});
    _player.processingStateStream.listen(_onProcessingState,
        onError: (Object _, StackTrace __) {});
    _queueController.add(const QueueSnapshot([], -1));
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
      playing: _player.playing,
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

  /// 内部切歌。[autoplay]=false 为断点恢复装载：只把音源加载进播放器并
  /// seek 到断点，不自动出声、不记历史（用户点播放时才真正开播）。
  Future<void> _playAt(int index, {bool autoplay = true}) async {
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
        await _player.setUrl(url);
      } catch (_) {
        if (seq != _playSeq) return;
        // 首次加载失败：大概率是缓存链接过期/服务端提前失效，
        // 强刷重解析一次再试；仍失败则抛原异常走外层容错。
        final fresh = await _resolveUrl(song.id, forceRefresh: true);
        if (seq != _playSeq) return;
        if (fresh == null || fresh.isEmpty) rethrow;
        url = fresh;
        await _player.setUrl(url);
      }
      if (seq != _playSeq) return;
      _loadedSongId = song.id;
      _loadedAt = DateTime.now();
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
      // 会卡住调用方的导航；播放失败由 playbackState 体现。
      unawaited(_player.play());
      // 音源加载成功即记为一次播放（播放历史）。
      onSongStarted?.call(song);
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
    // 当前曲音源从未加载成功（如无解灰接口的 VIP 歌曲解析失败）：
    // 播放器里装的还是上一首的音源，直接 play() 会把旧歌复活
    // （UI 已是新歌、声音却是旧歌）。改为重试解析当前曲，
    // 再次失败则保持暂停（由 _playAt 的失败态兜底）。
    if (_loadedSongId != song.id) {
      // 同曲已有一轮 _playAt 在飞（如播放页进入时的自动推进撞上列表
      // 起播）：交给在飞调用完成，避免同曲并发重入导致重复 setUrl、
      // 进度重置或新旧音源互相覆盖。
      if (_playAtRunning) return;
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
    await _player.play();
  }
  @override
  Future<void> pause() => _player.pause();
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
