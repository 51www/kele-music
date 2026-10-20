import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/login_screen.dart';
import '../features/discover/discover_screen.dart';
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
      // 初始化中（恢复 cookie + 校验）暂不强制跳转，避免闪烁到登录页。
      final status = ref.read(authStateProvider).status;
      if (status == AuthStatus.unknown) return null;
      final loggedIn = status == AuthStatus.authenticated || const bool.fromEnvironment('SKIP_AUTH');
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
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
          GoRoute(path: '/library', builder: (c, s) => const LibraryScreen()),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
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
