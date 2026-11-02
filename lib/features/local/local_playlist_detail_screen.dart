import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 本地歌单详情：曲目列表 + 播放全部 / 随机播放 / 导入本地音频 / 移除单曲。
/// 播放复用全局 audio handler：urlResolver 按歌曲 id 直读 file:// 本地文件。
class LocalPlaylistDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const LocalPlaylistDetailScreen({super.key, required this.id});
  @override
  ConsumerState<LocalPlaylistDetailScreen> createState() =>
      _LocalPlaylistDetailScreenState();
}

class _LocalPlaylistDetailScreenState
    extends ConsumerState<LocalPlaylistDetailScreen> {
  bool _busy = false;

  int get _pid => int.tryParse(widget.id) ?? 0;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  /// 播放队列中 [index] 处的曲目（立即跳播放页，起播在后台完成）。
  Future<void> _playAt(List<Song> songs, int index) async {
    if (songs.isEmpty || _busy) return;
    setState(() => _busy = true);
    // 以整个歌单为播放队列，播完自动切下一首。
    await play.playAndOpen(ref, context, songs, index);
    if (mounted) setState(() => _busy = false);
  }

  /// 播放整个歌单；[shuffle] 表示随机起点。
  Future<void> _playAll(List<Song> songs, {bool shuffle = false}) =>
      _playAt(songs, shuffle ? Random().nextInt(songs.length) : 0);

  /// 导入本地音频文件（系统文件选择器，多选）。Web 端文件选择器拿不到
  /// 本地路径（仅有字节流），暂不支持。
  Future<void> _addSongs() async {
    if (kIsWeb) {
      _toast('Web 端暂不支持导入本地音频，请在 App / 桌面端使用');
      return;
    }
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.audio, allowMultiple: true);
      final paths = result?.files
              .where((f) => f.path != null && f.path!.isNotEmpty)
              .map((f) => f.path!)
              .toList() ??
          const [];
      if (paths.isEmpty) return;
      final songs = paths.map(Song.fromLocalFilePath).toList();
      final added =
          ref.read(localPlaylistsProvider.notifier).addSongs(_pid, songs);
      _toast(added > 0 ? '已添加 $added 首歌曲' : '所选歌曲均已在歌单中');
    } catch (_) {
      _toast('导入失败，请重试');
    }
  }

  /// 新建 / 重命名共用的名称输入对话框；取消或名称为空返回 null。
  Future<String?> _promptName(BuildContext context, {String? initial}) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final controller = TextEditingController(text: initial ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: style.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text('重命名歌单',
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          cursorColor: style.accent,
          style: TextStyle(color: style.textPrimary, fontSize: 14.5),
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            hintStyle:
                TextStyle(color: style.textSecondary, fontSize: 13.5),
            counterStyle:
                TextStyle(color: style.textSecondary, fontSize: 11),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: style.surfaceBorder)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: style.accent)),
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _rename(LocalPlaylist p) async {
    final name = await _promptName(context, initial: p.name);
    if (name == null || name == p.name) return;
    ref.read(localPlaylistsProvider.notifier).rename(p.id, name);
    _toast('已重命名');
  }

  void _confirmDelete(LocalPlaylist p) {
    final style = kStyles[ref.read(styleIndexProvider)];
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: style.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text('删除歌单「${p.name}」？',
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: Text('歌单将被删除，本机音频文件不受影响。',
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
              if (context.canPop()) context.pop();
              _toast('已删除「${p.name}」');
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_DetailAction> _menuItem(
          AppStyle style, IconData icon, String label, _DetailAction value) =>
      PopupMenuItem<_DetailAction>(
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

  /// 图标按钮（无文字）：随机播放 / 导入音频。
  Widget _iconButton({
    required AppStyle style,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) =>
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: style.surfaceBorder),
          foregroundColor: style.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius),
          ),
        ),
        child: Icon(icon, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final playlists = ref.watch(localPlaylistsProvider);
    LocalPlaylist? p;
    for (final pl in playlists) {
      if (pl.id == _pid) {
        p = pl;
        break;
      }
    }

    // 歌单已被删除（如详情停留期间在别处删除）：给引导空态。
    // 经 final 局部变量落定后做非空判断（闭包捕获的变量无法类型提升）。
    final playlist = p;
    if (playlist == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(gradient: style.backgroundGradient),
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon:
                        Icon(Icons.arrow_back, color: style.textPrimary),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/library'),
                  ),
                ),
                const Expanded(
                  child: EmptyState(
                      icon: Icons.speaker,
                      title: '歌单不存在或已删除',
                      hint: '回到「本地」查看其它歌单'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final songs = playlist.songs;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: CustomScrollView(
              slivers: [
                // 头部：返回 + 标题 + 重命名/删除菜单。
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        sp.gutter, sp.inline, sp.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back,
                                  color: style.textPrimary),
                              onPressed: () => context.canPop()
                                  ? context.pop()
                                  : context.go('/library'),
                            ),
                            const Spacer(),
                            PopupMenuButton<_DetailAction>(
                              icon: Icon(Icons.more_vert,
                                  color: style.textSecondary, size: 20),
                              padding: EdgeInsets.zero,
                              splashRadius: 18,
                              color: Color.alphaBlend(
                                  style.surface, style.bgBottom),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(style.uiRadius),
                                side: BorderSide(
                                    color: style.surfaceBorder),
                              ),
                              onSelected: (a) {
                                switch (a) {
                                  case _DetailAction.rename:
                                    _rename(playlist);
                                  case _DetailAction.addSongs:
                                    _addSongs();
                                  case _DetailAction.delete:
                                    _confirmDelete(playlist);
                                }
                              },
                              itemBuilder: (c) => [
                                _menuItem(style, Icons.edit_outlined,
                                    '重命名', _DetailAction.rename),
                                _menuItem(style, Icons.playlist_add,
                                    '添加歌曲', _DetailAction.addSongs),
                                _menuItem(style, Icons.delete_outline,
                                    '删除', _DetailAction.delete),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color:
                                    style.accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: style.surfaceBorder),
                              ),
                              child: Icon(Icons.speaker,
                                  color: style.accent, size: 32),
                            ),
                            SizedBox(width: sp.block),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(playlist.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: style.textPrimary,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          height: 1.3)),
                                  SizedBox(height: sp.inline),
                                  Text('${songs.length} 首 · 本地音频',
                                      style: TextStyle(
                                          color: style.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 操作条：播放全部 + 随机播放 + 添加歌曲。
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        sp.gutter, sp.block, sp.gutter, sp.inline),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                songs.isEmpty || _busy ? null : () => _playAll(songs),
                            style: FilledButton.styleFrom(
                              backgroundColor: style.accent,
                              foregroundColor: style.bgBottom,
                            ),
                            icon: _busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: style.bgBottom))
                                : const Icon(Icons.play_arrow, size: 20),
                            label: const Text('播放全部'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        _iconButton(
                          style: style,
                          icon: Icons.shuffle,
                          tooltip: '随机播放',
                          onPressed: songs.isEmpty || _busy
                              ? null
                              : () => _playAll(songs, shuffle: true),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        _iconButton(
                          style: style,
                          icon: Icons.playlist_add,
                          tooltip: '添加歌曲',
                          onPressed: _addSongs,
                        ),
                      ],
                    ),
                  ),
                ),
                // 曲目列表（行尾：从歌单移除）。
                if (songs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const EmptyState(
                            icon: Icons.music_off_outlined,
                            title: '歌单是空的',
                            hint: '导入设备中的音频文件后即可播放'),
                        SizedBox(height: sp.block),
                        OutlinedButton.icon(
                          onPressed: _addSongs,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: style.surfaceBorder),
                            foregroundColor: style.textPrimary,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(style.uiRadius),
                            ),
                          ),
                          icon: Icon(Icons.playlist_add,
                              size: 18, color: style.accent),
                          label: const Text('添加歌曲'),
                        ),
                      ],
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                        horizontal: sp.gutter, vertical: sp.inline),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (c, i) => SongTile(
                          song: songs[i],
                          index: i + 1,
                          onTap: () => _playAt(songs, i),
                          trailing: IconButton(
                            icon: Icon(Icons.remove_circle_outline,
                                color: style.textSecondary, size: 20),
                            tooltip: '从歌单移除',
                            onPressed: () {
                              ref
                                  .read(localPlaylistsProvider.notifier)
                                  .removeSong(playlist.id, songs[i].id);
                              _toast('已从歌单移除');
                            },
                          ),
                        ),
                        childCount: songs.length,
                      ),
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

enum _DetailAction { rename, addSongs, delete }
