import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// 播放队列界面：展示当前队列与曲目信息，
/// 点击切歌、非当前曲目可移除；支持播放模式切换与一键清空。
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final snap = ref.watch(queueProvider);
    final mode = ref.watch(playModeProvider);
    final modeNotifier = ref.watch(playModeProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: style.textPrimary),
                        onPressed: () => context.pop()),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('当前播放',
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ),
                    // 播放模式切换。
                    IconButton(
                      icon: Icon(playModeIcon(mode),
                          color: style.accent, size: 22),
                      tooltip: playModeLabel(mode),
                      onPressed: modeNotifier.cycle,
                    ),
                    // 一键清空。
                    IconButton(
                      icon: Icon(Icons.delete_sweep_outlined,
                          color: style.textSecondary, size: 22),
                      tooltip: '清空队列',
                      onPressed: snap.valueOrNull != null &&
                              snap.value!.songs.isNotEmpty
                          ? () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dc) => AlertDialog(
                                  backgroundColor: style.bgTop,
                                  title: Text('清空播放队列',
                                      style: TextStyle(
                                          color: style.textPrimary,
                                          fontSize: 16)),
                                  content: Text('将停止播放并移除全部曲目',
                                      style: TextStyle(
                                          color: style.textSecondary,
                                          fontSize: 13)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dc, false),
                                      child: Text('取消',
                                          style: TextStyle(
                                              color: style.textSecondary)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(dc, true),
                                      child: Text('清空',
                                          style: TextStyle(
                                              color: style.accent)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await ref
                                    .read(audioHandlerProvider)
                                    .clearQueue();
                              }
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              snap.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Text('队列加载失败',
                        style: TextStyle(color: style.textSecondary))),
                data: (q) {
                  if (q.songs.isEmpty) {
                    return Expanded(
                      child: EmptyState(
                          icon: Icons.queue_music,
                          title: '播放队列为空',
                          hint: '去发现页挑个歌单开始听吧'),
                    );
                  }
                  return Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: q.songs.length,
                      separatorBuilder: (_, __) => Divider(
                          color: style.textSecondary.withValues(alpha: 0.12),
                          height: 1,
                          indent: 70),
                      itemBuilder: (c, i) {
                        final s = q.songs[i];
                        final current = i == q.index;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          leading: CoverImage(
                              url: s.coverUrl,
                              size: 44,
                              radius: BorderRadius.circular(8)),
                          title: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: current
                                      ? style.accent
                                      : style.textPrimary,
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                          subtitle: Text(s.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 12)),
                          trailing: current
                              ? Icon(Icons.graphic_eq,
                                  color: style.accent, size: 20)
                              : IconButton(
                                  icon: Icon(Icons.close,
                                      size: 18,
                                      color: style.textSecondary
                                          .withValues(alpha: 0.6)),
                                  onPressed: () => ref
                                      .read(audioHandlerProvider)
                                      .removeFromQueue(i),
                                ),
                          onTap: current
                              ? null
                              : () async {
                                  try {
                                    await ref
                                        .read(audioHandlerProvider)
                                        .skipToIndex(i);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(e.toString())));
                                    }
                                  }
                                },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
