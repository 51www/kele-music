import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants.dart';
import 'core/local_store.dart';
import 'core/errors.dart';
import 'core/live_activity/live_activity_controller.dart';
import 'core/notification_permission.dart';
import 'data/api_client.dart';
import 'data/auth_repository.dart';
import 'data/listen_stats.dart';
import 'data/lrc_parser.dart';
import 'data/models.dart';
import 'data/player_repository.dart';

// UI 层（播放页/导航坞）判断按钮置灰需要 PlayMode，经此 re-export 暴露。
export 'data/player_repository.dart' show PlayMode;

final apiProvider = Provider<NcmApi>((ref) => NcmApi());
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiProvider)));

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

/// iOS 实时活动（灵动岛 / 锁屏）推送控制器：main 启动时 read 一次即常驻。
/// 仅 iOS 16.1+ 且用户开启实时活动时生效，其它平台/不支持时自动 no-op。
final liveActivityControllerProvider = Provider<LiveActivityController>((ref) {
  final controller = LiveActivityController(
      ref.watch(audioHandlerProvider), ref.watch(apiProvider));
  unawaited(controller.start());
  ref.onDispose(controller.dispose);
  return controller;
});

/// 当前播放媒体项流（用于迷你播放条 / 全屏播放页）。
final currentMediaItemProvider = StreamProvider<MediaItem?>(
    (ref) => ref.watch(audioHandlerProvider).mediaItem);
final playbackStateProvider = StreamProvider<PlaybackState>(
    (ref) => ref.watch(audioHandlerProvider).playbackState);

