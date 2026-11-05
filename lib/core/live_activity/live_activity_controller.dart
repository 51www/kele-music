// 播放状态 → iOS 实时活动（灵动岛 + 锁屏）的推送控制器。
//
// 职责：
// - 监听当前媒体项 / 播放状态 / 进度流，生成实时活动快照；
// - 换歌时拉取歌词并下载封面字节，交给原生落盘到 App Group；
// - 按「歌词行变化 + 1 秒最小间隔」节流，避免 ActivityKit 被高频更新拖垮；
// - 非 iOS / 系统不支持 / 用户关闭实时活动时完全静默，不影响播放。

import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/api_client.dart';
import '../../data/lrc_parser.dart';
import '../../data/player_repository.dart';
import '../raw_http.dart';
import 'live_activity_bridge.dart';

/// 当前曲目快照（实时活动需要的字段）。
class _TrackInfo {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final Duration duration;

  const _TrackInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.duration,
  });

  _TrackInfo copyWith({Duration? duration}) => _TrackInfo(
        id: id,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        duration: duration ?? this.duration,
      );
}

class LiveActivityController with WidgetsBindingObserver {
  LiveActivityController(this._handler, this._api);

  final NcmAudioHandler _handler;
  final NcmApi _api;
  final LiveActivityBridge _bridge = LiveActivityBridge.instance;
  final Dio _dio = Dio();

  /// 两次推送的最小间隔。进度由 Widget 端的 `ProgressView(timerInterval:)`
  /// 自行推进，Swift 侧只在「歌词行切换 / 播放态变化 / 拖动进度」时更新，
  /// 因此 1 秒足以覆盖歌词粒度，又远低于系统对活动更新频率的容忍上限。
  static const Duration _minPushInterval = Duration(seconds: 1);

  /// 歌词缓存（按歌曲 id，小容量 LRU），避免反复请求同一首歌。
  final Map<int, LyricData> _lyricCache = {};
  static const int _lyricCacheMax = 8;

  final List<StreamSubscription<dynamic>> _subs = [];

  _TrackInfo? _current;
  LyricData? _lyrics;
  int _lyricToken = 0;

  Uint8List? _artworkBytes;
  int? _artworkForSongId;
  bool _artworkPending = false;

  bool _supported = false;
  bool _hasActivity = false;
  bool _disposed = false;

  DateTime _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _throttleTimer;
  int _lastLyricIndex = -2;
  Duration _lastPosition = Duration.zero;
  bool _lastPlaying = false;

  Future<void> start() async {
    if (!LiveActivityBridge.isPlatformSupported) return;
    _subs.add(_handler.mediaItem.listen(_onMediaItem));
    _subs.add(_handler.playbackState.listen(_onPlaybackState));
    _subs.add(_handler.positionStream.listen(_onPosition));
    WidgetsBinding.instance.addObserver(this);

    _supported = await _bridge.checkSupported();
    if (_disposed || !_supported) return;
    // 进程重启后系统里可能仍有上一会话的活动：接续更新而不是重复创建。
    _hasActivity = _bridge.hadRunning;
    _onMediaItem(_handler.mediaItem.valueOrNull);
    if (_handler.isPlaying || _hasActivity) _schedulePush(force: true);
  }

