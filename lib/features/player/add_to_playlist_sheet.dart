import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors.dart';
import '../../core/glass.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../local/local_screen.dart' show promptPlaylistName;

/// 「添加到歌单」弹层：列出「创建」页签的歌单（已登录为云端账号歌单，
/// 未登录为本机歌单），点选即把 [songs] 加入对应歌单；顶部提供「新建歌单」。
/// 供歌曲行 ⋮ 面板、多选等场景复用。
Future<void> showAddToPlaylistSheet(
    BuildContext context, WidgetRef ref, List<Song> songs) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(songs: songs),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  final List<Song> songs;
  const _AddToPlaylistSheet({required this.songs});

  /// 轻提示：用调用前捕获的 [messenger] 弹出——弹层 pop 之后原 context 已
  /// 失效，不能再 ScaffoldMessenger.of(context)。
  void _toast(ScaffoldMessengerState messenger, AppStyle style, String msg,
      {bool success = true}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(buildAppSnackBar(style, msg, success: success));
  }

  String get _songLabel =>
      songs.length == 1 ? '「${songs.first.name}」' : '${songs.length} 首歌曲';

  /// 加入歌单：成功（含新增 / 已在歌单中）/ 失败（重复或网络错误）各自提示；
  /// 文案带歌曲名与目标歌单名，语气简洁友好，添加成功后立即浮层反馈。
  /// 注意：pop 后弹层的 context/ref 均失效，操作依赖预先捕获的 notifier。
  Future<void> _add(BuildContext context, WidgetRef ref, UserPlaylist p) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(createdPlaylistsProvider.notifier);
    Navigator.of(context).pop();
    try {
      final added = await notifier.addSongs(p.id, songs);
      if (songs.length == 1) {
        _toast(
            messenger,
            style,
            added > 0
                ? '已把$_songLabel加入「${p.name}」'
                : '$_songLabel已在「${p.name}」中');
      } else if (added >= songs.length) {
        _toast(messenger, style, '已把$_songLabel加入「${p.name}」');
      } else if (added > 0) {
        _toast(messenger, style, '已加入 ${added} 首，其余已在「${p.name}」中');
      } else {
        _toast(messenger, style, '${songs.length} 首都已在「${p.name}」中');
      }
    } catch (e) {
      _toast(messenger, style, e is ApiException ? e.userMessage : '加入失败，请稍后重试',
          success: false);
    }
  }

  /// 新建歌单并加入歌曲：先在弹层之上弹出名称输入框（此时 context 仍有效），
  /// 拿到名称再关弹层；pop 后仅用预先捕获的 messenger / notifier 完成创建、
  /// 加歌与提示——否则弹层 context 失效会中断后续流程（歌没加上、无提示）。
  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final name = await promptPlaylistName(context, ref);
    if (name == null || name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(createdPlaylistsProvider.notifier);
    Navigator.of(context).pop();
    try {
      final id = await notifier.create(name);
      await notifier.addSongs(id, songs);
      _toast(messenger, style, '已创建「$name」并加入$_songLabel');
    } catch (e) {
      _toast(messenger, style, e is ApiException ? e.userMessage : '创建失败，请稍后重试',
          success: false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final created = ref.watch(createdPlaylistsProvider);
    final playlists = created.valueOrNull?.playlists ?? const <UserPlaylist>[];
    final countLabel =
        songs.length > 1 ? '${songs.length} 首歌曲' : '「${songs.first.name}」';

    return SafeArea(
      top: false,
      child: AMGlass(
        kind: AMGlassKind.sheet,
        animateAppearance: true,
        borderRadius: BorderRadius.circular(style.uiRadius + 8),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加到歌单',
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('将 $countLabel 加入以下歌单',
                style: TextStyle(color: style.textSecondary, fontSize: 12)),
            SizedBox(height: sp.inline),
            Flexible(
              child: playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text('还没有创建歌单，点击下方「新建歌单」',
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 13)),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => Divider(
                          color: style.textSecondary.withValues(alpha: 0.12),
                          height: 1),
                      itemBuilder: (c, i) {
                        final p = playlists[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: p.cover != null
                              ? CoverImage(
                                  url: p.cover!,
                                  size: 42,
                                  radius:
                                      BorderRadius.circular(style.uiRadius / 2))
                              : Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: style.accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(
                                        style.uiRadius / 2),
                                    border:
                                        Border.all(color: style.surfaceBorder),
                                  ),
                                  child: Icon(Icons.queue_music,
                                      color: style.accent, size: 20),
                                ),
                          title: Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textPrimary, fontSize: 14)),
                          subtitle: Text('${p.count} 首',
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 11.5)),
                          onTap: () => _add(context, ref, p),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: style.surfaceBorder),
            InkWell(
              borderRadius: BorderRadius.circular(style.uiRadius),
              onTap: () => _createAndAdd(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 21, color: style.accent),
                    const SizedBox(width: 14),
                    Text('新建歌单',
                        style:
                            TextStyle(color: style.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
