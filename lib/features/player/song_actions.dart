import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'play_utils.dart' as play;

/// 歌曲操作面板（列表行 ⋮ 唤起）：
/// 播放 / 收藏（动态态）/ 下载 / 加入播放列表 / 查看歌曲信息。
/// 搜索、歌单详情、收藏列表等场景可复用。
Future<void> showSongActionsSheet(
    BuildContext context, WidgetRef ref, Song song) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SongActionsSheet(song: song),
  );
}

class _SongActionsSheet extends ConsumerWidget {
  final Song song;
  const _SongActionsSheet({required this.song});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1400),
    ));
  }

  Future<void> _act(BuildContext context, WidgetRef ref, _Action a) async {
    Navigator.of(context).pop();
    final liked = ref.read(likedSongsProvider.notifier);
    switch (a) {
      case _Action.play:
        await play.playAndOpen(ref, context, [song], 0);
        return;
      case _Action.favorite:
        // 云端喜欢（/like）：乐观更新失败回滚，错误浮层提示。
        final willFav = !liked.isFavorite(song.id);
        try {
          await liked.toggle(song);
          _toast(context, willFav ? '已收藏，同步到「我喜欢的音乐」' : '已取消收藏');
        } catch (e) {
          _toast(context,
              e is ApiException ? e.userMessage : '操作失败，请稍后重试');
        }
        return;
      case _Action.download:
        _toast(context, '下载功能即将上线，敬请期待');
        return;
      case _Action.addToQueue:
        try {
          await ref.read(audioHandlerProvider).appendToQueue([song]);
          if (context.mounted) _toast(context, '已加入播放列表');
        } catch (e) {
          if (context.mounted) {
            _toast(context,
                e is ApiException ? e.userMessage : '加入失败，请稍后重试');
          }
        }
        return;
      case _Action.info:
        _showInfoDialog(context, ref);
        return;
    }
  }

  void _showInfoDialog(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.read(styleIndexProvider)];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: style.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 6),
          side: BorderSide(color: style.surfaceBorder),
        ),
        title: Text('歌曲信息',
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(style, '歌曲', song.name),
            _infoRow(style, '歌手', song.artistName),
            _infoRow(style, '专辑', song.album.name.isEmpty ? '—' : song.album.name),
            _infoRow(style, '时长', fmtDurationMs(song.duration)),
            _infoRow(style, '版权', song.isVip ? 'VIP 专属' : '免费'),
            _infoRow(style, 'ID', '${song.id}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('关闭', style: TextStyle(color: style.accent)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(AppStyle style, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style:
                    TextStyle(color: style.textSecondary, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(color: style.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    // watch 列表本身：云端喜欢状态变化时面板图标即时刷新。
    final favited =
        ref.watch(likedSongsProvider.select((l) => l.any((s) => s.id == song.id)));

    final actions = <(_Action, IconData, String)>[
      (_Action.play, Icons.play_arrow_rounded, '播放'),
      (
        _Action.favorite,
        favited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        favited ? '取消收藏' : '收藏'
      ),
      (_Action.download, Icons.download_outlined, '下载'),
      (_Action.addToQueue, Icons.playlist_add_rounded, '加入播放列表'),
      (_Action.info, Icons.info_outline_rounded, '查看歌曲信息'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        decoration: BoxDecoration(
          color: style.surface,
          borderRadius: BorderRadius.circular(style.uiRadius + 8),
          border: Border.all(color: style.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部歌曲信息头：确认操作对象。
            Row(
              children: [
                CoverImage(
                    url: song.coverUrl,
                    size: 42,
                    radius: BorderRadius.circular(style.uiRadius / 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(song.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (song.isVip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: style.accent, width: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('VIP',
                        style: TextStyle(
                            color: style.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (a, icon, label) in actions)
              InkWell(
                borderRadius: BorderRadius.circular(style.uiRadius),
                onTap: () => _act(context, ref, a),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(icon, size: 21, color: style.textPrimary),
                      const SizedBox(width: 14),
                      Text(label,
                          style: TextStyle(
                              color: style.textPrimary, fontSize: 14)),
                      const Spacer(),
                      if (a == _Action.favorite && favited)
                        Icon(Icons.check_rounded,
                            size: 16, color: style.accent),
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

enum _Action { play, favorite, download, addToQueue, info }
