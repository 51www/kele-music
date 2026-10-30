import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/constants.dart';
import 'core/local_store.dart';
import 'core/errors.dart';
import 'data/api_client.dart';
import 'data/auth_repository.dart';
import 'data/listen_stats.dart';
import 'data/lrc_parser.dart';
import 'data/models.dart';
import 'data/player_repository.dart';

// UI 层（播放页/导航坞）判断按钮置灰需要 PlayMode，经此 re-export 暴露。
export 'data/player_repository.dart' show PlayMode;

final apiProvider = Provider<NcmApi>((ref) => NcmApi());
final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiProvider), ref.watch(secureStorageProvider)));

/// 全局登录态：unknown（初始化中）→ authenticated / unauthenticated。
/// 路由守卫与 UI 都看这个状态，而非直接读 cookie 是否为空。
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  const AuthState(this.status);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _auth;
  final NcmApi _api;
  AuthNotifier(this._auth, this._api)
      : super(const AuthState(AuthStatus.unknown)) {
    // 服务端返回 301 时统一翻成「未登录」。
    _api.onUnauthorized = () => notifyUnauthorized();
    _init();
  }

  Future<void> _init() async {
    await _auth.init();
    if (!_auth.isLoggedIn) {
      state = const AuthState(AuthStatus.unauthenticated);
      return;
    }
    // 有 cookie：立即乐观置「已登录」——恢复只等本地 IO，不再把登录态
    // 绑在网络续期往返上（慢网络下曾拖到数秒后，个人专属等登录功能迟迟不可用）。
    state = const AuthState(AuthStatus.authenticated);
    // 续期移后台 best-effort：仅明确失效（ok=false / 301）才翻回未登录，
    // 网络异常乐观保留；期间其它请求 301 由 onUnauthorized 统一登出兜底。
    // 翻出前确认仍是 authenticated，避免极慢续期结果覆盖期间的重新登录。
    try {
      final ok = await _auth.refresh();
      if (!ok && state.status == AuthStatus.authenticated) {
        state = const AuthState(AuthStatus.unauthenticated);
      }
    } on ApiException catch (e) {
      if (e.code == 301 && state.status == AuthStatus.authenticated) {
        state = const AuthState(AuthStatus.unauthenticated);
      }
    } catch (_) {
      // 网络异常：乐观保留（与原逻辑一致）。
    }
  }

  /// 被服务端判定失效时调用（来自 NcmApi.onUnauthorized）。
  void notifyUnauthorized() {
    if (state.status == AuthStatus.authenticated) {
      _auth.clearLocal();
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  /// 登录成功后（二维码确认 / 手机验证码）调用。
  /// cookie 有效性已由登录接口本身确认（803 / 验证码通过），
  /// 续期只是 best-effort：失败不阻断登录，后续请求若真失效会经 301 自动登出。
  Future<void> completeLogin() async {
    try {
      await _auth.refresh();
    } catch (_) {
      // 忽略续期异常。
    }
    state = const AuthState(AuthStatus.authenticated);
  }

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(
          ref.watch(authRepositoryProvider),
          ref.watch(apiProvider),
        ));
final audioHandlerProvider = Provider<NcmAudioHandler>(
    (ref) => throw UnimplementedError('overridden in main'));

/// 当前播放媒体项流（用于迷你播放条 / 全屏播放页）。
final currentMediaItemProvider =
    StreamProvider<MediaItem?>((ref) => ref.watch(audioHandlerProvider).mediaItem);
final playbackStateProvider = StreamProvider<PlaybackState>(
    (ref) => ref.watch(audioHandlerProvider).playbackState);

/// 播放失败轻提示流：handler 内部兜底（不上抛）的失败——下一曲/上一曲、
/// 队列页点歌、播放按钮重试、自动切歌等——经此广播，UI 层统一弹 SnackBar。
final playErrorProvider = StreamProvider<String>(
    (ref) => ref.watch(audioHandlerProvider).playErrorStream);

/// 起播前置请求（歌单详情 / 每日推荐拉取）失败的错误态。
/// 这类流程是「先 push 播放页、后拉数据起播」，失败时 currentMediaItem
/// 仍为 null，播放页占位态据此展示失败原因与「返回」出口，避免永远
/// 停在「正在准备播放…」转圈。各 push 播放页入口在跳转前负责清空。
final playStartErrorProvider = StateProvider<String?>((_) => null);

/// 平滑播放进度 / 缓冲进度流：歌词同步与进度动效使用
/// （audio_service 的 playbackState 只在事件时更新，粒度不够）。
final positionStreamProvider = StreamProvider<Duration>(
    (ref) => ref.watch(audioHandlerProvider).positionStream);
final bufferedPositionStreamProvider = StreamProvider<Duration>(
    (ref) => ref.watch(audioHandlerProvider).bufferedPositionStream);

/// 播放队列快照流：队列界面 / 当前曲目下标。
/// 广播流会错过订阅前的事件，这里订阅时先重放当前快照。
final queueProvider = StreamProvider<QueueSnapshot>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  late StreamController<QueueSnapshot> sc;
  sc = StreamController<QueueSnapshot>(
    onListen: () => sc.add(handler.currentQueueSnapshot),
  );
  ref.onDispose(sc.close);
  final sub = handler.queueStream.listen(
    sc.add,
    onError: sc.addError,
    onDone: sc.close,
  );
  ref.onDispose(sub.cancel);
  return sc.stream;
});

