import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 行内三点菜单的操作项。
enum _ListAction { rename, delete }

void _showToast(BuildContext context, WidgetRef ref, String msg,
        {bool success = true}) =>
    showAppToast(context, ref, msg, success: success);

/// 新建 / 重命名共用的名称输入对话框；取消或名称为空返回 null。
Future<String?> promptPlaylistName(BuildContext context, WidgetRef ref,
    {String? initial}) async {
  final style = kStyles[ref.read(styleIndexProvider)];
  final controller = TextEditingController(text: initial ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor:
          Color.alphaBlend(style.surface, const Color(0x8C000000)),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 4),
          side: BorderSide(color: style.surfaceBorder)),
      title: Text(initial == null ? '新建歌单' : '重命名歌单',
          style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 30,
        cursorColor: style.accent,
        style: TextStyle(color: style.textPrimary, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: '输入歌单名称',
          hintStyle: TextStyle(color: style.textSecondary, fontSize: 13.5),
          counterStyle: TextStyle(color: style.textSecondary, fontSize: 11),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: style.surfaceBorder)),
          focusedBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: style.accent)),
        ),
        onSubmitted: (v) => Navigator.of(dctx).pop(v.trim()),
      ),
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
          onPressed: () => Navigator.of(dctx).pop(controller.text.trim()),
          child: Text(initial == null ? '创建' : '保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (name == null || name.isEmpty) ? null : name;
}

/// 新建本地歌单：名称弹窗 + 写入 + 轻提示。
/// 供本页与「音乐库」页签右上角的紧凑入口共用。
Future<void> createLocalPlaylist(BuildContext context, WidgetRef ref) async {
  final name = await promptPlaylistName(context, ref);
  if (name == null) return;
  ref.read(localPlaylistsProvider.notifier).create(name);
  if (context.mounted) _showToast(context, ref, '已创建「$name」');
}

/// 本地音乐（「音乐库 → 本地」页签内容）：设备本地音频文件的歌单管理
/// （创建 / 重命名 / 删除）。数据仅存本机（LocalStore），与登录态无关；
/// 歌单详情与播放见 LocalPlaylistDetailScreen。作为嵌入组件使用，
/// 背景与标题由宿主页面（LibraryScreen）提供。
class LocalScreen extends ConsumerStatefulWidget {
  const LocalScreen({super.key});
  @override
  ConsumerState<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends ConsumerState<LocalScreen> {
  void _toast(String msg) => _showToast(context, ref, msg);

  Future<void> _rename(LocalPlaylist p) async {
    final name = await promptPlaylistName(context, ref, initial: p.name);
    if (name == null || name == p.name) return;
    ref.read(localPlaylistsProvider.notifier).rename(p.id, name);
    _toast('已重命名为「$name」');
  }

  void _confirmDelete(LocalPlaylist p) {
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
            p.songs.isEmpty
                ? '歌单将被删除，本机音频文件不受影响。'
                : '歌单及其内 ${p.songs.length} 首曲目条目将被删除，本机音频文件不受影响。',
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
              ref.read(localPlaylistsProvider.notifier).remove(p.id);
              _toast('已删除「${p.name}」');
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_ListAction> _menuItem(
          AppStyle style, IconData icon, String label, _ListAction value) =>
      PopupMenuItem<_ListAction>(
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
    final playlists = ref.watch(localPlaylistsProvider);

    // 嵌入「音乐库 → 本地」页签的内容组件：背景/标题/页签由 LibraryScreen 提供。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: playlists.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: sp.section),
                    const EmptyState(
                        icon: Icons.speaker,
                        title: '还没有本地歌单',
                        hint: '点击页签右侧「新建」创建，再导入设备中的音频文件'),
                  ],
                )
              : ListView.separated(
                  padding: sp.scrollPadding,
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => Divider(
                      color: style.textSecondary
                                    .withValues(alpha: 0.12),
                                height: 1,
                                indent: 4),
                            itemBuilder: (c, i) {
                              final p = playlists[i];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.micro),
                                leading: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color:
                                        style.accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(
                                        style.uiRadius / 2),
                                    border: Border.all(
                                        color: style.surfaceBorder),
                                  ),
                                  child: Icon(Icons.speaker,
                                      color: style.accent, size: 24),
                                ),
                                title: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: style.textPrimary)),
                                subtitle: Text('${p.songs.length} 首',
                                    style: TextStyle(
                                        color: style.textSecondary,
                                        fontSize: 12)),
                                trailing: PopupMenuButton<_ListAction>(
                                  icon: Icon(Icons.more_vert,
                                      color: style.textSecondary, size: 20),
                                  padding: EdgeInsets.zero,
                                  splashRadius: 18,
                                  color: Color.alphaBlend(
                                      style.surface, style.bgBottom),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        style.uiRadius),
                                    side: BorderSide(
                                        color: style.surfaceBorder),
                                  ),
                                  onSelected: (a) {
                                    switch (a) {
                                      case _ListAction.rename:
                                        _rename(p);
                                      case _ListAction.delete:
                                        _confirmDelete(p);
                                    }
                                  },
                                  itemBuilder: (c) => [
                                    _menuItem(style, Icons.edit_outlined,
                                        '重命名', _ListAction.rename),
                                    _menuItem(style, Icons.delete_outline,
                                        '删除', _ListAction.delete),
                                  ],
                                ),
                                onTap: () =>
                                    context.push('/local-playlist/${p.id}'),
                              );
                            },
                          ),
        ),
      ],
    );
  }
}