  void _onMediaItem(MediaItem? item) {
    if (_disposed) return;
    if (item == null) {
      _current = null;
      _lyrics = null;
      _lyricToken++;
      _artworkBytes = null;
      _artworkForSongId = null;
      _artworkPending = false;
      if (_hasActivity) {
        _hasActivity = false;
        unawaited(_bridge.end());
      }
      return;
    }
    final id = int.tryParse(item.id) ?? 0;
    final fallbackDuration = _handler.currentSong?.duration ?? 0;
    final duration = (item.duration != null && item.duration! > Duration.zero)
        ? item.duration!
        : Duration(milliseconds: fallbackDuration);
    final cover = _coverUrlFor(item, id);

    if (_current != null && _current!.id == id) {
      // 同一首歌：典型场景是本地文件实测时长回填，只补时长并同步一次。
      if (duration != _current!.duration) {
        _current = _current!.copyWith(duration: duration);
        _schedulePush(force: true);
      }
      return;
    }

    _current = _TrackInfo(
      id: id,
      title: item.title,
      artist: item.artist ?? '',
      album: item.album ?? '',
      coverUrl: cover,
      duration: duration,
    );
    _lyrics = _lyricCache[id];
    _lastLyricIndex = -2;
    _artworkBytes = null;
    _artworkForSongId = null;
    _artworkPending = false;

    unawaited(_loadLyrics(id));
    unawaited(_loadArtwork(id, cover));
    _schedulePush(force: true);
  }

  String _coverUrlFor(MediaItem item, int songId) {
    final song = _handler.currentSong;
    if (song != null && song.id == songId && song.coverUrl.isNotEmpty) {
      return song.coverUrl;
    }
    return item.artUri?.toString() ?? '';
  }

  void _onPlaybackState(PlaybackState state) {
    if (_disposed) return;
    final playing = state.playing;
    if (playing == _lastPlaying) return;
    _lastPlaying = playing;
    if (playing) {
      // 起播时确保歌词就绪（暂停恢复的场景此前可能没拉过）。
      final id = _current?.id;
      if (id != null && _lyrics == null) unawaited(_loadLyrics(id));
      _schedulePush(force: true);
    } else if (_hasActivity) {
      // 暂停：立即推一次，让锁屏进度停在当前位置并显示暂停态。
      _schedulePush(force: true);
    }
  }

  void _onPosition(Duration position) {
    if (_disposed || !_supported) return;
    final lyrics = _lyrics;
    final index = lyrics == null ? -1 : currentLrcIndex(lyrics.lines, position);
    final seeked = (position - _lastPosition).inMilliseconds.abs() > 1500;
    _lastPosition = position;
    final lineChanged = index != _lastLyricIndex;
    _lastLyricIndex = index;

    // 拖动进度条（播放或暂停）：进度锚点已失效，立即重建锚点，
    // 否则 ActivityKit 的 timerInterval 会从旧位置继续走。
    if (seeked && _hasActivity) {
      _schedulePush(force: true);
      return;
    }
    if (lineChanged && (_hasActivity || _handler.isPlaying)) {
      _schedulePush();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_supported) return;
    // 回前台补一次：顺带重试在后台请求失败的活动。
    if (_current != null && (_hasActivity || _handler.isPlaying)) {
      _schedulePush(force: true);
    }
  }