/// 音源获取中状态（true = 正在解析/装载当前曲），供播放页封面 loading 层。
/// 广播流不重放，UI 初始值用 handler.isPreparing 兜底。
final playbackLoadingProvider = StreamProvider<bool>(
    (ref) => ref.watch(audioHandlerProvider).loadingStream);

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
final lyricProvider =
    FutureProvider.autoDispose.family<LyricData, int>((ref, songId) async {
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

/// 单曲收藏列表状态：已加载的歌曲 + 是否还有更多（分页）+ 是否加载中。
class LikedSongsState {
  final List<Song> songs;
  final bool hasMore;
  final bool loadingMore;
  const LikedSongsState(
      {this.songs = const [], this.hasMore = false, this.loadingMore = false});
}

/// 单曲收藏（「喜欢」）双轨存储：
/// - 已登录：走云端 /like。取数路径固定两步，无冗余请求：
///   1) /likelist 一次性拿全部喜欢的歌曲 id；
///   2) /song/detail 按 ids（逗号分隔）分页批量还原歌曲详情（dt=时长），
///      首屏只取第一页，后续随滑动按页加载（loadMore）。
/// - 未登录：数据仅存本机 LocalStore（kLocalFavoriteSongsKey）。
/// 登录后展现云端集合，登出回落本机集合，两套数据互不覆盖。
class LikedSongsNotifier extends StateNotifier<LikedSongsState> {
  LikedSongsNotifier(this._api) : super(const LikedSongsState()) {
    // 启动即按当前（未登录）态预热本机集合，使离线收藏立即可用；
    // 随后 userProfileProvider 若确认已登录（uid>0），onProfile 会改拉云端。
    if (_uid == 0) _loadLocal();
  }
  final NcmApi _api;

  /// 每页歌曲详情条数。30 个 id 约 360 字符，叠加 sharecode/cookie 后
  /// 整条 query 仍远低于常见网关（1KB/2KB）限制，避免超长被截断。
  static const int _pageSize = 25;

  int _uid = 0;
  Set<int> _ids = {};
  List<int> _allIds = const [];
  int _nextIndex = 0;
  bool _loadingMore = false;
  int _emptyPages = 0; // 连续空页计数（翻页止损用）
  int _retryCount = 0;
  static const int _maxAutoRetries = 3;

  /// 是否处于未登录的本地存储模式（供 UI 文案区分「本机」/「账号」）。
  bool get isLocal => _uid == 0;

  bool isFavorite(int songId) => _ids.contains(songId);

  /// 登录资料变化入口（userProfileProvider 监听桥接）：
  /// uid>0 拉云端，uid==0 回落本机集合。
  Future<void> onProfile(int uid) async {
    if (uid == _uid) return;
    _uid = uid;
    _retryCount = 0;
    await _reload();
  }

  /// 手动刷新（音乐库单曲页签下拉）：按当前登录态从对应来源重载。
  Future<void> refresh() => _reload();

  /// 滑动到底部附近时由 UI 触发：拉取下一页歌曲详情（不再重复请求
  /// /likelist，只按游标追加 /song/detail）。
  Future<void> loadMore() async {
    if (_uid == 0 || _loadingMore || _nextIndex >= _allIds.length) return;
    _loadingMore = true;
    state =
        LikedSongsState(songs: state.songs, hasMore: true, loadingMore: true);
    final prev = state.songs;
    final start = _nextIndex;
    try {
      // 看门狗：整页（含失败拆分重试）最多等 30s，绝不无限挂起。
      final more =
          await _fetchDetail(_allIds.skip(start).take(_pageSize).toList())
              .timeout(const Duration(seconds: 30));
      if (_uid == 0) return;
      _nextIndex = start + _pageSize;
      final known = prev.map((s) => s.id).toSet();
      final fresh = more.where((s) => !known.contains(s.id)).toList();
      // 连续两页颗粒无收：视为数据尽头/网关异常，停止翻页避免无限重试。
      final stop = fresh.isEmpty && ++_emptyPages >= 2;
      if (fresh.isNotEmpty) _emptyPages = 0;
      state = LikedSongsState(
        songs: [...prev, ...fresh],
        hasMore: !stop && _nextIndex < _allIds.length,
        loadingMore: false,
      );
      _loadingMore = false;
    } catch (_) {
      // 翻页失败不弹错误打断浏览：复位加载态，继续滑动会再次触发。
      _loadingMore = false;
      if (mounted) {
        state = LikedSongsState(
            songs: state.songs, hasMore: true, loadingMore: false);
      }
    }
  }

  /// 按当前登录态从对应来源重载：云端 or 本机。
  Future<void> _reload() async {
    if (_uid == 0) {
      _loadLocal();
      return;
    }
    // 已登录：只展示云端「我喜欢的音乐」，绝不回落本机离线收藏——
    // 否则登录失败/慢时，启动时残留的离线收藏会被误当成账号收藏展示。
    _allIds = const [];
    _nextIndex = 0;
    _emptyPages = 0;
    _ids = {};
    state = const LikedSongsState();
    try {
      await _refreshCloud();
      _retryCount = 0;
    } catch (_) {
      // 首屏同步一次失败（网络抖动/超时）绝不把本机集合当账号收藏展示，
      // 保持空态并安排指数退避自动重试。
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_uid == 0 || _retryCount >= _maxAutoRetries || !mounted) return;
    final attempt = _retryCount++;
    unawaited(Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)))
        .then((_) async {
      if (_uid == 0 || !mounted) return;
      try {
        await _refreshCloud();
        _retryCount = 0;
      } catch (_) {
        _scheduleRetry();
      }
    }));
  }

  /// 云端首屏同步：/likelist 一次取全部 id → /song/detail 只取第一页。
  Future<void> _refreshCloud() async {
    if (_uid == 0) return;
    final ids = await _api.likeList(_uid);
    if (_uid == 0) return; // 期间登出：丢弃结果。
    _allIds = ids;
    _ids = ids.toSet();
    if (ids.isEmpty) {
      state = const LikedSongsState();
      return;
    }
    final first = await _fetchDetail(ids.take(_pageSize).toList());
    if (_uid == 0) return; // 期间登出：丢弃结果。
    // ids 非空但一首都没拿到：多为网络中断/网关异常，交上层自动重试，
    // 不静默渲染成空列表（否则永远停在空态）。
    if (first.isEmpty) {
      throw ApiException(null, '歌曲详情获取失败');
    }
    _nextIndex = _pageSize;
    state = LikedSongsState(
      songs: first,
      hasMore: _nextIndex < ids.length,
      loadingMore: false,
    );
  }

  /// 批量拉歌曲详情：整批失败时对半拆分重试，最终落到单曲粒度——
  /// 个别网关对超长 query 截断或对逗号编码（%2C）不兼容时，拆到单 id
  /// 请求即可绕过（单 id 既短又不含逗号）；某个坏 id 单独失败也只牺牲
  /// 该曲，其余歌曲照常展示。
  /// [deadline] 硬截止（20s）：拆分风暴下最多 2n-1 次请求再叠加节流
  /// 排队，超时后放弃剩余拆分，避免一轮翻页把节流队列占满几十秒。
  Future<List<Song>> _fetchDetail(List<int> batch) async {
    if (batch.isEmpty) return const [];
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Future<List<Song>> split(List<int> b) async {
      try {
        return await _api.songsDetail(b);
      } catch (_) {
        if (b.length == 1) return const []; // 单曲也失败：跳过该曲。
        if (DateTime.now().isAfter(deadline)) return const [];
        final mid = b.length ~/ 2;
        final head = await split(b.sublist(0, mid));
        final tail = await split(b.sublist(mid));
        return [...head, ...tail];
      }
    }

    return split(batch);
  }

  /// 从本机 LocalStore 恢复离线收藏（同步读，无需网络）。
  void _loadLocal() {
    final list = _localSongs();
    _ids = list.map((s) => s.id).toSet();
    state = LikedSongsState(songs: list);
  }

  List<Song> _localSongs() {
    try {
      final raw = LocalStore.instance.getString(kLocalFavoriteSongsKey);
      if (raw == null || raw.isEmpty) return const [];
      final j = jsonDecode(raw) as List;
      return j.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const []; // 数据损坏按空处理，不阻断。
    }
  }

  /// 收藏/取消收藏：在线走云端（乐观更新+失败回滚），离线仅写本机。
  Future<void> toggle(Song song) async {
    final willFav = !_ids.contains(song.id);
    if (_uid == 0) {
      _apply(song, willFav);
      _persistLocal();
      return;
    }
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
      _allIds = [s.id, ..._allIds.where((x) => x != s.id)];
      state = LikedSongsState(
        songs: [s, ...state.songs.where((x) => x.id != s.id)],
        hasMore: state.hasMore,
        loadingMore: state.loadingMore,
      );
    } else {
      _ids = _ids.where((x) => x != s.id).toSet();
      _allIds = _allIds.where((x) => x != s.id).toList();
      state = LikedSongsState(
        songs: state.songs.where((x) => x.id != s.id).toList(),
        hasMore: state.hasMore,
        loadingMore: state.loadingMore,
      );
    }
  }

  /// 本机集合落盘（即时同步落盘，进程被杀也不丢）。
  void _persistLocal() {
    try {
      LocalStore.instance.setString(kLocalFavoriteSongsKey,
          jsonEncode(state.songs.map((s) => s.toJson()).toList()));
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }
}

