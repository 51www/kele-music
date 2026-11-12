import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../local/local_screen.dart';
import '../player/play_utils.dart' as play;

/// 音乐库：四个页签——「单曲」（收藏的歌曲）、「收藏」（收藏的歌单 + 固定的
/// 「我喜欢的音乐」入口）、「创建」（用户自建歌单，可增删改；登录后与云端账号
/// 同步，未登录仅存本机）与「本地」（本机音频歌单，见 LocalScreen）。
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
    _tab = TabController(length: 4, vsync: this);
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
    final created = ref.watch(createdPlaylistsProvider);
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
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4)),
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
                            Tab(text: '收藏'),
                            Tab(text: '创建'),
                            Tab(text: '本地'),
                          ],
                        ),
                      ),
                      // 页签行右侧的紧凑「新建」入口：仅「创建」（新建歌单）
                      // 与「本地」（新建本地歌单）页签显示，样式一致。
                      AnimatedBuilder(
                        animation: _tab,
                        builder: (_, __) => _tab.index == 2
                            ? _buildCreateButton(
                                style, () => _createPlaylist(authed))
                            : _tab.index == 3
                                ? _buildCreateButton(
                                    style, () => createLocalPlaylist(context, ref))
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
                        _buildFavTab(style, favPlaylists, likedSongs, authed),
                        _buildCreatedTab(style, created, authed),
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

  // ── 页签行右侧的紧凑「新建」入口（与「本地」歌单样式一致） ──

  Widget _buildCreateButton(AppStyle style, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: SizedBox(
        height: 30,
        child: OutlinedButton.icon(
          onPressed: onPressed,
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

  /// 新建歌单（「创建」页签）：名称弹窗 + 写入（云端 / 本机随登录态）。
  Future<void> _createPlaylist(bool authed) async {
    final name = await promptPlaylistName(context, ref);
    if (name == null || !mounted) return;
    try {
      await ref.read(createdPlaylistsProvider.notifier).create(name);
      if (mounted) {
        showAppToast(context, ref,
            authed ? '已创建「$name」，同步到你的账号' : '已创建「$name」');
      }
    } catch (e) {
      if (mounted) showErrorToast(context, ref, e);
    }
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
                    if (mounted) showErrorToast(context, ref, e);
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 收藏页签：收藏的歌单（只读）；未登录额外固定「我喜欢的音乐」入口 ──
  // 登录用户的「我喜欢的音乐」不单独展示：随云端 /user/playlist 原样出现在
  // 「创建」页签首位。

  Widget _buildFavTab(AppStyle style, List<Playlist> favPlaylists,
      LikedSongsState likedState, bool authed) {
    final sp = AppSpacing.of(context);
    return ListView(
      padding: sp.scrollPadding,
      children: [
        // 未登录：固定入口「我喜欢的音乐」，聚合本机收藏的单曲。
        if (!authed) ...[
          _likedSongsTile(
              style, likedState.songs.length, () => context.push('/liked-songs')),
        ],
        // 该页签只有收藏的歌单，不再设栏目标题，列表直接与页签行对齐
        // （顶部间距与其他页签一致，均来自 scrollPadding）。
        if (favPlaylists.isNotEmpty)
          for (final p in favPlaylists) _playlistTile(style, p)
        else
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.micro, vertical: AppSpacing.md),
            child: Text(
                authed
                    ? '在歌单详情页点击右上角 ⛉ 收藏，将同步到你的账号'
                    : '在歌单详情页点击右上角 ⛉ 收藏，将保存在本机',
                style: TextStyle(color: style.textSecondary, fontSize: 12.5)),
          ),
      ],
    );
  }

  /// 「我喜欢的音乐」固定入口：心形底座封面 + 收藏单曲数。
  Widget _likedSongsTile(AppStyle style, int count, VoidCallback onTap) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.micro),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: style.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(style.uiRadius / 2),
          border: Border.all(color: style.surfaceBorder),
        ),
        child: Icon(Icons.favorite, color: style.accent, size: 24),
      ),
      title: Text('我喜欢的音乐',
          style: TextStyle(
              color: style.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text('$count 首',
          style: TextStyle(color: style.textSecondary, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: style.textSecondary, size: 20),
      onTap: onTap,
    );
  }

  // ── 创建页签：用户自建歌单（增删改；登录后与云端同步） ──────

  Widget _buildCreatedTab(
      AppStyle style, AsyncValue<CreatedPlaylistsState> created, bool authed) {
    return created.when(
      loading: () => const Center(
          child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4))),
      error: (_, __) => _createdList(style, const [], authed),
      data: (st) => RefreshIndicator(
        color: style.accent,
        onRefresh: () =>
            ref.read(createdPlaylistsProvider.notifier).refresh(),
        child: _createdList(style, st.playlists, authed),
      ),
    );
  }

  Widget _createdList(
      AppStyle style, List<UserPlaylist> playlists, bool authed) {
    final sp = AppSpacing.of(context);
    if (playlists.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: sp.section),
          EmptyState(
              icon: Icons.playlist_add,
              title: '还没有创建歌单',
              hint: authed
                  ? '点击右上角「新建」创建，创建的歌单自动同步到你的账号；在歌曲或专辑页可将歌曲加入歌单'
                  : '点击右上角「新建」创建（保存在本机）；在歌曲或专辑页可将歌曲加入歌单'),
        ],
      );
    }
    return ListView.separated(
      padding: sp.scrollPadding,
      itemCount: playlists.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) => _createdTile(style, playlists[i]),
    );
  }

  /// 创建歌单条目：样式与「本地」歌单条目一致（⌘ 行尾 ⋮ 菜单：重命名 / 删除）。
  Widget _createdTile(AppStyle style, UserPlaylist p) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.micro),
      leading: p.cover != null
          ? CoverImage(
              url: p.cover!,
              size: 52,
              radius: BorderRadius.circular(style.uiRadius / 2))
          : Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(style.uiRadius / 2),
                border: Border.all(color: style.surfaceBorder),
              ),
              child: Icon(Icons.queue_music, color: style.accent, size: 24),
            ),
      title: Text(p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: style.textPrimary)),
      subtitle: Text('${p.count} 首',
          style: TextStyle(color: style.textSecondary, fontSize: 12)),
      trailing: p.specialType == 5
          // 「我喜欢的音乐」为系统歌单：不提供改名/删除菜单。
          ? Icon(Icons.chevron_right, color: style.textSecondary, size: 20)
          : _createdMenu(style, p),
      onTap: () {
        if (p.local) {
          context.push('/user-playlist/${p.id}');
        } else {
          context.push('/playlist/${p.id}');
        }
      },
    );
  }

  Widget _createdMenu(AppStyle style, UserPlaylist p) {
    return PopupMenuButton<_CreatedAction>(
      icon: Icon(Icons.more_vert, color: style.textSecondary, size: 20),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      color: Color.alphaBlend(style.surface, style.bgBottom),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.uiRadius),
        side: BorderSide(color: style.surfaceBorder),
      ),
      onSelected: (a) {
        switch (a) {
          case _CreatedAction.rename:
            _renamePlaylist(p);
          case _CreatedAction.delete:
            _confirmDeletePlaylist(p);
        }
      },
      itemBuilder: (c) => [
        PopupMenuItem<_CreatedAction>(
          value: _CreatedAction.rename,
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 19, color: style.textPrimary),
            const SizedBox(width: 12),
            Text('重命名',
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ]),
        ),
        PopupMenuItem<_CreatedAction>(
          value: _CreatedAction.delete,
          child: Row(children: [
            Icon(Icons.delete_outline, size: 19, color: style.textPrimary),
            const SizedBox(width: 12),
            Text('删除',
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ]),
        ),
      ],
    );
  }

  Future<void> _renamePlaylist(UserPlaylist p) async {
    final name = await promptPlaylistName(context, ref, initial: p.name);
    if (name == null || name == p.name || !mounted) return;
    try {
      await ref.read(createdPlaylistsProvider.notifier).rename(p.id, name);
      if (mounted) showAppToast(context, ref, '已重命名为「$name」');
    } catch (e) {
      if (mounted) showErrorToast(context, ref, e);
    }
  }

  /// 删除歌单：成功 / 失败均以轻量浮层提示。
  Future<void> _deletePlaylist(UserPlaylist p) async {
    try {
      await ref.read(createdPlaylistsProvider.notifier).remove(p.id);
      if (mounted) showAppToast(context, ref, '已删除「${p.name}」');
    } catch (e) {
      if (mounted) showErrorToast(context, ref, e);
    }
  }

  void _confirmDeletePlaylist(UserPlaylist p) {
    final style = kStyles[ref.read(styleIndexProvider)];
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor:
            Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text('删除歌单「${p.name}」？',
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: Text(
            p.local && (p.tracks?.isNotEmpty ?? false)
                ? '歌单及其内 ${p.tracks!.length} 首曲目条目将被删除。'
                : '歌单将被删除。',
            style: TextStyle(color: style.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text('取消', style: TextStyle(color: style.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: style.accent,
              foregroundColor: style.bgBottom,
            ),
            onPressed: () {
              Navigator.of(dctx).pop();
              _deletePlaylist(p);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ── 公共 ────────────────────────────────────────────────────


  Widget _playlistTile(AppStyle style, Playlist p) {
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
      trailing: Icon(Icons.chevron_right,
          color: style.textSecondary, size: 20),
      onTap: () => context.push('/playlist/${p.id}'),
    );
  }
}

enum _CreatedAction { rename, delete }