/// 歌词数据（按歌曲 id 缓存，离开页面自动释放）。
final lyricProvider = FutureProvider.autoDispose.family<LyricData, int>(
    (ref, songId) async {
  final ly = await ref.watch(apiProvider).lyric(songId);
  return LyricData(parseLrc(ly.text), parseLrc(ly.trans));
});

/// 睡眠定时器：到点自动暂停播放。state=null 表示未启用。
class SleepTimerNotifier extends StateNotifier<Duration?> {
  final NcmAudioHandler _handler;
  Timer? _ticker;

  SleepTimerNotifier(this._handler) : super(null);

  /// 启动/重设倒计时；到点暂停播放并清空状态。
  void start(Duration duration) {
    _ticker?.cancel();
    state = duration;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final remain = (state ?? Duration.zero) - const Duration(seconds: 1);
      if (remain <= Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
        _handler.pause();
        state = null;
      } else {
        state = remain;
      }
    });
  }

  /// 手动取消倒计时。
  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, Duration?>(
    (ref) => SleepTimerNotifier(ref.watch(audioHandlerProvider)));

/// 云端「喜欢」的歌曲（「我喜欢的音乐」）：
/// 列表来自 /likelist + /song/detail，收藏/取消走 /like。
/// 乐观更新 + 失败回滚；登录后自动同步，登出即清空（不再用本地 localStorage）。
class LikedSongsNotifier extends StateNotifier<List<Song>> {
  LikedSongsNotifier(this._api) : super(const []);
  final NcmApi _api;

  int _uid = 0;
  Set<int> _ids = {};

  bool isFavorite(int songId) => _ids.contains(songId);

  /// 登录资料变化入口（userProfileProvider 监听桥接）：uid>0 拉云端，否则清空。
  Future<void> onProfile(int uid) async {
    if (uid == _uid) return;
    _uid = uid;
    if (uid == 0) {
      _ids = {};
      state = const [];
      return;
    }
    await refresh();
  }

  /// 全量同步喜欢的歌曲：likelist ids → 分批 song/detail 还原 Song。
  Future<void> refresh() async {
    if (_uid == 0) return;
    final ids = await _api.likeList(_uid);
    _ids = ids.toSet();
    final all = <Song>[];
    // 分批拉详情，避免 URL 过长；上限 1000 首作保护。
    for (var i = 0; i < ids.length && i < 1000; i += 100) {
      all.addAll(await _api.songsDetail(ids.skip(i).take(100).toList()));
    }
    if (_uid == 0) return; // 期间登出：丢弃结果。
    state = all;
  }