/// 桥接登录资料 → 喜欢列表。fireImmediately：provider 首次被读时即按当前态同步。
final likedSongsProvider =
    StateNotifierProvider<LikedSongsNotifier, LikedSongsState>((ref) {
  final notifier = LikedSongsNotifier(ref.watch(apiProvider));
  ref.listen(userProfileProvider, (_, next) {
    notifier.onProfile(next.valueOrNull?.userId ?? 0);
  }, fireImmediately: true);
  return notifier;
});

/// 歌单收藏双轨存储（与单曲喜欢同构）：
/// - 已登录：走云端 /playlist/subscribe，列表来自 /user/playlist（creator.userId != uid）；
/// - 未登录：数据仅存本机 LocalStore（kLocalFavoritePlaylistsKey），无需登录即可收藏。
/// 切换登录态时仅切换当前激活集合，两套数据各自独立保留。
class SubscribedPlaylistsNotifier extends StateNotifier<List<Playlist>> {
  SubscribedPlaylistsNotifier(this._api) : super(const []) {
    if (_uid == 0) _loadLocal();
  }
  final NcmApi _api;

  int _uid = 0;

  /// 是否处于未登录的本地存储模式（供 UI 文案区分「本机」/「账号」）。
  bool get isLocal => _uid == 0;

  bool isFavorite(int playlistId) => state.any((p) => p.id == playlistId);

  /// 登录资料变化入口。
  Future<void> onProfile(int uid) async {
    if (uid == _uid) return;
    _uid = uid;
    await _reload();
  }

  Future<void> _reload() async {
    if (_uid == 0) {
      _loadLocal();
    } else {
      await _refreshCloud();
    }
  }

  Future<void> _refreshCloud() async {
    if (_uid == 0) return;
    final list = await _api.subscribedPlaylists(_uid);
    if (_uid == 0) return;
    state = list;
  }

  /// 从本机 LocalStore 恢复离线收藏的歌单。
  void _loadLocal() {
    try {
      final raw = LocalStore.instance.getString(kLocalFavoritePlaylistsKey);
      if (raw == null || raw.isEmpty) {
        state = const [];
        return;
      }
      final j = jsonDecode(raw) as List;
      state =
          j.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      state = const []; // 数据损坏按空处理。
    }
  }

