import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass.dart';
import '../../core/styles.dart';
import '../../providers.dart';

/// 「更多」菜单：收纳下载、添加到歌单、查看歌曲信息等次要操作（与 song_actions
/// 面板同构的图标 + 文字行）。具体动作由调用方以回调注入（逻辑归属播放页）。
void showMoreSheet(BuildContext context,
    {required VoidCallback onDownload,
    required VoidCallback onInfo,
    VoidCallback? onAddToPlaylist}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MoreSheet(
        onDownload: onDownload,
        onInfo: onInfo,
        onAddToPlaylist: onAddToPlaylist),
  );
}

class _MoreSheet extends ConsumerWidget {
  final VoidCallback onDownload;
  final VoidCallback onInfo;
  final VoidCallback? onAddToPlaylist;
  const _MoreSheet(
      {required this.onDownload, required this.onInfo, this.onAddToPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final radius = BorderRadius.circular(style.uiRadius + 8);
    final items = <(IconData, String, VoidCallback)>[
      (Icons.download_outlined, '下载', onDownload),
      if (onAddToPlaylist != null)
        (Icons.library_add_rounded, '添加到歌单', onAddToPlaylist!),
      (Icons.info_outline, '查看歌曲信息', onInfo),
    ];

    return SafeArea(
      top: false,
      child: AMGlass(
        kind: AMGlassKind.sheet,
        animateAppearance: true,
        borderRadius: radius,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: style.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            for (final (icon, label, action) in items)
              InkWell(
                borderRadius: BorderRadius.circular(style.uiRadius),
                onTap: () {
                  Navigator.of(context).pop();
                  action();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(icon, size: 21, color: style.textPrimary),
                      const SizedBox(width: 14),
                      Text(label,
                          style: TextStyle(
                              color: style.textPrimary, fontSize: 14)),
                      const Spacer(),
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
