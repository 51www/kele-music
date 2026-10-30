import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../stats/listen_summary_cards.dart';

/// 「我的」页：收听概览 + 二级入口。
///
/// 页面焦点已从「账号」转为「收听」：顶部不再放登录 / 用户资料卡，改为今日 /
/// 本周 / 本月三张收听卡片（数据来自本地收听统计）；登录与账号绑定收进
/// 「设置 → 账号管理」，未登录时页面同样完整可用，不再用登录入口打断浏览。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: ListView(
              padding: sp.listPadding,
              children: [
                Text('我的',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
                // 收听概览：三张卡片与「收听统计」页共用同一份数据与版式。
                const AppSection(child: ListenSummaryCards()),
                // 功能入口：收听统计紧邻设置上方，形成「看数据 → 调设置」的动线。
                AppSection(
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _EntryTile(
                          style: style,
                          icon: Icons.history,
                          title: '最近播放',
                          subtitle: '本地历史记录，最多 100 条',
                          onTap: () => context.push('/history'),
                          showDivider: true,
                        ),
                        _EntryTile(
                          style: style,
                          icon: Icons.insights_rounded,
                          title: '收听统计',
                          subtitle: '趋势图表 · 周月汇总 · 每日明细',
                          onTap: () => context.push('/listen-stats'),
                          showDivider: true,
                        ),
                        _EntryTile(
                          style: style,
                          icon: Icons.settings_outlined,
                          title: '设置',
                          subtitle: '界面风格、音质与账号管理',
                          onTap: () => context.push('/settings'),
                        ),
                      ],
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

/// 功能入口行。
class _EntryTile extends StatelessWidget {
  final AppStyle style;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;
  const _EntryTile({
    required this.style,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final sp = AppSpacing.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(style.uiRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 22, color: style.textPrimary),
                SizedBox(width: sp.block),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(subtitle,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: style.textSecondary),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: style.textSecondary.withValues(alpha: 0.15)),
      ],
    );
  }
}
