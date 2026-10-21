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

  final StreamController<QueueSnapshot> _queueController =
      StreamController<QueueSnapshot>.broadcast();

  /// 队列变化流（构造时先发一份空快照，保证监听方有初始值）。
  Stream<QueueSnapshot> get queueStream => _queueController.stream;
  QueueSnapshot get currentQueueSnapshot =>
      QueueSnapshot(List.unmodifiable(_queue), _queueIndex);
  List<Song> get songs => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  Song? get currentSong => _current;
  PlayMode get playMode => _playMode;

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
        // 单曲循环：不切歌，回到开头继续播。
        try {
          await _player.seek(Duration.zero);
          unawaited(_player.play());
        } catch (_) {}
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
  Future<void> _safePlayAt(int index) async {
    try {
      await _playAt(index);
    } catch (_) {}
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
    _queue
      ..clear()
      ..addAll(songs);
    _emitQueue();
    await _playAt(index);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
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
      artUri: Uri.tryParse(song.coverUrl),
    ));
    try {
      final url = await urlResolver?.call(song.id);
      if (url == null || url.isEmpty) {
        throw const ApiException(null, '该歌曲暂无可用音源（可能是版权限制）');
      }
      await _player.setUrl(url);
      // 不 await play()：个别平台（Web）该 Future 可能迟迟不完成，
      // 会卡住调用方的导航；播放失败由 playbackState 体现。
      unawaited(_player.play());
      // 音源加载成功即记为一次播放（播放历史）。
      onSongStarted?.call(song);
    } on ApiException {
      playbackState.add(playbackState.value.copyWith(playing: false));
      rethrow;
    } catch (e) {
      // 加载异常（网络/解码等）：置为暂停态，不打断整体流程。
      playbackState.add(playbackState.value.copyWith(playing: false));
    }
  }

  /// 跳到队列中的指定曲目（切歌失败静默置暂停，不抛出）。
  Future<void> skipToIndex(int index) => _safePlayAt(index);

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
    _queue.clear();
    _queueIndex = -1;
    _current = null;
    mediaItem.add(null);
    _emitQueue();
  }

  /// 设置播放模式（UI 与持久化层同步调用）。
  void setPlayMode(PlayMode mode) => _playMode = mode;

  @override
  Future<void> play() => _player.play();
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
