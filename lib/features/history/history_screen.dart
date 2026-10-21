import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../player/play_utils.dart' as play;
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 最近播放：本地历史记录（SharedPreferences 持久化，最多 100 条）。
/// 点击任意一首即以整个历史为队列播放；右上角可一键清空（带确认）。
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final songs = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 顶栏：返回 + 标题 + 清空。
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new,
                        color: style.textPrimary, size: 20),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Text('最近播放',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: songs.isEmpty
                            ? style.textSecondary.withValues(alpha: 0.35)
                            : style.textSecondary,
                        size: 21),
                    tooltip: '清空历史',
                    onPressed:
                        songs.isEmpty ? null : () => _confirmClear(context, ref),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${songs.length} 首歌曲',
                      style: TextStyle(
                          color: style.textSecondary, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: songs.isEmpty
                    ? EmptyState(
                        icon: Icons.history,
                        title: '还没有播放记录',
                        hint: '播放过的歌曲会自动出现在这里',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: songs.length,
                        itemBuilder: (c, i) {
                          final s = songs[i];
                          return SongTile(
                            song: s,
                            onTap: () => _play(context, ref, i),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref, int index) async {
    // 立即跳播放页，起播失败由 playAndOpen 统一轻提示。
    await play.playAndOpen(
        ref, context, List<Song>.from(ref.read(historyProvider)), index);
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.read(styleIndexProvider)];
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: style.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text('清空播放历史？',
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: Text('本地记录的最近播放将被全部删除。',
            style: TextStyle(color: style.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text('取消',
                style: TextStyle(color: style.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: style.accent,
              foregroundColor: style.bgBottom,
            ),
            onPressed: () {
              ref.read(historyProvider.notifier).clear();
              Navigator.of(dctx).pop();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
