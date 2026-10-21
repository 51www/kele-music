import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/login_screen.dart';
import '../features/discover/all_playlists_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/history/history_screen.dart';
import '../features/library/library_screen.dart';
import '../features/playlist/playlist_detail_screen.dart';
import '../features/player/app_shell.dart';
import '../features/player/now_playing.dart';
import '../features/player/queue_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../providers.dart';

/// 把 authStateProvider 的变化转成 Listenable，供 GoRouter.refreshListenable 用。
/// 绝不能用 ref.watch(authStateProvider) 来建 GoRouter——那会导致每次登录态
/// 变化都重建整个 router（丢导航栈、旧 context 失效，扫码确认后跳转失灵）。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<AuthState>(authStateProvider, (_, __) => notifyListeners());
    ref.onDispose(dispose);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthRefreshListenable(ref);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      // 游客模式：未登录可访问全部核心页面（发现/搜索/音乐库/我的），
      // 不再强制跳登录页；登录与否只影响云端数据（创建的歌单/签到/每日推荐）。
      // 初始化中（恢复 cookie + 校验）暂不干预，避免闪烁。
      final status = ref.read(authStateProvider).status;
      if (status == AuthStatus.unknown) return null;
      final onLogin = state.matchedLocation == '/login';
      final loggedIn = status == AuthStatus.authenticated || const bool.fromEnvironment('SKIP_AUTH');
      // 已登录用户误入 /login 拉回首页；其余一律放行。
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (c, s) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child, location: s.matchedLocation),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const DiscoverScreen()),
          GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
          GoRoute(
            path: '/playlist/:id',
            builder: (c, s) =>
                PlaylistDetailScreen(id: s.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/all-playlists',
            builder: (c, s) => const AllPlaylistsScreen(),
          ),
          GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        builder: (c, s) => const NowPlayingScreen(),
      ),
      GoRoute(
        path: '/queue',
        builder: (c, s) => const QueueScreen(),
      ),
    ],
  );
});
