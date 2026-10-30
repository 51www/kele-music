import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// 第三方账号接入点。
///
/// 当前只接了网易云音乐；新增平台时在 [kThirdPartyAccounts] 追加一项，并在
/// [AccountScreen] 里接上该平台的绑定 / 解绑流程（绑定态通常来自各自的
/// 授权仓库，解绑即清理对应凭证），列表与版式会自动跟着变，不用改页面结构。
class ThirdPartyAccount {
  final String id;
  final String name;
  final IconData icon;

  const ThirdPartyAccount(
      {required this.id, required this.name, required this.icon});
}

const List<ThirdPartyAccount> kThirdPartyAccounts = [
  ThirdPartyAccount(
      id: 'netease', name: '网易云音乐', icon: Icons.music_note_rounded),
];

/// 账号管理：第三方账号的绑定与解绑。
///
/// 从「我的」页迁入（原先是页面顶部的用户资料卡 + 退出登录），入口收进
/// 「设置 → 账号管理」——登录只是同步云端歌单的前置动作，不该占据首屏。
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final authed =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: Column(
              children: [
                _TopBar(style: style, title: '账号管理'),
                Expanded(
                  child: ListView(
                    padding: sp.listPadding,
                    children: [
                      Padding(
                        padding:
                            EdgeInsets.only(bottom: sp.block, left: 2),
                        child: Text('第三方账号',
                            style: TextStyle(
                                color: style.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                      GlassPanel(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < kThirdPartyAccounts.length;
                                i++) ...[
                              if (i > 0)
                                Divider(
                                    height: 1,
                                    indent: 14,
                                    endIndent: 14,
                                    color: style.textSecondary
                                        .withValues(alpha: 0.15)),
                              _ThirdPartyTile(
                                style: style,
                                account: kThirdPartyAccounts[i],
                                bound: authed,
                                nickname: profile?.nickname ?? '',
                                avatarUrl: profile?.avatarUrl ?? '',
                                onBind: () =>
                                    context.push('/login?next=/settings/account'),
                                onUnbind: () => _confirmUnbind(context, ref),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: sp.block, left: 2, right: 2),
                        child: Text(
                          '目前支持绑定网易云音乐；后续接入其他平台后，会以同样的方式出现在这里。',
                          style: TextStyle(
                              color: style.textSecondary.withValues(alpha: 0.8),
                              fontSize: 11,
                              height: 1.5),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: sp.section, left: 2, right: 2),
                        child: Text(
                          '绑定用于同步云端歌单、收藏与每日推荐；解绑后这些内容在本机不再展示，已缓存的收听统计不受影响。',
                          style: TextStyle(
                              color: style.textSecondary.withValues(alpha: 0.7),
                              fontSize: 11,
                              height: 1.6),
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

  Future<void> _confirmUnbind(BuildContext context, WidgetRef ref) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 6),
          side: BorderSide(color: style.surfaceBorder),
        ),
        title: Text('解除网易云音乐绑定？',
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w700)),
        content: Text('解绑后云端歌单、收藏与每日推荐将不再显示，可随时重新绑定。',
            style: TextStyle(color: style.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child:
                  Text('取消', style: TextStyle(color: style.textSecondary))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: style.accent,
                  foregroundColor: style.bgBottom),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('解除绑定', style: TextStyle(fontSize: 13))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authStateProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('已解除网易云音乐绑定'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600)));
    }
  }
}

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
          onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
        ),
        const Spacer(),
        Text(title,
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

/// 单个第三方账号行：绑定态展示头像与昵称，右侧是绑定 / 解绑动作。
class _ThirdPartyTile extends StatelessWidget {
  final AppStyle style;
  final ThirdPartyAccount account;
  final bool bound;
  final String nickname;
  final String avatarUrl;
  final VoidCallback onBind;
  final VoidCallback onUnbind;

  const _ThirdPartyTile({
    required this.style,
    required this.account,
    required this.bound,
    required this.nickname,
    required this.avatarUrl,
    required this.onBind,
    required this.onUnbind,
  });

  @override
  Widget build(BuildContext context) {
    final name = nickname.isEmpty ? '已绑定账号' : nickname;
    return InkWell(
      borderRadius: BorderRadius.circular(style.uiRadius),
      onTap: bound ? null : onBind,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _Leading(style: style, bound: bound, avatarUrl: avatarUrl, icon: account.icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bound ? '$name · ${account.name}' : account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    bound ? '已绑定，云端歌单与收藏已同步' : '未绑定，绑定后可同步歌单与收藏',
                    maxLines: 2,
                    style: TextStyle(
                        color: style.textSecondary, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ActionPill(
              style: style,
              label: bound ? '解绑' : '绑定',
              primary: !bound,
              onTap: bound ? onUnbind : onBind,
            ),
          ],
        ),
      ),
    );
  }
}

/// 左侧图标位：已绑定显示头像（描 accent 圈），未绑定显示平台图标。
class _Leading extends StatelessWidget {
  final AppStyle style;
  final bool bound;
  final String avatarUrl;
  final IconData icon;
  const _Leading({
    required this.style,
    required this.bound,
    required this.avatarUrl,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final size = 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: style.surface,
        border: Border.all(
            color: bound
                ? style.accent.withValues(alpha: 0.8)
                : style.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: bound && avatarUrl.isNotEmpty
          ? SafeNetworkImage(url: avatarUrl, width: size, height: size)
          : Icon(icon,
              size: 20,
              color: bound ? style.accent : style.textSecondary),
    );
  }
}

/// 行尾小药丸按钮：绑定用 accent 实心，解绑用描边（破坏性动作不抢视觉）。
class _ActionPill extends StatelessWidget {
  final AppStyle style;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _ActionPill({
    required this.style,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? style.accent : null,
          borderRadius: BorderRadius.circular(20),
          border: primary
              ? null
              : Border.all(color: style.surfaceBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? style.bgBottom : style.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
