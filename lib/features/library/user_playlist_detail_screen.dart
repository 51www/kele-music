import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../local/local_screen.dart' show promptPlaylistName;
import '../player/play_utils.dart' as play;

/// 用户创建歌单的详情页（未登录本机歌单，曲目内嵌在 CreatedPlaylistsNotifier）。
/// 支持播放全部、单曲移出歌单；右上角菜单：重命名 / 删除歌单。
/// 已登录的云端自建歌单走 /playlist/:id（PlaylistDetailScreen），不经此页。
class UserPlaylistDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const UserPlaylistDetailScreen({super.key, required this.id});

  @override
  ConsumerState<UserPlaylistDetailScreen> createState() =>
      _UserPlaylistDetailScreenState();
}

enum _PageAction { rename, delete }

class _UserPlaylistDetailScreenState
    extends ConsumerState<UserPlaylistDetailScreen> {
  void _toast(String msg) => showAppToast(context, ref, msg);

  int get _pid => int.tryParse(widget.id) ?? 0;

  UserPlaylist? _playlistById() {
    final list =
        ref.read(createdPlaylistsProvider).valueOrNull?.playlists ?? const [];
    for (final x in list) {
      if (x.id == _pid) return x;
    }
    return null;
  }

  Future<void> _rename() async {
    final p = _playlistById();
    if (p == null) return;
    final name = await promptPlaylistName(context, ref, initial: p.name);
    if (name == null || name == p.name) return;
    try {
      await ref.read(createdPlaylistsProvider.notifier).rename(_pid, name);
      _toast('已重命名为「$name」');
    } catch (e) {
      showErrorToast(context, ref, e);
    }
  }

  /// 删除歌单：成功后轻量提示并退出详情页；失败留在原页提示。
  Future<void> _delete() async {
    final name = _playlistById()?.name ?? '';
    try {
      await ref.read(createdPlaylistsProvider.notifier).remove(_pid);
      _toast('已删除「$name」');
      if (context.canPop()) context.pop();
    } catch (e) {
      showErrorToast(context, ref, e);
    }
  }

  void _confirmDelete() {
    final style = kStyles[ref.read(styleIndexProvider)];
    final p = _playlistById();
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor:
            Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text('删除歌单「${p?.name ?? ''}」？',
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: Text('歌单及其内曲目条目将被删除。',
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
              _delete();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_PageAction> _menuItem(
          AppStyle style, IconData icon, String label, _PageAction value) =>
      PopupMenuItem<_PageAction>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 19, color: style.textPrimary),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final created = ref.watch(createdPlaylistsProvider);
    final p = created.valueOrNull?.playlists
        .where((x) => x.id == _pid)
        .firstOrNull;
    final songs = p?.tracks ?? const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(0, sp.inline, 0, sp.block),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            Icon(Icons.arrow_back, color: style.textPrimary),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(p?.name ?? '歌单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: style.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                      ),
                      // 右侧留白与列表行尾图标对齐（48px 按钮内 20px 图标居中，
                      // 加 4px 行内边距 ≈ 18px），避免标题行贴边、列表不贴边。
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Text('${songs.length} 首',
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 12.5)),
                      ),
                      PopupMenuButton<_PageAction>(
                        icon: Icon(Icons.more_vert,
                            color: style.textSecondary, size: 20),
                        padding: EdgeInsets.zero,
                        splashRadius: 18,
                        color: Color.alphaBlend(style.surface, style.bgBottom),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(style.uiRadius),
                          side: BorderSide(color: style.surfaceBorder),
                        ),
                        onSelected: (a) {
                          switch (a) {
                            case _PageAction.rename:
                              _rename();
                            case _PageAction.delete:
                              _confirmDelete();
                          }
                        },
                        itemBuilder: (c) => [
                          _menuItem(style, Icons.edit_outlined, '重命名',
                              _PageAction.rename),
                          _menuItem(style, Icons.delete_outline, '删除歌单',
                              _PageAction.delete),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: songs.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: sp.section),
                            const EmptyState(
                                icon: Icons.queue_music,
                                title: '歌单是空的',
                                hint: '在歌曲或专辑页通过 ⋮ 菜单「添加到歌单」加入'),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: sp.scrollPadding,
                          itemCount: songs.length,
                          separatorBuilder: (_, __) => Divider(
                              color: style.textSecondary
                                  .withValues(alpha: 0.12),
                              height: 1,
                              indent: 4),
                          itemBuilder: (c, i) {
                            final s = songs[i];
                            return SongTile(
                              song: s,
                              index: i + 1,
                              onTap: () =>
                                  play.playAndOpen(ref, context, songs, i),
                              trailing: IconButton(
                                icon: Icon(Icons.remove_circle_outline,
                                    color: style.textSecondary, size: 20),
                                tooltip: '移出歌单',
                                onPressed: () {
                                  ref
                                      .read(createdPlaylistsProvider.notifier)
                                      .removeSong(_pid, s.id);
                                  _toast('已移出「${s.name}」');
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
