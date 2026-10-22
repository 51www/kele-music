import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

void _toast(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1800),
    content: Text(e is ApiException ? e.userMessage : '操作失败，请稍后重试'),
  ));
}

/// 音乐库：聚合「收藏的歌曲」「我创建的歌单（云端）」与「收藏的歌单」。
/// 从「我的」二级入口升级为一级 Tab。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    // 收藏已迁移到网易云云端（/like、/playlist/subscribe），登录后自动同步。
    final favorites = ref.watch(likedSongsProvider);
    final favPlaylists = ref.watch(favoritePlaylistsProvider);
    final created = ref.watch(myPlaylistsProvider);
    final authed =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Text('音乐库',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
                // 数量徽标 Tab。
                TabBar(
                  controller: _tab,
                  dividerColor: Colors.transparent,
                  indicatorColor: style.accent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: style.textPrimary,
                  unselectedLabelColor: style.textSecondary,
                  tabs: const [
                    Tab(text: '歌曲'),
                    Tab(text: '创建'),
                    Tab(text: '收藏'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildSongs(style, favorites, authed),
                      _buildCreated(style, created),
                      _buildPlaylists(style, favPlaylists, authed),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 云端「我喜欢的音乐」：未登录给登录引导，已登录展示云端列表。
  Widget _buildSongs(AppStyle style, List<Song> favorites, bool authed) {
    if (favorites.isEmpty) {
      return EmptyState(
          icon: Icons.favorite_border,
          title: authed ? '还没有喜欢的歌曲' : '登录后同步你喜欢的音乐',
          hint: authed
              ? '在播放页点击 ♥ 喜欢歌曲，自动同步到网易云'
              : '登录后网易云「我喜欢的音乐」自动出现在这里');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: favorites.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) {
        final s = favorites[i];
        return SongTile(
          song: s,
          onTap: () => play.playAndOpen(ref, context, favorites, i),
          trailing: IconButton(
            icon: Icon(Icons.favorite, color: style.accent, size: 20),
            tooltip: '取消喜欢',
            onPressed: () async {
              try {
                await ref.read(likedSongsProvider.notifier).toggle(s);
              } catch (e) {
                if (mounted) _toast(context, e);
              }
            },
          ),
        );
      },
    );
  }

  /// 我创建的歌单（云端，需登录）：下拉刷新；未登录/无数据给引导空态。
  Widget _buildCreated(AppStyle style, AsyncValue<List<Playlist>> created) {
    return created.when(
      loading: () => const Center(
          child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4))),
      error: (_, __) => _buildCreatedList(style, const []),
      data: (list) => RefreshIndicator(
        color: style.accent,
        onRefresh: () async => ref.invalidate(myPlaylistsProvider),
        child: _buildCreatedList(style, list),
      ),
    );
  }

  Widget _buildCreatedList(AppStyle style, List<Playlist> list) {
    if (list.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          EmptyState(
              icon: Icons.queue_music,
              title: '没有创建的歌单',
              hint: '登录后自动同步你在网易云创建的歌单'),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) {
        final p = list[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CoverImage(
              url: p.coverImgUrl,
              size: 52,
              radius: BorderRadius.circular(style.uiRadius / 2)),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: style.textPrimary)),
          subtitle: Text('${p.trackCount} 首',
              style: TextStyle(color: style.textSecondary, fontSize: 12)),
          trailing: Icon(Icons.chevron_right,
              color: style.textSecondary, size: 20),
          onTap: () => context.push('/playlist/${p.id}'),
        );
      },
    );
  }

  /// 云端收藏的歌单：未登录给登录引导。
  Widget _buildPlaylists(AppStyle style, List<Playlist> favPlaylists,
      bool authed) {
    if (favPlaylists.isEmpty) {
      return EmptyState(
          icon: Icons.bookmark_border,
          title: authed ? '还没有收藏的歌单' : '登录后同步你收藏的歌单',
          hint: authed
              ? '在歌单详情页点击右上角 ⛉ 收藏'
              : '登录后你在网易云收藏的歌单自动出现在这里');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: favPlaylists.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) {
        final p = favPlaylists[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CoverImage(
              url: p.coverImgUrl,
              size: 52,
              radius: BorderRadius.circular(style.uiRadius / 2)),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: style.textPrimary)),
          subtitle: Text('${p.trackCount} 首',
              style: TextStyle(color: style.textSecondary, fontSize: 12)),
          trailing: IconButton(
            icon: Icon(Icons.bookmark, color: style.accent, size: 20),
            tooltip: '取消收藏',
            onPressed: () async {
              try {
                await ref.read(favoritePlaylistsProvider.notifier).toggle(p);
              } catch (e) {
                if (mounted) _toast(context, e);
              }
            },
          ),
          onTap: () => context.push('/playlist/${p.id}'),
        );
      },
    );
  }
}
