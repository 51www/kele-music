import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
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
  String? _signMsg;
  bool _signing = false;

  Future<void> _sign() async {
    if (_signing) return;
    setState(() => _signing = true);
    try {
      await ref.read(apiProvider).dailySignin();
      setState(() => _signMsg = '签到成功，经验 +1');
    } catch (e) {
      setState(() =>
          _signMsg = e is ApiException ? e.userMessage : e.toString());
    }
    setState(() => _signing = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final authed =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('我的',
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              const SizedBox(height: 16),
              // 用户资料卡：已登录显示昵称/头像，未登录引导登录。
              profile.maybeWhen(
                data: (p) => _ProfileCard(style: style, profile: p, authed: authed),
                orElse: () => GlassPanel(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white12,
                        child: Icon(Icons.person, color: Colors.white24),
                      ),
                      const SizedBox(width: 14),
                      Text('加载中…',
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 15)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 每日签到。
              GlassPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        size: 22, color: style.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('每日签到',
                              style: TextStyle(
                                  color: style.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          if (_signMsg != null)
                            Text(_signMsg!,
                                style: TextStyle(
                                    color: style.textSecondary,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: (_signing || !authed) ? null : _sign,
                      style: FilledButton.styleFrom(
                        backgroundColor: style.accent,
                        foregroundColor: style.bgBottom,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: Text(_signing ? '签到中…' : '签到',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // 功能入口。
              GlassPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _EntryTile(
                      style: style,
                      icon: Icons.library_music_outlined,
                      title: '音乐库',
                      subtitle: '收藏的歌曲与歌单',
                      onTap: () => context.go('/library'),
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
              if (authed) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(authStateProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: style.surfaceBorder),
                    foregroundColor: style.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('退出登录'),
                ),
              ],
            ],
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
    return GlassPanel(
      child: InkWell(
        borderRadius: BorderRadius.circular(style.uiRadius),
        onTap: empty ? () => context.go('/login') : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              empty
                  ? CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white12,
                      child: Icon(Icons.person,
                          color: style.textSecondary),
                    )
                  : CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white12,
                      backgroundImage:
                          profile.avatarUrl.isEmpty
                              ? null
                              : NetworkImage(profile.avatarUrl
                                  .replaceFirst('http://', 'https://')),
                      child: profile.avatarUrl.isEmpty
                          ? Icon(Icons.person, color: style.textSecondary)
                          : null,
                    ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 3),
                    Text(
                      empty ? '点击登录，同步你的音乐世界' : '欢迎回来，继续你的音乐时光',
                      style:
                          TextStyle(color: style.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (empty)
                Icon(Icons.chevron_right, color: style.textSecondary),
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
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(style.uiRadius),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 22, color: style.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
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