  /// 收藏/取消收藏（乐观更新，失败回滚并抛出供 UI 提示）。
  Future<void> toggle(Song song) async {
    if (_uid == 0) {
      throw const ApiException(301, '请先登录后再收藏歌曲');
    }
    final willFav = !_ids.contains(song.id);
    _apply(song, willFav);
    try {
      await _api.likeSong(song.id, like: willFav);
    } catch (_) {
      _apply(song, !willFav); // 回滚
      rethrow;
    }
  }

  void _apply(Song s, bool fav) {
    if (fav) {
      _ids = {..._ids, s.id};
      state = [s, ...state.where((x) => x.id != s.id)];
    } else {
      _ids = _ids.where((x) => x != s.id).toSet();
      state = state.where((x) => x.id != s.id).toList();
    }
  }
}

/// 桥接登录资料 → 喜欢列表。fireImmediately：provider 首次被读时即按当前态同步。
final likedSongsProvider =
    StateNotifierProvider<LikedSongsNotifier, List<Song>>((ref) {
  final notifier = LikedSongsNotifier(ref.watch(apiProvider));
  ref.listen(userProfileProvider, (_, next) {
    notifier.onProfile(next.valueOrNull?.userId ?? 0);
  }, fireImmediately: true);
  return notifier;
});

/// 云端收藏的歌单：列表来自 /user/playlist（creator.userId != uid），
/// 收藏/取消走 /playlist/subscribe（t=1/2）。乐观更新 + 失败回滚；登出清空。
class SubscribedPlaylistsNotifier extends StateNotifier<List<Playlist>> {
  SubscribedPlaylistsNotifier(this._api) : super(const []);
  final NcmApi _api;

  int _uid = 0;

  bool isFavorite(int playlistId) =>
      state.any((p) => p.id == playlistId);

  /// 登录资料变化入口。
  Future<void> onProfile(int uid) async {
    if (uid == _uid) return;
    _uid = uid;
    if (uid == 0) {
      state = const [];
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_uid == 0) return;
    final list = await _api.subscribedPlaylists(_uid);
    if (_uid == 0) return;
    state = list;
  }

  /// 收藏/取消收藏（乐观更新，失败回滚并抛出）。
  /// 业务码 501（未收藏过）/502（已收藏过）视为幂等成功，不回滚。
  Future<void> toggle(Playlist playlist) async {
    if (_uid == 0) {
      throw const ApiException(301, '请先登录后再收藏歌单');
    }
    final willFav = !isFavorite(playlist.id);
    state = willFav
        ? [playlist, ...state]
        : state.where((p) => p.id != playlist.id).toList();
    try {
      await _api.subscribePlaylist(playlist.id, subscribe: willFav);
    } on ApiException catch (e) {
      if (e.code == 501 || e.code == 502) return; // 与服务端状态已一致。
      state = willFav
          ? state.where((p) => p.id != playlist.id).toList()
          : [playlist, ...state];
      rethrow;
    } catch (_) {
      state = willFav
          ? state.where((p) => p.id != playlist.id).toList()
          : [playlist, ...state];
      rethrow;
    }
  }
}

/// 桥接登录资料 → 收藏歌单列表。
final favoritePlaylistsProvider =
    StateNotifierProvider<SubscribedPlaylistsNotifier, List<Playlist>>((ref) {
  final notifier = SubscribedPlaylistsNotifier(ref.watch(apiProvider));
  ref.listen(userProfileProvider, (_, next) {
    notifier.onProfile(next.valueOrNull?.userId ?? 0);
  }, fireImmediately: true);
  return notifier;
});

/// 风格切换（持久化到 SharedPreferences）。
class StyleNotifier extends StateNotifier<int> {
  StyleNotifier() : super(0) {
    _load();
  }
  Future<void> _load() async {
    final sp = LocalStore.instance;
    state = sp.getInt(kStyleIndexKey) ?? 0;
  }

  Future<void> set(int i) async {
    state = i;
    final sp = LocalStore.instance;
    sp.setInt(kStyleIndexKey, i);
  }
}

final styleIndexProvider =
    StateNotifierProvider<StyleNotifier, int>((ref) => StyleNotifier());