  /// 节流推送：非强制更新合并到 1 秒窗口末尾，强制更新（换歌/暂停/起播/
  /// 封面就绪）立即执行。
  void _schedulePush({bool force = false}) {
    if (_disposed || !_supported) return;
    if (force) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      unawaited(_push());
      return;
    }
    final elapsed = DateTime.now().difference(_lastPushAt);
    if (elapsed >= _minPushInterval) {
      unawaited(_push());
      return;
    }
    _throttleTimer ??= Timer(_minPushInterval - elapsed, () {
      _throttleTimer = null;
      unawaited(_push());
    });
  }

  Future<void> _push() async {
    final track = _current;
    if (track == null) return;
    // 尚未创建活动且没在播放：不主动起活动（避免「暂停态空活动」）。
    if (!_hasActivity && !_handler.isPlaying) return;

    final lyrics = _lyrics;
    final position = _handler.position;
    var lyric = '';
    var translation = '';
    if (lyrics != null) {
      final index = currentLrcIndex(lyrics.lines, position);
      if (index >= 0 && index < lyrics.lines.length) {
        final line = lyrics.lines[index];
        lyric = line.text;
        translation = lyrics.transFor(line.time) ?? '';
      }
    }

    final sendArtwork = _artworkPending && _artworkBytes != null;
    _lastPushAt = DateTime.now();
    final ok = await _bridge.update(LiveActivityPayload(
      songId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      isPlaying: _handler.isPlaying,
      position: position,
      duration: track.duration,
      lyric: lyric,
      translation: translation,
      artworkBytes: sendArtwork ? _artworkBytes : null,
    ));
    if (!ok) return;
    _hasActivity = true;
    if (sendArtwork) _artworkPending = false;
  }

  Future<void> _loadLyrics(int songId) async {
    if (songId <= 0) {
      if (_current?.id == songId) _lyrics = null;
      return;
    }
    final cached = _lyricCache[songId];
    if (cached != null) {
      _lyrics = cached;
      return;
    }
    final token = ++_lyricToken;
    try {
      final lyric = await _api.lyric(songId);
      final data = LyricData(parseLrc(lyric.text), parseLrc(lyric.trans));
      if (_lyricCache.length >= _lyricCacheMax) {
        _lyricCache.remove(_lyricCache.keys.first);
      }
      _lyricCache[songId] = data;
      if (_disposed || token != _lyricToken || _current?.id != songId) return;
      _lyrics = data;
      _lastLyricIndex = -2;
      if (_hasActivity || _handler.isPlaying) _schedulePush(force: true);
    } catch (_) {
      // 歌词失败不影响实时活动：退化为只有歌名/歌手/进度。
      if (!_disposed && token == _lyricToken && _current?.id == songId) {
        _lyrics = null;
      }
    }
  }

  /// 下载封面字节。原生侧负责缩放/落盘到 App Group——Live Activity 不能
  /// 直接加载网络图片，必须落到共享容器供 Widget Extension 读取。
  /// 下载走与 SafeNetworkImage 相同的候选链（p3 节点 / 协议回退 / 裸 socket
  /// 兜底），规避网易图床对非浏览器请求的 WAF 403。
  Future<void> _loadArtwork(int songId, String coverUrl) async {
    if (coverUrl.isEmpty || songId == _artworkForSongId) return;
    final bytes = await _downloadCover(coverUrl);
    if (_disposed || _current?.id != songId) return;
    _artworkForSongId = songId;
    _artworkBytes = bytes;
    if (bytes != null && bytes.isNotEmpty) {
      _artworkPending = true;
      if (_hasActivity || _handler.isPlaying) _schedulePush(force: true);
    }
  }

  Future<Uint8List?> _downloadCover(String url) async {
    for (final candidate in _coverCandidates(url)) {
      try {
        final res = await _dio.get<List<int>>(
          candidate,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 8),
            headers: const {'User-Agent': 'Mozilla/5.0'},
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        final data = res.data;
        if (data != null && data.isNotEmpty) {
          return Uint8List.fromList(data);
        }
      } catch (_) {
        // 换下一个候选。
      }
      final raw = await rawHttpGet(candidate);
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return null;
  }

  /// 与 SafeNetworkImage 一致的封面候选链（原 URL → p3 节点 → 原域 https）。
  List<String> _coverCandidates(String url) {
    var u = url.trim();
    if (u.isEmpty) return const [];
    if (u.startsWith('//')) u = 'https:$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.scheme.isEmpty) return const [];
    if (uri.scheme != 'http' && uri.scheme != 'https') return const [];
    final host = uri.host;
    if (!RegExp(r'^p\d+\.music\.126\.net$').hasMatch(host)) {
      return u.startsWith('https://')
          ? [u, u.replaceFirst('https://', 'http://')]
          : [u, u.replaceFirst('http://', 'https://')];
    }
    final path = uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return [
      u,
      if (host != 'p3.music.126.net') 'http://p3.music.126.net$path$query',
      'https://$host$path$query',
    ];
  }

  void dispose() {
    _disposed = true;
    _throttleTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    WidgetsBinding.instance.removeObserver(this);
  }
}
