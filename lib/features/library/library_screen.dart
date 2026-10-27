import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

void _toast(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1800),
    content: Text(e is ApiException ? e.userMessage : '操作失败，请稍后重试'),
  ));
}

/// 音乐库：聚合「我创建的歌单（云端）」与「收藏的歌单」。
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
    final sp = AppSpacing.of(context);
    // 收藏已迁移到云端（/playlist/subscribe），登录后自动同步。
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
                      Tab(text: '创建'),
                      Tab(text: '收藏'),
                    ],
                  ),
                  SizedBox(height: sp.block),
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
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
      ),
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
    final sp = AppSpacing.of(context);
    if (list.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: sp.section),
          EmptyState(
              icon: Icons.queue_music,
              title: '没有创建的歌单',
              hint: '登录后自动同步你在平台创建的歌单'),
        ],
      );
    }
    return ListView.separated(
      padding: sp.scrollPadding,
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) {
        final p = list[i];
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
          trailing:
              Icon(Icons.chevron_right, color: style.textSecondary, size: 20),
          onTap: () => context.push('/playlist/${p.id}'),
        );
      },
    );
  }

  /// 云端收藏的歌单：未登录给登录引导。
  Widget _buildPlaylists(
      AppStyle style, List<Playlist> favPlaylists, bool authed) {
    if (favPlaylists.isEmpty) {
      return EmptyState(
          icon: Icons.bookmark_border,
          title: authed ? '还没有收藏的歌单' : '登录后同步你收藏的歌单',
          hint: authed ? '在歌单详情页点击右上角 ⛉ 收藏' : '登录后你在平台收藏的歌单自动出现在这里');
    }
    return ListView.separated(
      padding: AppSpacing.of(context).scrollPadding,
      itemCount: favPlaylists.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: AppSpacing.micro),
      itemBuilder: (c, i) {
        final p = favPlaylists[i];
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