  /// 收藏/取消收藏：在线走云端（乐观更新+失败回滚），离线仅写本机。
  /// 业务码 501（未收藏过）/502（已收藏过）视为幂等成功，不回滚。
  Future<void> toggle(Playlist playlist) async {
    final willFav = !isFavorite(playlist.id);
    if (_uid == 0) {
      state = willFav
          ? [playlist, ...state.where((p) => p.id != playlist.id)]
          : state.where((p) => p.id != playlist.id).toList();
      _persistLocal();
      return;
    }
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

  /// 本机集合落盘。
  void _persistLocal() {
    try {
      LocalStore.instance.setString(kLocalFavoritePlaylistsKey,
          jsonEncode(state.map((p) => p.toJson()).toList()));
    } catch (_) {
      // 落盘失败不影响本次会话。
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

/// 「创建」页签的歌单条目（用户自建，双轨视图模型）：
/// - 已登录：云端歌单，meta 来自 /user/playlist（creator==uid），tracks 为 null
///   （详情经 /playlist/detail 拉取，曲目数用 trackCount）；
/// - 未登录：本机歌单，tracks 内嵌完整曲目（LocalStore 持久化，复用 LocalPlaylist 结构）。
class UserPlaylist {
  final int id;
  final String name;
  final String coverImgUrl;
  final int trackCount;

  /// 未登录本机歌单内嵌的曲目；云端歌单为 null。
  final List<Song>? tracks;
  final bool local;

  /// 云端歌单的 specialType（5 = 「我喜欢的音乐」）；本机歌单恒为 0。
  final int specialType;
  const UserPlaylist({
    required this.id,
    required this.name,
    this.coverImgUrl = '',
    this.trackCount = 0,
    this.tracks,
    this.local = false,
    this.specialType = 0,
  });

  int get count => local ? (tracks?.length ?? 0) : trackCount;

  /// 列表封面：云端用 coverImgUrl，本机取首曲封面，都没有返回 null 走占位。
  String? get cover {
    if (local) {
      final t = tracks;
      if (t != null && t.isNotEmpty) return t.first.coverUrl;
      return null;
    }
    return coverImgUrl.isEmpty ? null : coverImgUrl;
  }
}

/// 「创建」页签状态：歌单列表（登录用户含云端「我喜欢的音乐」，原样展示在首位）。
class CreatedPlaylistsState {
  final List<UserPlaylist> playlists;
  const CreatedPlaylistsState({this.playlists = const []});
}

/// 用户创建的歌单（「音乐库 → 创建」页签）双轨存储：
/// - 已登录：增删改全走云端接口（/playlist/create、/playlist/name/update、
///   /playlist/delete），添加曲目走 /playlist/tracks(op=add)，与网易云账号同步；
///   列表来自 /user/playlist（creator==uid），随接口原样展示——含首位的
///   「我喜欢的音乐」（specialType=5，UI 不提供改名/删除入口）。
/// - 未登录：数据仅存本机 LocalStore（kLocalUserPlaylistsKey），纯本地增删改。
class CreatedPlaylistsNotifier
    extends StateNotifier<AsyncValue<CreatedPlaylistsState>> {
  CreatedPlaylistsNotifier(this._api)
      : super(const AsyncData(CreatedPlaylistsState())) {
    // 启动即按当前（未登录）态读本机集合；登录确认后 onProfile 改拉云端。
  }
  final NcmApi _api;

  int _uid = 0;

  bool get isLocal => _uid == 0;

  /// 登录资料变化入口（userProfileProvider 监听桥接）。
  Future<void> onProfile(int uid) async {
    if (uid == _uid) return;
    _uid = uid;
    if (uid == 0) {
      state = AsyncData(CreatedPlaylistsState(playlists: _readLocal()));
      return;
    }
    state = const AsyncLoading();
    await _refreshCloud();
  }

  /// 手动刷新（创建页签下拉）。
  Future<void> refresh() async {
    if (_uid == 0) {
      state = AsyncData(CreatedPlaylistsState(playlists: _readLocal()));
      return;
    }
    await _refreshCloud();
  }

  Future<void> _refreshCloud() async {
    final uid = _uid;
    if (uid == 0) return;
    try {
      // 破缓存拉取：本刷新均发生在新建/删除/改名/加歌之后或用户手动下拉，
      // 必须看到最新列表（/user/playlist 是 GET，默认命中 120s 边缘缓存）。
      final list = await _api.createdPlaylists(uid, bustCache: true);
      if (_uid != uid) return; // 登录态已切换，丢弃过期结果。
      // 云端列表原样展示（含 specialType=5 的「我喜欢的音乐」，接口排在首位）。
      final mine = list
          .map((p) => UserPlaylist(
                id: p.id,
                name: p.name,
                coverImgUrl: p.coverImgUrl,
                trackCount: p.trackCount,
                specialType: p.specialType,
              ))
          .toList();
      state = AsyncData(CreatedPlaylistsState(playlists: mine));
    } catch (_) {
      // 拉取失败保留旧数据（AsyncLoading 期间失败则回落空态，UI 有重试入口）。
      if (state is AsyncLoading) {
        state = AsyncData(const CreatedPlaylistsState());
      }
    }
  }

  /// 未登录：读取本机自建歌单。
  List<UserPlaylist> _readLocal() {
    try {
      final raw = LocalStore.instance.getString(kLocalUserPlaylistsKey);
      if (raw == null || raw.isEmpty) return const [];
      final j = jsonDecode(raw) as List;
      return j
          .map((e) => LocalPlaylist.fromJson(e as Map<String, dynamic>))
          .map((p) => UserPlaylist(
              id: p.id, name: p.name, tracks: p.songs, local: true))
          .toList();
    } catch (_) {
      return const []; // 数据损坏按空处理。
    }
  }

  void _persistLocal(List<UserPlaylist> playlists) {
    try {
      final j = playlists
          .map((p) => LocalPlaylist(
                id: p.id,
                name: p.name,
                songs: p.tracks ?? const [],
              ).toJson())
          .toList();
      LocalStore.instance.setString(kLocalUserPlaylistsKey, jsonEncode(j));
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }

  LocalPlaylist? _localById(int id) {
    final list = state.valueOrNull?.playlists ?? const [];
    for (final p in list) {
      if (p.id == id && p.local) {
        return LocalPlaylist(
            id: p.id, name: p.name, songs: p.tracks ?? const []);
      }
    }
    return null;
  }

  void _updateLocal(List<UserPlaylist> playlists) {
    state = AsyncData(CreatedPlaylistsState(playlists: playlists));
    _persistLocal(playlists);
  }

  /// 新建歌单（云端 / 本机，按登录态）。返回新歌单 id（失败抛异常）。
  Future<int> create(String name) async {
    if (_uid == 0) {
      final id = nextLocalMediaId();
      _updateLocal([
        UserPlaylist(id: id, name: name, tracks: const [], local: true),
        ...(state.valueOrNull?.playlists ?? const []),
      ]);
      return id;
    }
    final id = await _api.createPlaylist(name);
    await _refreshCloud();
    return id;
  }

  /// 重命名歌单。
  Future<void> rename(int id, String name) async {
    if (_uid == 0) {
      final list = state.valueOrNull?.playlists ?? const [];
      _updateLocal([
        for (final p in list)
          if (p.id == id) _withName(p, name) else p,
      ]);
      return;
    }
    await _api.renamePlaylist(id, name);
    await _refreshCloud();
  }

  /// 删除歌单。
  Future<void> remove(int id) async {
    if (_uid == 0) {
      _updateLocal((state.valueOrNull?.playlists ?? const [])
          .where((p) => p.id != id)
          .toList());
      return;
    }
    await _api.deletePlaylist(id);
    await _refreshCloud();
  }

  /// 把歌曲加入歌单（云端 op=add / 本机内嵌追加，按曲目 id 去重）。
  /// 返回实际新增数量（提示「已加入 / 已在歌单中」用）。
  Future<int> addSongs(int playlistId, List<Song> songs) async {
    if (songs.isEmpty) return 0;
    if (_uid == 0) {
      final p = _localById(playlistId);
      if (p == null) return 0;
      final existIds = p.songs.map((s) => s.id).toSet();
      final fresh = songs.where((s) => !existIds.contains(s.id)).toList();
      if (fresh.isEmpty) return 0;
      final list = state.valueOrNull?.playlists ?? const [];
      _updateLocal([
        for (final x in list)
          if (x.id == playlistId)
            UserPlaylist(
                id: x.id,
                name: x.name,
                tracks: [...(x.tracks ?? const []), ...fresh],
                local: true)
          else
            x,
      ]);
      return fresh.length;
    }
    // 云端：乐观更新曲目数，失败回滚。
    final prev = state;
    _bumpCount(playlistId, songs.length);
    try {
      await _api.updatePlaylistTracks(
          playlistId, songs.map((s) => s.id).toList(),
          add: true);
      return songs.length;
    } catch (_) {
      state = prev;
      rethrow;
    }
  }

  /// 从歌单移出单曲（云端 op=del 后重拉；未登录仅改本机内嵌曲目）。
  Future<void> removeSong(int playlistId, int songId) async {
    if (_uid == 0) {
      final list = state.valueOrNull?.playlists ?? const [];
      _updateLocal([
        for (final x in list)
          if (x.id == playlistId)
            UserPlaylist(
                id: x.id,
                name: x.name,
                tracks: (x.tracks ?? const [])
                    .where((s) => s.id != songId)
                    .toList(),
                local: true)
          else
            x,
      ]);
      return;
    }
    await _api.updatePlaylistTracks(playlistId, [songId], add: false);
    await _refreshCloud();
  }

  void _bumpCount(int playlistId, int delta) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData(CreatedPlaylistsState(
      playlists: [
        for (final p in cur.playlists)
          if (p.id == playlistId)
            UserPlaylist(
                id: p.id,
                name: p.name,
                coverImgUrl: p.coverImgUrl,
                trackCount: p.trackCount + delta,
                specialType: p.specialType)
          else
            p,
      ],
    ));
  }

  UserPlaylist _withName(UserPlaylist p, String name) => UserPlaylist(
        id: p.id,
        name: name,
        coverImgUrl: p.coverImgUrl,
        trackCount: p.trackCount,
        tracks: p.tracks,
        local: p.local,
        specialType: p.specialType,
      );
}

/// 桥接登录资料 → 创建歌单列表。
final createdPlaylistsProvider = StateNotifierProvider<CreatedPlaylistsNotifier,
    AsyncValue<CreatedPlaylistsState>>((ref) {
  final notifier = CreatedPlaylistsNotifier(ref.watch(apiProvider));
  ref.listen(userProfileProvider, (_, next) {
    notifier.onProfile(next.valueOrNull?.userId ?? 0);
  }, fireImmediately: true);
  return notifier;
});

/// 批量导入结果：实际新增数量 + 因已在歌单中而跳过的数量。
class AddSongsResult {
  final int added;
  final int skippedDuplicate;
  const AddSongsResult({required this.added, required this.skippedDuplicate});
}

/// 本地歌单（「本地」页签）：设备本地音频文件的歌单，仅存本机 LocalStore
/// （kLocalPlaylistsKey），与登录态无关。曲目 url 为 file:// 本地路径，
/// 播放经 main 注入的 urlResolver 按歌曲 id 直读本地文件、不走网络。
class LocalPlaylistsNotifier extends StateNotifier<List<LocalPlaylist>> {
  LocalPlaylistsNotifier() : super(const []) {
    _load();
  }

  void _load() {
    try {
      final raw = LocalStore.instance.getString(kLocalPlaylistsKey);
      if (raw == null || raw.isEmpty) {
        state = const [];
        return;
      }
      final j = jsonDecode(raw) as List;
      state = j
          .map((e) => LocalPlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      state = const []; // 数据损坏按空处理。
    }
  }

  void _persist() {
    try {
      LocalStore.instance.setString(kLocalPlaylistsKey,
          jsonEncode(state.map((p) => p.toJson()).toList()));
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }

  LocalPlaylist? byId(int id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 新建歌单（新歌单排在最前）。
  void create(String name) {
    state = [
      LocalPlaylist(id: nextLocalMediaId(), name: name, songs: const []),
      ...state
    ];
    _persist();
  }

  void rename(int id, String name) {
    state = [
      for (final p in state)
        if (p.id == id)
          LocalPlaylist(id: p.id, name: name, songs: p.songs)
        else
          p
    ];
    _persist();
  }

  /// 删除歌单（歌单内曲目引用的本地文件不做删除）。
  void remove(int id) {
    state = state.where((p) => p.id != id).toList();
    _persist();
  }

  /// 批量导入本地音频文件；按歌曲 id 与文件路径双重去重。
  /// 重复项不静默丢弃，单独计数返回，供 UI 明确提示「已跳过 N 个重复」。
  AddSongsResult addSongs(int playlistId, List<Song> songs) {
    final p = byId(playlistId);
    if (p == null || songs.isEmpty) {
      return const AddSongsResult(added: 0, skippedDuplicate: 0);
    }
    final existIds = p.songs.map((s) => s.id).toSet();
    final existUrls = p.songs.map((s) => s.url).toSet();
    var added = 0;
    var skipped = 0;
    final merged = [...p.songs];
    for (final s in songs) {
      if (existIds.contains(s.id) || existUrls.contains(s.url)) {
        skipped++;
        continue;
      }
      merged.add(s);
      existIds.add(s.id);
      added++;
    }
    if (added > 0) {
      state = [
        for (final x in state)
          if (x.id == playlistId)
            LocalPlaylist(id: x.id, name: x.name, songs: merged)
          else
            x
      ];
      _persist();
    }
    return AddSongsResult(added: added, skippedDuplicate: skipped);
  }

  /// 从歌单移除单曲（同一文件若重复导入，多个条目 id 不同可分别移除）。
  void removeSong(int playlistId, int songId) {
    final p = byId(playlistId);
    if (p == null) return;
    final songs = p.songs.where((s) => s.id != songId).toList();
    state = [
      for (final x in state)
        if (x.id == playlistId)
          LocalPlaylist(id: x.id, name: x.name, songs: songs)
        else
          x
    ];
    _persist();
  }
}

final localPlaylistsProvider =
    StateNotifierProvider<LocalPlaylistsNotifier, List<LocalPlaylist>>(
        (ref) => LocalPlaylistsNotifier());

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
        nowPlayingVisual:
            kNowPlayingVisuals.contains(visual) ? visual! : kVisualVinylWave,
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

final playbackSettingsProvider =
    StateNotifierProvider<PlaybackSettingsNotifier, PlaybackSettings>(
        (ref) => PlaybackSettingsNotifier());

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
  void cycle() =>
      set(PlayMode.values[(state.index + 1) % PlayMode.values.length]);
}

final playModeProvider = StateNotifierProvider<PlayModeNotifier, PlayMode>(
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
        songIds: {
          for (var s = 0; s < (min / 7).round(); s++) 900100 + i * 10 + s
        },
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

// ─────────────────────────────────────────────────────────────────────────────
// 「继续收听」提示：冷启动检测到上次未播完的歌曲时的 UI 阶段。
// ─────────────────────────────────────────────────────────────────────────────

/// 一条待续播断点：曲目 + 上次中断位置。信息直接来自队列快照，
/// 不依赖 mediaItem 是否已装载完成（音源解析失败时提示依然可见）。
class ResumePrompt {
  final Song song;
  final Duration position;
  const ResumePrompt({required this.song, required this.position});
}

/// 冷启动续播的 UI 状态：
/// - [prompt] 非空：展示「继续收听」提示栏；
/// - [awaitingFirstPlay] 为真：用户尚未确认续播，抑制固定播放条
///   （含「忽略提示」后仍在待机的情况），避免一进 App 就看到播放条。
class ResumePromptState {
  final ResumePrompt? prompt;
  final bool awaitingFirstPlay;
  const ResumePromptState({this.prompt, this.awaitingFirstPlay = false});
  static const hidden = ResumePromptState();
}

class ResumePromptController extends StateNotifier<ResumePromptState> {
  ResumePromptController() : super(ResumePromptState.hidden);

  /// 启动时发现未播完的断点。
  void found(ResumePrompt prompt) =>
      state = ResumePromptState(prompt: prompt, awaitingFirstPlay: true);

  /// 用户点「关闭」忽略提示：撤下提示栏，但仍不冒出固定播放条
  /// ——本次会话从未真正起播过。下次冷启动若断点仍在会再次提示。
  void dismiss() {
    if (state.prompt == null) return;
    state = const ResumePromptState(awaitingFirstPlay: true);
  }

  /// 用户点了提示栏续播，或经播放页 / 通知栏等其它入口起播、点播新队列、
  /// 切歌、清空队列、曲目播完：提示使命结束，播放条回到
  /// 「有 mediaItem 就显示」的正常逻辑。
  void markStarted() {
    if (state.prompt == null && !state.awaitingFirstPlay) return;
    state = ResumePromptState.hidden;
  }
}

/// 读取断点快照中「仍未播完」的信息；无快照 / 数据损坏 / 已播完返回 null。
/// [QueueSnapshotStore._restore] 与 [resumePromptProvider] 共用同一判定，
/// 保证「提示出现」与「队列恢复」永远一致。
({List<Song> songs, int index, Duration position})? _readPendingQueueSnapshot() {
  try {
    final raw = LocalStore.instance.getString(kQueueSnapshotKey);
    if (raw == null || raw.isEmpty) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final songs = (j['songs'] as List? ?? const [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
    final index = (j['index'] as num?)?.toInt() ?? -1;
    final positionMs = (j['positionMs'] as num?)?.toInt() ?? 0;
    if (songs.isEmpty || index < 0 || index >= songs.length) return null;
    final duration = songs[index].duration;
    // 已播完（留 1s 容差吸收进度上报误差）：不算「未播完歌曲」。
    if (duration > 0 && positionMs >= duration - kResumeTailToleranceMs) {
      return null;
    }
    return (
      songs: songs,
      index: index,
      position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
    );
  } catch (_) {
    return null;
  }
}

/// 「继续收听」提示状态：初始同步读一次快照，故 AppShell 首帧即可正确
/// 决定「显示提示栏 / 隐藏播放条」，不会先闪一下播放条。
final resumePromptProvider =
    StateNotifierProvider<ResumePromptController, ResumePromptState>((ref) {
  final controller = ResumePromptController();
  final snap = _readPendingQueueSnapshot();
  if (snap != null) {
    controller.found(ResumePrompt(
      song: snap.songs[snap.index],
      position: snap.position,
    ));
  }
  return controller;
});

/// 播放现场断点持久化（断点续听）：
/// - 启动时读快照，把上次的播放队列恢复为**暂停态**（装队列 + 预载音源 +
///   seek 到断点，不自动出声），见 NcmAudioHandler.restoreQueue；
/// - 会话中在「队列变化 / 播放中→暂停 / App 退后台」时回写快照；
///   队列清空则删除快照（避免下次恢复出一个空队列）。
/// 进度只在播放器已装载当前曲时才写入——切歌窗口里 loadedSongId 为空或
/// 还是上一首，此时断点应记 0（新曲从头恢复）。
class QueueSnapshotStore extends WidgetsBindingObserver {
  final NcmAudioHandler _handler;
  final ResumePromptController _resume;
  StreamSubscription<QueueSnapshot>? _queueSub;
  StreamSubscription<PlaybackState>? _stateSub;
  bool _lastPlaying = false;
  bool _restoring = false;
  bool _wasInBackground = false;

  QueueSnapshotStore(this._handler, this._resume) {
    _restore();
    _queueSub = _handler.queueStream.listen((_) {
      _save();
      // 恢复期之外任何队列变化（点播新歌 / 切歌 / 清空）都意味着本次
      // 冷启动断点已被新的用户操作取代：撤下提示并结束待机抑制。
      if (!_restoring) _resume.markStarted();
    });
    _stateSub = _handler.playbackState.listen((s) {
      // 播放中 → 暂停：此刻播放器位置就是最准的断点。
      if (_lastPlaying && !s.playing) _save();
      _lastPlaying = s.playing;
      // 真的开始播放（点了提示栏续播，或经播放页 / 通知栏等其它入口
      // 起播）：提示使命完成，回到正常播放条。
      if (s.playing && !_restoring) _resume.markStarted();
      // 曲目播完：提示立即失效。快照交给 _save() 处理（「已播完不落盘」
      // 分支删除，自动切到下一曲则写入新曲断点）——此处不直接删 key，
      // 否则 completed 事件晚于队列变化时会把刚写好的新断点误删。
      if (s.processingState == AudioProcessingState.completed) {
        _resume.markStarted();
        _save();
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  /// 读本地快照并恢复队列。无快照 / 损坏 / 已播完一律清除并按全新会话启动；
  /// 恢复期间挂起回写，防止装载途中 loadedSongId 尚空把断点进度覆盖成 0。
  void _restore() {
    final snap = _readPendingQueueSnapshot();
    if (snap == null) {
      LocalStore.instance.remove(kQueueSnapshotKey);
      return;
    }
    _restoring = true;
    try {
      _handler
          .restoreQueue(snap.songs, snap.index, snap.position)
          .whenComplete(() => _restoring = false);
    } catch (_) {
      _restoring = false;
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
    // 曲目已播完：不落盘。否则下次冷启动会把播完的歌当成断点恢复、
    // 再弹一次「继续收听」（顺序模式到队尾时尤其明显）。
    final duration = snap.index < snap.songs.length
        ? snap.songs[snap.index].duration
        : 0;
    if (duration > 0 && positionMs >= duration - kResumeTailToleranceMs) {
      sp.remove(kQueueSnapshotKey);
      return;
    }
    try {
      sp.setString(
          kQueueSnapshotKey,
          jsonEncode({
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
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台：handler 负责「会话/焦点重申请 + UI/真实状态对账 + 陈旧引擎
      // 标记重建」。不在此处预防性重载音源（会造成切换停顿并废掉过期判断）。
      if (_wasInBackground) {
        _wasInBackground = false;
        unawaited(_handler.reactivateForForeground());
        // 通知权限被拒 → 前台服务易被 ColorOS 冻结，给出一次性引导。
        unawaited(NotificationPermission.guideIfDisabled(_handler.notifyUser));
      }
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
  final store = QueueSnapshotStore(
    ref.watch(audioHandlerProvider),
    ref.watch(resumePromptProvider.notifier),
  );
  ref.onDispose(store.dispose);
  return store;
});

/// 登录用户资料：随登录态变化自动重算；未登录返回空实例。
final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  final authed =
      ref.watch(authStateProvider).status == AuthStatus.authenticated;
  if (!authed) return const UserProfile(userId: 0, nickname: '', avatarUrl: '');
  // 慢网络下一次超时不该把资料（及依赖 uid 的收藏/歌单云端同步）永久打成
  // 空userId：失败短退避重试两次，仍失败才按空资料降级。
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return await ref.watch(apiProvider).userAccount();
    } catch (_) {
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }
  return const UserProfile(userId: 0, nickname: '', avatarUrl: '');
});

/// 热搜关键词榜（失败由 UI 侧静默降级，不阻塞搜索页）。
final hotSearchProvider =
    FutureProvider<List<String>>((ref) => ref.watch(apiProvider).hotSearch());

/// 单曲评论某一 Tab 的分页/加载状态（首屏 loading、首屏 error、加载更多态）。
class CommentsState {
  final List<Comment> comments;
  final int total;
  final bool hasMore;
  final bool loading; // 首屏加载
  final bool loadingMore; // 追加分页中
  final String? error; // 首屏错误文案（null = 无错误）
  const CommentsState({
    this.comments = const [],
    this.total = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  CommentsState copyWith({
    List<Comment>? comments,
    int? total,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) =>
      CommentsState(
        comments: comments ?? this.comments,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 单曲评论分页状态机：按 (songId, tab) 双键管理，autoDispose —— 面板关闭或
/// 切歌后立即释放，避免串台与脏数据。热门（hot）只取首页、不分页；最新
/// （latest）按 offset 翻页。防重入：同一 offset 在请求中不重复发起。
class CommentsNotifier extends StateNotifier<CommentsState> {
  CommentsNotifier(this._api, this.songId, this.tab)
      : super(const CommentsState(loading: true)) {
    load();
  }
  final NcmApi _api;
  final int songId;
  final CommentTab tab;

  static const int _limit = 20;
  int _offset = 0;
  bool _requesting = false;
  bool _loaded = false;

  /// 首屏加载（offset=0）。幂等：已加载或加载中不重复触发。
  Future<void> load() async {
    if (_loaded || _requesting) return;
    _requesting = true;
    state = const CommentsState(loading: true);
    try {
      final page = await _api.songComments(songId,
          hot: tab == CommentTab.hot, limit: _limit, offset: 0);
      _loaded = true;
      _offset = page.comments.length;
      state = CommentsState(
        total: page.total,
        comments: page.comments,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = CommentsState(error: e.userMessage);
    } catch (_) {
      state = const CommentsState(error: '评论加载失败，请稍后重试');
    } finally {
      _requesting = false;
    }
  }

  /// 加载更多（仅最新 Tab 有效；热门为固定集合不分页）。
  Future<void> loadMore() async {
    if (tab == CommentTab.hot) return; // 热门不分页
    if (_requesting || state.loadingMore || !state.hasMore) return;
    _requesting = true;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _api.songComments(songId,
          hot: false, limit: _limit, offset: _offset);
      _offset += page.comments.length;
      state = state.copyWith(
        comments: [...state.comments, ...page.comments],
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loadingMore: false, error: e.userMessage);
    } catch (_) {
      state = state.copyWith(loadingMore: false);
    } finally {
      _requesting = false;
    }
  }
}

/// 单曲评论 Provider 家族：键为 (songId, tab)。autoDispose 保证面板关闭即回收。
final songCommentsProvider = StateNotifierProvider.autoDispose
    .family<CommentsNotifier, CommentsState, (int, CommentTab)>(
  (ref, key) => CommentsNotifier(ref.watch(apiProvider), key.$1, key.$2),
);