/// 播放设置：在线播放音质 / 下载音质 / 播放页视觉（持久化）。
/// urlResolver 闭包经 currentPlayLevel() 取值，改档位后下一次解析音源立即生效。
class PlaybackSettings {
  final String playLevel;
  final String downloadLevel;
  final String nowPlayingVisual;
  const PlaybackSettings(
      {this.playLevel = 'standard',
      this.downloadLevel = 'standard',
      this.nowPlayingVisual = kVisualVinylWave});
}

class PlaybackSettingsNotifier extends StateNotifier<PlaybackSettings> {
  PlaybackSettingsNotifier() : super(const PlaybackSettings()) {
    _load();
  }

  /// 供 urlResolver 闭包读取当前播放档位（StateNotifier.state 受保护，
  /// 外部经此方法取值）。
  String currentPlayLevel() => state.playLevel;

  Future<void> _load() async {
    try {
      final sp = LocalStore.instance;
      final visual = sp.getString(kNowPlayingVisualKey);
      state = PlaybackSettings(
        playLevel: sp.getString(kPlayQualityKey) ?? 'standard',
        downloadLevel: sp.getString(kDownloadQualityKey) ?? 'standard',
        // 脏值兜底：不在合法枚举内时回落默认黑胶动效。
        nowPlayingVisual: kNowPlayingVisuals.contains(visual)
            ? visual!
            : kVisualVinylWave,
      );
    } catch (_) {
      // 读取失败保持默认。
    }
  }

  Future<void> setPlayLevel(String level) async {
    if (!kQualityLevels.contains(level) || level == state.playLevel) return;
    state = PlaybackSettings(
        playLevel: level,
        downloadLevel: state.downloadLevel,
        nowPlayingVisual: state.nowPlayingVisual);
    final sp = LocalStore.instance;
    sp.setString(kPlayQualityKey, level);
  }

  Future<void> setDownloadLevel(String level) async {
    if (!kQualityLevels.contains(level) || level == state.downloadLevel) return;
    state = PlaybackSettings(
        playLevel: state.playLevel,
        downloadLevel: level,
        nowPlayingVisual: state.nowPlayingVisual);
    final sp = LocalStore.instance;
    sp.setString(kDownloadQualityKey, level);
  }

  /// 切换播放页视觉（黑胶动效/经典静态），立即生效并持久化。
  Future<void> setNowPlayingVisual(String visual) async {
    if (!kNowPlayingVisuals.contains(visual) ||
        visual == state.nowPlayingVisual) {
      return;
    }
    state = PlaybackSettings(
        playLevel: state.playLevel,
        downloadLevel: state.downloadLevel,
        nowPlayingVisual: visual);
    final sp = LocalStore.instance;
    sp.setString(kNowPlayingVisualKey, visual);
  }
}

final playbackSettingsProvider = StateNotifierProvider<PlaybackSettingsNotifier,
        PlaybackSettings>((ref) => PlaybackSettingsNotifier());

/// 播放模式（顺序/列表循环/单曲循环/随机），持久化并同步给 audio handler。
class PlayModeNotifier extends StateNotifier<PlayMode> {
  final NcmAudioHandler _handler;
  PlayModeNotifier(this._handler) : super(PlayMode.sequential) {
    _handler.setPlayMode(state);
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = LocalStore.instance;
      final i = sp.getInt(kPlayModeKey) ?? 0;
      final m = PlayMode.values[i.clamp(0, PlayMode.values.length - 1)];
      state = m;
      _handler.setPlayMode(m);
    } catch (_) {
      // 读取失败保持默认。
    }
  }

  Future<void> set(PlayMode m) async {
    state = m;
    _handler.setPlayMode(m);
    try {
      final sp = LocalStore.instance;
      sp.setInt(kPlayModeKey, m.index);
    } catch (_) {
      // 持久化失败不影响本次会话。
    }
  }

  /// 循环切换：顺序 → 列表循环 → 单曲循环 → 随机。
  void cycle() => set(PlayMode.values[(state.index + 1) % PlayMode.values.length]);
}

