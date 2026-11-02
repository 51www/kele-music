import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../local/local_screen.dart';
import '../player/play_utils.dart' as play;

void _toast(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1800),
    content: Text(e is ApiException ? e.userMessage : '操作失败，请稍后重试'),
  ));
}

/// 音乐库：三个页签——「单曲」（收藏的歌曲）、「歌单」（我创建的 + 我收藏的）
/// 与「本地」（本机音频歌单，见 LocalScreen）。
/// 收藏数据随登录态自动切换来源：已登录同步自账号，未登录来自本机。
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
    final sp = AppSpacing.of(context);
    final likedSongs = ref.watch(likedSongsProvider);
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
          child: AppContentColumn(
            child: Padding(
              padding: sp.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: sp.block),
                    child: Text('音乐库',
                        style: TextStyle(
                            color: style.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          controller: _tab,
                          dividerColor: Colors.transparent,
                          indicatorColor: style.accent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          labelColor: style.textPrimary,
                          unselectedLabelColor: style.textSecondary,
                          tabs: const [
                            Tab(text: '单曲'),
                            Tab(text: '歌单'),
                            Tab(text: '本地'),
                          ],
                        ),
                      ),
                      // 「本地」页签的紧凑新建入口（随页签切换显隐）。
                      AnimatedBuilder(
                        animation: _tab,
                        builder: (_, __) => _tab.index == 2
                            ? _buildCreateLocalButton(style)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  SizedBox(height: sp.block),
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _buildSongs(style, likedSongs, authed),
                        _buildPlaylistsTab(style, created, favPlaylists, authed),
                        const LocalScreen(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 本地页签：页签行右侧的紧凑「新建」入口 ────────────────────

  Widget _buildCreateLocalButton(AppStyle style) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: SizedBox(
        height: 30,
        child: OutlinedButton.icon(
          onPressed: () => createLocalPlaylist(context, ref),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: style.surfaceBorder),
            foregroundColor: style.textPrimary,
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w500),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(style.uiRadius),
            ),
          ),
          icon: Icon(Icons.add, size: 15, color: style.accent),
          label: const Text('新建'),
        ),
      ),
    );
  }

  // ── 单曲页签：收藏的歌曲 ────────────────────────────────────

  /// 下拉刷新：资料重算（登录态/uid 失败缓存借此恢复）+ 收藏列表重载。
  Future<void> _refreshSongs() async {
    ref.invalidate(userProfileProvider);
    await ref.read(likedSongsProvider.notifier).refresh();
  }

  Widget _buildSongs(AppStyle style, LikedSongsState likedState, bool authed) {
    final sp = AppSpacing.of(context);
    final liked = likedState.songs;
    if (liked.isEmpty) {
      return RefreshIndicator(
        color: style.accent,
        onRefresh: _refreshSongs,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: sp.section),
            EmptyState(
                icon: Icons.favorite_border,
                title: '还没有收藏的单曲',
                hint: authed
                    ? '在歌曲 ⋮ 菜单或播放页点击 ♥ 收藏，将同步到你的账号'
                    : '在歌曲 ⋮ 菜单或播放页点击 ♥ 收藏，将保存在本机'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: style.accent,
      onRefresh: _refreshSongs,
      child: NotificationListener<ScrollNotification>(
        // 滚动位置触发翻页：接近底部（400px 内）即拉下一页。相比在
        // itemBuilder 里触发，滚动事件不依赖列表重建——上一页失败/复位
        // 后用户继续滑动就能再次发起，不会卡死。
        onNotification: (n) {
          final m = n.metrics;
          if (likedState.hasMore && m.pixels >= m.maxScrollExtent - 400) {
            unawaited(ref.read(likedSongsProvider.notifier).loadMore());
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: sp.scrollPadding,
          // 末尾多一行状态行（还有更多时）：加载中转圈 / 空闲提示可重试。
          itemCount: liked.length + (likedState.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => Divider(
              color: style.textSecondary.withValues(alpha: 0.12),
              height: 1,
              indent: 4),
          itemBuilder: (c, i) {
            if (i >= liked.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: likedState.loadingMore
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: style.accent))
                      : Text('上滑加载更多',
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 12.5)),
                ),
              );
            }
            final s = liked[i];
            return SongTile(
              song: s,
              index: i + 1,
              onTap: () => play.playAndOpen(ref, context, liked, i),
              trailing: IconButton(
                icon: Icon(Icons.favorite, color: style.accent, size: 20),
                tooltip: '取消收藏',
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
        ),
      ),
    );
  }

  // ── 歌单页签：我创建的 + 我收藏的 ────────────────────────────

  Widget _buildPlaylistsTab(AppStyle style, AsyncValue<List<Playlist>> created,
      List<Playlist> favPlaylists, bool authed) {
    return created.when(
      loading: () => const Center(
          child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4))),
      error: (_, __) =>
          _playlistSections(style, const [], favPlaylists, authed),
      data: (list) => RefreshIndicator(
        color: style.accent,
        onRefresh: () async => ref.invalidate(myPlaylistsProvider),
        child: _playlistSections(style, list, favPlaylists, authed),
      ),
    );
  }

  Widget _playlistSections(AppStyle style, List<Playlist> created,
      List<Playlist> favPlaylists, bool authed) {
    final sp = AppSpacing.of(context);
    if (created.isEmpty && favPlaylists.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: sp.section),
          EmptyState(
              icon: Icons.bookmark_border,
              title: '还没有歌单',
              hint: authed
                  ? '收藏的歌单将同步到你的账号；创建的歌单登录后自动同步'
                  : '在歌单详情页点击右上角 ⛉ 收藏，将保存在本机'),
        ],
      );
    }
    return ListView(
      padding: sp.scrollPadding,
      children: [
        if (created.isNotEmpty) ...[
          _sectionHeader(style, '我创建的'),
          for (final p in created) _playlistTile(style, p),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (favPlaylists.isNotEmpty) ...[
          _sectionHeader(style, '我收藏的'),
          for (final p in favPlaylists) _playlistTile(style, p, favorited: true),
        ],
      ],
    );
  }

  Widget _sectionHeader(AppStyle style, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.micro, AppSpacing.sm, AppSpacing.micro, AppSpacing.xxs),
        child: Text(text,
            style: TextStyle(
                color: style.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _playlistTile(AppStyle style, Playlist p, {bool favorited = false}) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.micro),
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
      trailing: favorited
          ? IconButton(
              icon: Icon(Icons.bookmark, color: style.accent, size: 20),
              tooltip: '取消收藏',
              onPressed: () async {
                try {
                  await ref
                      .read(favoritePlaylistsProvider.notifier)
                      .toggle(p);
                } catch (e) {
                  if (mounted) _toast(context, e);
                }
              },
            )
          : Icon(Icons.chevron_right,
              color: style.textSecondary, size: 20),
      onTap: () => context.push('/playlist/${p.id}'),
    );
  }
}
