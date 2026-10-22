import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final authed =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;
    final profile = ref.watch(userProfileProvider);

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
                // 用户资料卡：已登录显示昵称/头像，未登录引导登录。
                AppSection(
                  child: profile.maybeWhen(
                    data: (p) =>
                        _ProfileCard(style: style, profile: p, authed: authed),
                    orElse: () => GlassPanel(
                      padding: EdgeInsets.all(sp.gutter),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.white12,
                            child: Icon(Icons.person, color: Colors.white24),
                          ),
                          SizedBox(width: sp.block),
                          Text('加载中…',
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
                // 功能入口。
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
                          icon: Icons.settings_outlined,
                          title: '设置',
                          subtitle: '界面风格切换',
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (authed)
                  AppSection(
                    child: _GlassActionButton(
                      style: style,
                      icon: Icons.logout_rounded,
                      label: '退出登录',
                      onTap: () async {
                        await ref.read(authStateProvider.notifier).logout();
                        if (context.mounted) context.go('/login');
                      },
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

/// 用户资料卡。
class _ProfileCard extends StatelessWidget {
  final AppStyle style;
  final UserProfile profile;
  final bool authed;
  const _ProfileCard(
      {required this.style, required this.profile, required this.authed});

  @override
  Widget build(BuildContext context) {
    final empty = !authed || profile.isEmpty;
    final sp = AppSpacing.of(context);
    return GlassPanel(
      child: InkWell(
        borderRadius: BorderRadius.circular(style.uiRadius),
        onTap: empty ? () => context.go('/login') : null,
        child: Padding(
          padding: EdgeInsets.all(sp.gutter),
          child: Row(
            children: [
              empty
                  ? CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white12,
                      child: Icon(Icons.person, color: style.textSecondary),
                    )
                  : CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white12,
                      backgroundImage: profile.avatarUrl.isEmpty
                          ? null
                          : NetworkImage(profile.avatarUrl
                              .replaceFirst('http://', 'https://')),
                      child: profile.avatarUrl.isEmpty
                          ? Icon(Icons.person, color: style.textSecondary)
                          : null,
                    ),
              SizedBox(width: sp.block),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empty ? '未登录' : profile.nickname,
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      empty ? '点击登录，同步你的音乐世界' : '欢迎回来，继续你的音乐时光',
                      style:
                          TextStyle(color: style.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (empty) Icon(Icons.chevron_right, color: style.textSecondary),
            ],
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

/// 玻璃质感操作按钮（退出登录）。
///
/// 与页面其它玻璃卡片共用同一套 token：半透明底 `surface` + hairline 描边
/// `surfaceBorder` + `uiRadius` 圆角；文案居中、字重与入口行标题对齐。
/// 不用裸 Material 按钮，避免默认 M3 圆角与收紧的宽度在玻璃版面里显得突兀。
class _GlassActionButton extends StatefulWidget {
  final AppStyle style;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlassActionButton({
    required this.style,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final radius = BorderRadius.circular(style.uiRadius);
    // 悬停：描边更亮、底色略微提亮；按下：底色压暗。
    // 用 alphaBlend 而不是直接改 alpha，这样三套风格（深色/浅色底）方向一致。
    final fill = _pressed
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.10), style.surface)
        : _hover
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), style.surface)
            : style.surface;
    final border = _hover
        ? style.surfaceBorder.withValues(alpha: 0.9)
        : style.surfaceBorder;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Container(
          width: double.infinity,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: style.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.label,
                style: TextStyle(
                    color: style.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