final playModeProvider =
    StateNotifierProvider<PlayModeNotifier, PlayMode>(
        (ref) => PlayModeNotifier(ref.watch(audioHandlerProvider)));

/// 搜索历史（本地持久化，最新在前，最多 10 条）。
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const []) {
    _load();
  }
  static const int _max = 10;

  void add(String keyword) {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    state = [kw, ...state.where((e) => e != kw)].take(_max).toList();
    _persist();
  }

  void remove(String keyword) {
    state = state.where((e) => e != keyword).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  Future<void> _load() async {
    try {
      final sp = LocalStore.instance;
      final raw = sp.getStringList(kSearchHistoryKey) ?? const [];
      state = List<String>.from(raw);
    } catch (_) {
      // 忽略损坏数据。
    }
  }

  Future<void> _persist() async {
    try {
      final sp = LocalStore.instance;
      sp.setStringList(kSearchHistoryKey, state);
    } catch (_) {
      // 持久化失败不影响本次会话。
    }
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
        (ref) => SearchHistoryNotifier());

/// 播放历史（本地持久化到 SharedPreferences）：由 main 注入
/// NcmAudioHandler.onSongStarted，每次成功开播自动记录。
/// 最新在前、按歌曲 id 去重，最多保留 kHistoryMax 条。
class HistoryNotifier extends StateNotifier<List<Song>> {
  HistoryNotifier() : super(const []) {
    _load();
  }

  /// 记录一次播放：同曲去重并置顶。
  void add(Song song) {
    if (song.id == 0) return;
    state = [
      song,
      ...state.where((s) => s.id != song.id),
    ].take(kHistoryMax).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  Future<void> _load() async {
    try {
      final sp = LocalStore.instance;
      final raw = sp.getString(kHistoryKey);
      if (raw == null || raw.isEmpty) return;
      state = (jsonDecode(raw) as List)
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏时忽略，保持空列表。
    }
  }

  Future<void> _persist() async {
    try {
      final sp = LocalStore.instance;
      sp.setString(
          kHistoryKey, jsonEncode(state.map((s) => s.toJson()).toList()));
    } catch (_) {
      // 持久化失败不影响本次会话使用。
    }
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<Song>>((ref) {
  final notifier = HistoryNotifier();
  // 挂到 audio handler：开播即记录（main 中会 override 为同一实例并接线）。
  ref.watch(audioHandlerProvider).onSongStarted = notifier.add;
  return notifier;
});

/// 收听统计（本地累计）：
///
/// - 计时：每秒 tick 一次，仅在 [NcmAudioHandler.isPlaying] 为真时累加到当天，
///   不受拖动进度条（seek 跳变）与暂停影响，比用 position 差分会更稳；
/// - 起播次数：听 [NcmAudioHandler.songStartedStream]（广播流，不和播放历史抢
///   单回调 `onSongStarted`）；
/// - 落盘节流：内存里逐秒累加，UI 每 5 秒发布一次快照、磁盘每 15 秒写一次，
///   暂停 / 停止时立即补写——避免每秒 fsync 拖慢播放。
class ListenStatsNotifier extends StateNotifier<ListenStats> {
  ListenStatsNotifier(this._handler) : super(ListenStats.empty()) {
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _songSub = _handler.songStartedStream.listen(_onSongStarted);
    _stateSub = _handler.playbackState.listen((s) {
      if (!s.playing) _persist(); // 暂停/停止：立刻把未落盘的秒数写下去。
    });
  }

  static const Duration _emitEvery = Duration(seconds: 5);
  static const Duration _persistEvery = Duration(seconds: 15);

  final NcmAudioHandler _handler;
  final Map<String, DayListen> _days = {};
  Timer? _ticker;
  StreamSubscription<Song>? _songSub;
  StreamSubscription<PlaybackState>? _stateSub;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dirty = false;

  void _load() {
    try {
      final raw = LocalStore.instance.getString(kListenStatsKey);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final map = j['days'] as Map<String, dynamic>? ?? const {};
        map.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            _days[k] = DayListen.fromJson(v);
          }
        });
      }
    } catch (_) {
      // 数据损坏：当作无记录重新开始，不阻断启动。
    }
    // 离线 Mock 模式植入一段演示数据，方便调试统计视图（真实使用从 0 开始）。
    if (_days.isEmpty && kUseMock) _seedDemo();
    _publish(force: true);
  }

  void _tick() {
    if (!_handler.isPlaying) return;
    // 卡顿/加载中不累加：`playing` 在缓冲、卡网时仍为 true，只看它会虚增时长。
    if (_handler.playbackState.value.processingState !=
        AudioProcessingState.ready) {
      return;
    }
    final now = DateTime.now();
    final key = dayKey(now);
    _days[key] = (_days[key] ?? DayListen.empty).addSeconds(1);
    _dirty = true;
    if (now.difference(_lastEmit) >= _emitEvery) _publish(now: now);
    if (now.difference(_lastPersist) >= _persistEvery) _persist(now: now);
  }

  void _onSongStarted(Song song) {
    final now = DateTime.now();
    final key = dayKey(now);
    _days[key] = (_days[key] ?? DayListen.empty).addSong(song.id);
    _dirty = true;
    // 起播是低频事件：立即刷新页面上的「首数」，并马上落盘。
    _publish(now: now, force: true);
    _persist(now: now);
  }

  void _publish({DateTime? now, bool force = false}) {
    final n = now ?? DateTime.now();
    if (!force && n.difference(_lastEmit) < _emitEvery) return;
    _lastEmit = n;
    state = ListenStats.fromDays(Map<String, DayListen>.from(_days), now: n);
  }

  void _persist({DateTime? now}) {
    if (!_dirty) return;
    final n = now ?? DateTime.now();
    _lastPersist = n;
    _dirty = false;
    try {
      LocalStore.instance.setString(
        kListenStatsKey,
        jsonEncode({
          'version': 1,
          'days': {
            for (final e in _days.entries) e.key: e.value.toJson(),
          },
        }),
      );
    } catch (_) {
      // 落盘失败不影响本次会话，下一次 tick 会再试。
    }
  }

  /// 清空全部收听统计（设置页「清除收听统计」）。
  void clear() {
    _days.clear();
    _dirty = true;
    _publish(force: true);
    _persist(now: DateTime.now());
  }

  /// 离线 Mock 模式演示数据：近 14 天（含今天），数值按固定序列生成，
  /// 只为让图表/明细在无真实播放时也可读，正式包（USE_MOCK=false）不会执行。
  void _seedDemo() {
    const minutes = [52, 78, 44, 96, 63, 118, 85, 39, 74, 101, 57, 68, 92, 47];
    final today = DateTime.now();
    for (var i = 0; i < minutes.length; i++) {
      final d = today.subtract(Duration(days: minutes.length - 1 - i));
      final min = minutes[i];
      _days[dayKey(d)] = DayListen(
        seconds: min * 60,
        plays: (min / 3.4).round(),
        songIds: {for (var s = 0; s < (min / 7).round(); s++) 900100 + i * 10 + s},
      );
    }
  }

  @override
  void dispose() {
    _persist(now: DateTime.now());
    _ticker?.cancel();
    _songSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

final listenStatsProvider =
    StateNotifierProvider<ListenStatsNotifier, ListenStats>(
        (ref) => ListenStatsNotifier(ref.watch(audioHandlerProvider)));

/// 播放现场断点持久化（断点续听）：
/// - 启动时读快照，把上次的播放队列恢复为**暂停态**（装队列 + 预载音源 +
///   seek 到断点，不自动出声），见 NcmAudioHandler.restoreQueue；
/// - 会话中在「队列变化 / 播放中→暂停 / App 退后台」时回写快照；
///   队列清空则删除快照（避免下次恢复出一个空队列）。
/// 进度只在播放器已装载当前曲时才写入——切歌窗口里 loadedSongId 为空或
/// 还是上一首，此时断点应记 0（新曲从头恢复）。
class QueueSnapshotStore extends WidgetsBindingObserver {
  final NcmAudioHandler _handler;
  StreamSubscription<QueueSnapshot>? _queueSub;
  StreamSubscription<PlaybackState>? _stateSub;
  bool _lastPlaying = false;
  bool _restoring = false;

  QueueSnapshotStore(this._handler) {
    _restore();
    _queueSub = _handler.queueStream.listen((_) => _save());
    _stateSub = _handler.playbackState.listen((s) {
      // 播放中 → 暂停：此刻播放器位置就是最准的断点。
      if (_lastPlaying && !s.playing) _save();
      _lastPlaying = s.playing;
    });
    WidgetsBinding.instance.addObserver(this);
  }

  /// 读本地快照并恢复队列。快照损坏/字段缺失一律忽略，按无快照启动；
  /// 恢复期间挂起回写，防止装载途中 loadedSongId 尚空把断点进度覆盖成 0。
  void _restore() {
    try {
      final raw = LocalStore.instance.getString(kQueueSnapshotKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final songs = (j['songs'] as List? ?? const [])
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
      final index = (j['index'] as num?)?.toInt() ?? -1;
      final positionMs = (j['positionMs'] as num?)?.toInt() ?? 0;
      if (songs.isEmpty || index < 0 || index >= songs.length) return;
      _restoring = true;
      _handler
          .restoreQueue(songs, index, Duration(milliseconds: positionMs))
          .whenComplete(() => _restoring = false);
    } catch (_) {
      _restoring = false;
      // 损坏数据：忽略，按无快照启动。
    }
  }

  void _save() {
    if (_restoring) return;
    final snap = _handler.currentQueueSnapshot;
    final sp = LocalStore.instance;
    if (snap.songs.isEmpty || snap.index < 0) {
      sp.remove(kQueueSnapshotKey);
      return;
    }
    var positionMs = 0;
    if (snap.index < snap.songs.length &&
        _handler.loadedSongId == snap.songs[snap.index].id) {
      positionMs = _handler.position.inMilliseconds;
    }
    try {
      sp.setString(kQueueSnapshotKey, jsonEncode({
        'index': snap.index,
        'positionMs': positionMs,
        'songs': snap.songs.map((s) => s.toJson()).toList(),
      }));
    } catch (_) {
      // 回写失败不影响本次会话（下次保存自然补上）。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退后台/进程即将被杀：抢写一次断点（LocalStore 同步落盘，划掉也不丢）。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _save();
    }
  }

  void dispose() {
    _queueSub?.cancel();
    _stateSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// 断点续听入口：main 在 urlResolver 接线后 read 一次，触发启动恢复并
/// 常驻监听会话内的保存时机。
final queueSnapshotProvider = Provider<QueueSnapshotStore>((ref) {
  final store = QueueSnapshotStore(ref.watch(audioHandlerProvider));
  ref.onDispose(store.dispose);
  return store;
});

/// 登录用户资料：随登录态变化自动重算；未登录返回空实例。
final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  final authed =
      ref.watch(authStateProvider).status == AuthStatus.authenticated;
  if (!authed) return const UserProfile(userId: 0, nickname: '', avatarUrl: '');
  try {
    return await ref.watch(apiProvider).userAccount();
  } catch (_) {
    return const UserProfile(userId: 0, nickname: '', avatarUrl: '');
  }
});

/// 热搜关键词榜（失败由 UI 侧静默降级，不阻塞搜索页）。
final hotSearchProvider = FutureProvider<List<String>>(
    (ref) => ref.watch(apiProvider).hotSearch());

/// 我创建的歌单（云端 /user/playlist，userId == 当前账号）。
/// 未登录 / 请求失败时静默降级为空列表，不阻塞音乐库页。
final myPlaylistsProvider = FutureProvider<List<Playlist>>((ref) async {
  try {
    final profile = await ref.watch(userProfileProvider.future);
    if (profile.userId == 0) return const [];
    return await ref.watch(apiProvider).createdPlaylists(profile.userId);
  } catch (_) {
    return const [];
  }
});
