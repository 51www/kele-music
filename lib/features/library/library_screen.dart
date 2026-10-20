import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart';

/// 音乐库：聚合「收藏的歌曲」与「收藏的歌单」（本地持久化）。
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
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final favorites = ref.watch(favoritesProvider);
    final favPlaylists = ref.watch(favoritePlaylistsProvider);

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
                  labelColor: style.textPrimary,
                  unselectedLabelColor: style.textSecondary,
                  tabs: [
                    Tab(text: '歌曲 ${favorites.length}'),
                    Tab(text: '歌单 ${favPlaylists.length}'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildSongs(style, favorites),
                      _buildPlaylists(style, favPlaylists),
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

  Widget _buildSongs(AppStyle style, List<Song> favorites) {
    if (favorites.isEmpty) {
      return EmptyState(
          icon: Icons.favorite_border,
          title: '还没有收藏的歌曲',
          hint: '在播放页点击 ♥ 收藏喜欢的音乐');
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
          onTap: () async {
            try {
              await playQueue(ref, favorites, i);
              if (context.mounted) context.push('/now-playing');
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }
          },
          trailing: IconButton(
            icon: Icon(Icons.favorite, color: style.accent, size: 20),
            tooltip: '取消收藏',
            onPressed: () =>
                ref.read(favoritesProvider.notifier).toggle(s),
          ),
        );
      },
    );
  }

  Widget _buildPlaylists(AppStyle style, List<Playlist> favPlaylists) {
    if (favPlaylists.isEmpty) {
      return EmptyState(
          icon: Icons.bookmark_border,
          title: '还没有收藏的歌单',
          hint: '在歌单详情页点击右上角 ☆ 收藏');
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
            onPressed: () =>
                ref.read(favoritePlaylistsProvider.notifier).toggle(p),
          ),
          onTap: () => context.push('/playlist/${p.id}'),
        );
      },
    );
  }
}
