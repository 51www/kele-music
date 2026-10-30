import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/listen_stats.dart';
import '../../providers.dart';
import 'listen_summary_cards.dart';

/// 收听统计：趋势图表 + 今日/本周/本月卡片 + 每日明细。
///
/// 口径与「我的」页三张卡完全一致（同一份 [listenStatsProvider] 快照），
/// 图表额外提供一个时间窗切换（近 7 天 / 近 30 天），只影响图表与上期对比，
/// 不影响卡片（卡片固定为今日 / 本周 / 本月）。
class ListenStatsScreen extends ConsumerStatefulWidget {
  const ListenStatsScreen({super.key});

  @override
  ConsumerState<ListenStatsScreen> createState() => _ListenStatsScreenState();
}

class _ListenStatsScreenState extends ConsumerState<ListenStatsScreen> {
  /// 图表时间窗（天）。7 = 看节奏，30 = 看习惯。
  int _range = 7;

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final stats = ref.watch(listenStatsProvider);
    final points = stats.recentDays(_range);
    final prevPoints = stats.recentDays(_range * 2).take(_range).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: Column(
              children: [
                _TopBar(style: style, title: '收听统计'),
                Expanded(
                  child: ListView(
                    padding: sp.listPadding,
                    children: [
                      // 图表：本段最大的视觉块，先给结论（总量）再给过程（逐日）。
                      _ChartCard(
                        style: style,
                        range: _range,
                        points: points,
                        prevPoints: prevPoints,
                        onRangeChanged: (v) => setState(() => _range = v),
                      ),
                      AppSection(
                        title: '播放概览',
                        child: const ListenSummaryCards(),
                      ),
                      AppSection(
                        title: '每日明细',
                        child: _DailyDetailCard(
                          style: style,
                          points: stats.recordedDays(30),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: sp.section),
                        child: Column(
                          children: [
                            if (stats.totalSeconds > 0)
                              Text(
                                '累计收听 ${listenMinutes(stats.totalSeconds)} 分钟 · 记录 ${stats.activeDays} 天',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: style.textSecondary
                                      .withValues(alpha: 0.85),
                                  fontSize: 11,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              '收听数据仅保存在本机，不上传服务器。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    style.textSecondary.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// 二级页顶栏：返回 + 居中标题（与「最近播放」保持同一版式）。
class _TopBar extends StatelessWidget {
  final AppStyle style;
  final String title;
  const _TopBar({required this.style, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: style.textPrimary, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go('/profile'),
        ),
        const Spacer(),
        Text(title,
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        // 与左侧返回键等宽的占位，保证标题在视觉正中。
        const SizedBox(width: 48),
      ],
    );
  }
}

/// 趋势卡片：时间窗切换 + 总量 + 逐日柱状图。
class _ChartCard extends StatelessWidget {
  final AppStyle style;
  final int range;
  final List<DayPoint> points;
  final List<DayPoint> prevPoints;
  final ValueChanged<int> onRangeChanged;

  const _ChartCard({
    required this.style,
    required this.range,
    required this.points,
    required this.prevPoints,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final total = _sum(points);
    final prevTotal = _sum(prevPoints);
    final minutes = listenMinutes(total);
    final caption = total == 0
        ? '播放歌曲后这里会出现你的聆听曲线'
        : [
            '日均 ${listenMinutes(total ~/ math.max(1, points.length))} 分钟',
            if (prevTotal > 0) _deltaText(total, prevTotal),
          ].join(' · ');

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('收听趋势',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2)),
              ),
              _RangeSwitch(
                  style: style, value: range, onChanged: onRangeChanged),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$minutes',
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('分钟',
                    style: TextStyle(
                        color: style.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('近 $range 天',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: style.textSecondary.withValues(alpha: 0.75),
                          fontSize: 11)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: style.textSecondary.withValues(alpha: 0.9),
                  fontSize: 11)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 168,
            child: total == 0
                ? _EmptyChart(style: style, range: range)
                : _ListenBarChart(style: style, points: points, range: range),
          ),
        ],
      ),
    );
  }

  static int _sum(List<DayPoint> p) =>
      p.fold(0, (sum, e) => sum + e.seconds);

  /// 与上一个同长度时间窗的对比（只在上一期有数据时展示，避免出现 +∞）。
  static String _deltaText(int total, int prevTotal) {
    final pct = ((total - prevTotal) / prevTotal * 100).round();
    if (pct == 0) return '与上期持平';
    return pct > 0 ? '较上期 +$pct%' : '较上期 $pct%';
  }
}

/// 7 天 / 30 天切换：两枚小药丸，选中项用 accent 描边 + 极浅填充。
class _RangeSwitch extends StatelessWidget {
  final AppStyle style;
  final int value;
  final ValueChanged<int> onChanged;
  const _RangeSwitch(
      {required this.style, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int v) {
      final selected = value == v;
      return GestureDetector(
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? style.accent.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected
                    ? style.accent.withValues(alpha: 0.7)
                    : style.surfaceBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? style.accent : style.textSecondary,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
    }

    return Row(
      children: [
        chip('7 天', 7),
        const SizedBox(width: AppSpacing.xs),
        chip('30 天', 30),
      ],
    );
  }
}

/// 逐日柱状图。
///
/// 柱体用「accent → 透明」的竖向渐变，高度按当期最大值归一；今天的柱子实心
/// 高亮并带数值标签，其余柱子降低不透明度——一眼能定位「今天」在哪根。
/// 入场用一次整体生长动画（系统开启「减弱动效」时直接呈现终态）。
class _ListenBarChart extends StatelessWidget {
  final AppStyle style;
  final List<DayPoint> points;
  final int range;
  const _ListenBarChart(
      {required this.style, required this.points, required this.range});

  @override
  Widget build(BuildContext context) {
    final maxSeconds =
        points.fold(0, (m, p) => math.max(m, p.seconds)).toDouble();
    // 系统开启「减弱动效」时不播放入场生长，直接呈现终态。
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final todayKey = dayKey(DateTime.now());
    final dense = range > 7;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: animate ? const Duration(milliseconds: 620) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) {
                  // 7 天模式柱顶带数值标签，预留 14px；30 天模式不标数值。
                  final labelSpace = dense ? 0.0 : 14.0;
                  final maxBar = math.max(6.0, cons.maxHeight - labelSpace);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in points)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: dense ? 1 : 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (!dense && p.seconds > 0)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      '${listenMinutes(p.seconds)}',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: dayKey(p.date) == todayKey
                                            ? style.accent
                                            : style.textSecondary,
                                        fontSize: 9.5,
                                        height: 1,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ),
                                _Bar(
                                  style: style,
                                  height: p.seconds == 0
                                      ? 0
                                      : math.max(
                                          4,
                                          (p.seconds / maxSeconds) *
                                              maxBar *
                                              t),
                                  today: dayKey(p.date) == todayKey,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 1, color: style.surfaceBorder),
            const SizedBox(height: 5),
            SizedBox(
              height: 14,
              // 30 天模式每根柱子只有 10px 宽，塞不下日期：横轴只标首尾，
              // 逐日 5 列标签留给 7 天模式。
              child: dense
                  ? Row(
                      children: [
                        Text(
                            '${points.first.date.month}/${points.first.date.day}',
                            style: TextStyle(
                                color: style.textSecondary
                                    .withValues(alpha: 0.8),
                                fontSize: 9.5)),
                        const Spacer(),
                        Text('今天',
                            style: TextStyle(
                                color: style.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    )
                  : Row(
                      children: [
                        for (final p in points)
                          Expanded(
                            child: Text(
                              weekdayLabel(p.date),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: dayKey(p.date) == todayKey
                                    ? style.accent
                                    : style.textSecondary
                                        .withValues(alpha: 0.8),
                                fontSize: 9.5,
                                fontWeight: dayKey(p.date) == todayKey
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final AppStyle style;
  final double height;
  final bool today;
  const _Bar({required this.style, required this.height, required this.today});

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink(); // 当天无收听：不画柱子。
    final radius = BorderRadius.vertical(
        top: Radius.circular(height > 6 ? 3 : 1.5),
        bottom: const Radius.circular(1.5));
    if (today) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              style.accent,
              style.accent.withValues(alpha: 0.55),
            ],
          ),
        ),
      );
    }
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            style.accent.withValues(alpha: 0.5),
            style.accent.withValues(alpha: 0.16),
          ],
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final AppStyle style;
  final int range;
  const _EmptyChart({required this.style, required this.range});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded,
              size: 34, color: style.textSecondary.withValues(alpha: 0.55)),
          const SizedBox(height: AppSpacing.sm),
          Text('近 $range 天还没有收听记录',
              style: TextStyle(color: style.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text('播放歌曲后开始累计，时长单位为分钟',
              style: TextStyle(
                  color: style.textSecondary.withValues(alpha: 0.7),
                  fontSize: 10.5)),
        ],
      ),
    );
  }
}

/// 每日明细：一行一天，最新在前。
class _DailyDetailCard extends StatelessWidget {
  final AppStyle style;
  final List<DayPoint> points;
  const _DailyDetailCard({required this.style, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        // 空态内容窄，不撑满会缩成一小块；显式拉满，与有数据时的列表同宽。
        width: double.infinity,
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Column(
            children: [
              Icon(Icons.event_note_outlined,
                  size: 30,
                  color: style.textSecondary.withValues(alpha: 0.6)),
              const SizedBox(height: AppSpacing.sm),
              Text('还没有每日记录',
                  style: TextStyle(color: style.textPrimary, fontSize: 13)),
              const SizedBox(height: 2),
              Text('有收听的那一天才会出现在这里',
                  style: TextStyle(color: style.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      );
    }
    final maxSeconds = points.fold(0, (m, p) => math.max(m, p.seconds));

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: style.textSecondary.withValues(alpha: 0.12)),
            _DayRow(
              style: style,
              point: points[i],
              ratio: maxSeconds == 0 ? 0 : points[i].seconds / maxSeconds,
            ),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final AppStyle style;
  final DayPoint point;
  /// 相对列表最大值的比例，用于行内迷你条的长度。
  final double ratio;
  const _DayRow(
      {required this.style, required this.point, required this.ratio});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = dayKey(point.date) == dayKey(now);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md - 1),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayLabel(point.date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isToday ? style.accent : style.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(weekdayLabel(point.date),
                    maxLines: 1,
                    style:
                        TextStyle(color: style.textSecondary, fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 4,
                color: style.textSecondary.withValues(alpha: 0.14),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.02, 1.0).toDouble(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: style.accent.withValues(alpha: isToday ? 1 : 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 62,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${listenMinutes(point.seconds)}',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text('分钟',
                      style: TextStyle(
                          color: style.textSecondary, fontSize: 9.5)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 46,
            child: Text('${point.songCount} 首',
                textAlign: TextAlign.right,
                style: TextStyle(color: style.textSecondary, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}
