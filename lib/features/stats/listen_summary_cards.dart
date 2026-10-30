import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/listen_stats.dart';
import '../../providers.dart';

/// 「今日 / 本周 / 本月」三张收听卡片：我的页与收听统计页共用一套版式，
/// 保证两处口径与观感一致（同一份 provider 快照，不各自算一遍）。
///
/// 版式约定：
/// - 三列等宽、卡内留白一致，数字用等宽数字（tabularFigures）避免逐秒跳动时
///   宽度抖动；
/// - 数字主视觉 22pt、单位「分钟」缩到 10pt 贴基线右侧，读起来是「47 分钟」
///   一个词组，而不是两个独立元素；
/// - 底部一行灰字承担「与上期对比 / 日均 / 有记录天数」这类解释性信息，
///   让三张卡各自有信息量，而不是三块只有数字的色块。
class ListenSummaryCards extends ConsumerWidget {
  const ListenSummaryCards({super.key, this.padding});

  /// 卡片之间的间距，默认取当前断点的 `AppSpacing.inline`。
  final double? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final stats = ref.watch(listenStatsProvider);
    final gap = padding ?? AppSpacing.of(context).inline;

    // IntrinsicHeight 提供高度上界，三张卡才能靠 stretch 等高；
    // 直接 stretch 会在 ListView 的无界高度下撑成无限高（后续内容被顶出可视区）。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              style: style,
              label: '今日播放',
              seconds: stats.todaySeconds,
              caption: _todayCaption(stats),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _StatCard(
              style: style,
              label: '本周播放',
              seconds: stats.weekSeconds,
              caption: stats.weekSeconds == 0
                  ? '本周还没听'
                  : '日均 ${listenMinutes(stats.weekDailyAverageSeconds)} 分钟',
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _StatCard(
              style: style,
              label: '本月播放',
              seconds: stats.monthSeconds,
              caption: stats.monthSeconds == 0
                  ? '本月还没听'
                  : '${stats.monthActiveDays} 天有记录',
            ),
          ),
        ],
      ),
    );
  }

  /// 今日卡片底部：优先给「较昨天」的增减，昨天无记录时退回展示昨天的量。
  String _todayCaption(ListenStats stats) {
    final today = listenMinutes(stats.todaySeconds);
    final yesterday = listenMinutes(stats.yesterdaySeconds);
    if (stats.yesterdaySeconds == 0) {
      return stats.todaySeconds == 0 ? '还没有记录' : '今天开始记录';
    }
    final delta = today - yesterday;
    if (delta == 0) return '与昨天持平';
    return delta > 0 ? '较昨天 +$delta' : '较昨天 $delta';
  }
}

class _StatCard extends StatelessWidget {
  final AppStyle style;
  final String label;
  final int seconds;
  final String caption;
  const _StatCard({
    required this.style,
    required this.label,
    required this.seconds,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = listenMinutes(seconds);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md - 1, AppSpacing.md, AppSpacing.md - 1, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 数字会随播放逐分钟增长：定高 + 只缩不拉，卡片高度始终不乱跳。
          SizedBox(
            height: 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$minutes',
                    style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 23,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1.5),
                    child: Text(
                      '分钟',
                      style: TextStyle(
                        color: style.textSecondary,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              caption,
              maxLines: 1,
              style: TextStyle(
                color: style.textSecondary.withValues(alpha: 0.85),
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
