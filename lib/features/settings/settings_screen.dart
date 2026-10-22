import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/app_config.dart';
import '../../providers.dart';

/// 设置页：分组卡片布局。
/// 播放（音质档位）/ 界面（主题、语言）/ 存储与隐私（本地记录清理）/ 后端服务。
/// 全部修改即时持久化：音质经 playbackSettingsProvider 生效于下一次音源解析，
/// baseUrl 经 AppConfig 单例立即生效于后续请求。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final settings = ref.watch(playbackSettingsProvider);
    final settingsNotifier = ref.read(playbackSettingsProvider.notifier);
    final styleIdx = ref.watch(styleIndexProvider);
    final styleNotifier = ref.read(styleIndexProvider.notifier);

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
                Text('设置',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),

                // ── 播放 ─────────────────────────────────────────────
                _settingsBlock(
                  context,
                  style,
                  title: '播放',
                  icon: Icons.graphic_eq_rounded,
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // 在线音质：直接在行内展开档位条，改完即生效。
                        _QualityTile(
                          style: style,
                          title: '在线播放音质',
                          subtitle: '切换后下一次播放生效',
                          currentLevel: settings.playLevel,
                          onSelected: settingsNotifier.setPlayLevel,
                          showDivider: true,
                        ),
                        _QualityTile(
                          style: style,
                          title: '下载音质',
                          subtitle: '下载歌曲时使用的档位',
                          currentLevel: settings.downloadLevel,
                          onSelected: settingsNotifier.setDownloadLevel,
                          showDivider: true,
                        ),
                        // 播放页视觉：黑胶动效（默认）/ 经典静态，即时生效并持久化。
                        _VisualTile(
                          style: style,
                          current: settings.nowPlayingVisual,
                          onSelected: settingsNotifier.setNowPlayingVisual,
                        ),
                      ],
                    ),
                  ),
                ),
                // ── 界面 ─────────────────────────────────────────────
                _settingsBlock(
                  context,
                  style,
                  title: '界面',
                  icon: Icons.palette_outlined,
                  child: GlassPanel(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('主题风格',
                            style: TextStyle(
                                color: style.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        SizedBox(height: sp.block),
                        Wrap(
                          spacing: sp.inline,
                          runSpacing: sp.inline,
                          children: [
                            for (int i = 0; i < kStyles.length; i++)
                              ChoiceChip(
                                label: Text(kStyles[i].name),
                                selected: styleIdx == i,
                                selectedColor: style.accent,
                                backgroundColor: style.surface,
                                side: BorderSide(
                                    color: styleIdx == i
                                        ? style.accent
                                        : style.surfaceBorder),
                                labelStyle: TextStyle(
                                    color: styleIdx == i
                                        ? style.bgBottom
                                        : style.textPrimary,
                                    fontSize: 12.5),
                                onSelected: (_) => styleNotifier.set(i),
                              ),
                          ],
                        ),
                        const Divider(height: 24),
                        // 语言：真实 i18n 未接入，English 置灰诚实展示。
                        Row(
                          children: [
                            Icon(Icons.translate_rounded,
                                size: 19, color: style.textPrimary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('语言 / Language',
                                  style: TextStyle(
                                      color: style.textPrimary, fontSize: 14)),
                            ),
                            Text('简体中文',
                                style: TextStyle(
                                    color: style.textSecondary,
                                    fontSize: 12.5)),
                            const SizedBox(width: 6),
                            Text('English（即将支持）',
                                style: TextStyle(
                                    color: style.textSecondary
                                        .withValues(alpha: 0.5),
                                    fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ── 存储与隐私 ────────────────────────────────────────
                _settingsBlock(
                  context,
                  style,
                  title: '存储与隐私',
                  icon: Icons.shield_outlined,
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _ActionTile(
                          style: style,
                          icon: Icons.manage_search_rounded,
                          title: '清除搜索历史',
                          subtitle: '删除本机保存的搜索关键词',
                          confirm: '确定清除全部搜索历史？',
                          onTap: () => _clearSearchHistory(context, ref),
                          showDivider: true,
                        ),
                        _ActionTile(
                          style: style,
                          icon: Icons.history_rounded,
                          title: '清除播放历史',
                          subtitle: '删除本机保存的播放记录（最多 100 条）',
                          confirm: '确定清除全部播放历史？',
                          onTap: () => _clearHistory(context, ref),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── 后端服务 ─────────────────────────────────────────
                _settingsBlock(
                  context,
                  style,
                  title: '后端服务',
                  icon: Icons.dns_outlined,
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _EntryRow(
                          style: style,
                          title: 'API 地址',
                          value: AppConfig.instance.baseUrl,
                          subtitle: '当前实际生效，点击修改',
                          onTap: () => _editBaseUrl(context, ref),
                          showDivider: true,
                        ),
                        // 实际值 ≠ 内置默认时，提供一键回落。
                        if (AppConfig.instance.baseUrl != kBaseUrl)
                          _ActionTile(
                            style: style,
                            icon: Icons.restore_rounded,
                            title: '恢复默认地址',
                            subtitle: kBaseUrl,
                            confirm: '恢复默认后端地址？\n$kBaseUrl',
                            onTap: () => _resetBaseUrl(context, ref),
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

  /// 设置页的一个板块：小标题 + 内容面板。
  ///
  /// 板块上边距由本方法承担（`AppSpacing.section`），与 `AppSection` 同一约定：
  /// 间距挂在板块身上，父级列表不插空档，各板块间距因此永远一致。
  Widget _settingsBlock(
    BuildContext context,
    AppStyle style, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final sp = AppSpacing.of(context);
    return Padding(
      padding: sp.sectionPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(style, title, icon),
          SizedBox(height: sp.block),
          child,
        ],
      ),
    );
  }

  Widget _sectionTitle(AppStyle style, String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: style.accent),
        const SizedBox(width: AppSpacing.xxs),
        Text(text,
            style: TextStyle(
                color: style.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      ],
    );
  }

  Future<void> _clearSearchHistory(BuildContext context, WidgetRef ref) async {
    ref.read(searchHistoryProvider.notifier).clear();
    _toast(context, '已清除搜索历史');
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    ref.read(historyProvider.notifier).clear();
    _toast(context, '已清除播放历史');
  }

  Future<void> _resetBaseUrl(BuildContext context, WidgetRef ref) async {
    await AppConfig.resetBaseUrl();
    if (context.mounted) {
      _toast(context, '已恢复默认：${AppConfig.instance.baseUrl}');
      // 触发整页重建以隐藏「恢复默认」行。
      ref.invalidate(playbackSettingsProvider);
    }
  }

  /// baseUrl 编辑弹窗：输入校验（http/https 前缀）→ AppConfig.saveBaseUrl
  /// （更新单例当前会话立即生效 + SP 持久化下次启动生效）。
  Future<void> _editBaseUrl(BuildContext context, WidgetRef ref) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final ctrl = TextEditingController(text: AppConfig.instance.baseUrl);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 6),
          side: BorderSide(color: style.surfaceBorder),
        ),
        title: Text('修改 API 地址',
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保存后立即生效，并持久化到本机。',
                  style: TextStyle(color: style.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              TextFormField(
                controller: ctrl,
                style: TextStyle(color: style.textPrimary, fontSize: 13),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final u = v?.trim() ?? '';
                  if (u.isEmpty) return '地址不能为空';
                  if (!u.startsWith('http://') && !u.startsWith('https://')) {
                    return '需以 http:// 或 https:// 开头';
                  }
                  if (Uri.tryParse(u)?.host.isEmpty ?? true) return '地址格式不正确';
                  return null;
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: style.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(style.uiRadius)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('取消', style: TextStyle(color: style.textSecondary))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: style.accent,
                  foregroundColor: style.bgBottom),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('保存', style: TextStyle(fontSize: 13))),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      await AppConfig.saveBaseUrl(ctrl.text.trim());
      if (context.mounted) {
        // 同步到运行中的 API 客户端：否则当前会话仍走旧地址，要重启才生效。
        ref.read(apiProvider).setBaseUrl(AppConfig.instance.baseUrl);
        _toast(context, '已保存：${AppConfig.instance.baseUrl}');
        ref.invalidate(playbackSettingsProvider); // 刷新页面。
      }
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600)));
  }
}

/// 音质设置行：左侧标题/说明，右侧当前档位；点击展开档位选择弹层。
class _QualityTile extends StatelessWidget {
  final AppStyle style;
  final String title;
  final String subtitle;
  final String currentLevel;
  final ValueChanged<String> onSelected;
  final bool showDivider;
  const _QualityTile({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.currentLevel,
    required this.onSelected,
    this.showDivider = false,
  });

  String _labelOf(String level) {
    final i = kQualityLevels.indexOf(level);
    return i >= 0 ? kQualityLabels[i].$1 : level;
  }

  Future<void> _pick(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _QualitySheet(style: style, title: title, currentLevel: currentLevel),
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(style.uiRadius),
          onTap: () => _pick(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: style.accent.withValues(alpha: 0.5)),
                  ),
                  child: Text(_labelOf(currentLevel),
                      style: TextStyle(
                          color: style.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right, size: 18, color: style.textSecondary),
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

/// 音质档位选择弹层：单选列表，当前档位带 accent 勾选。
class _QualitySheet extends StatelessWidget {
  final AppStyle style;
  final String title;
  final String currentLevel;
  const _QualitySheet(
      {required this.style, required this.title, required this.currentLevel});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          // 半透明 surface 叠 55% 黑：低透明度主题（如柔焦）下压得住背景内容。
          color: Color.alphaBlend(style.surface, const Color(0x8C000000)),
          borderRadius: BorderRadius.circular(style.uiRadius + 8),
          border: Border.all(color: style.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
            for (final (i, level) in kQualityLevels.indexed)
              InkWell(
                borderRadius: BorderRadius.circular(style.uiRadius),
                onTap: () => Navigator.of(context).pop(level),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Text(kQualityLabels[i].$1,
                          style: TextStyle(
                              color: level == currentLevel
                                  ? style.accent
                                  : style.textPrimary,
                              fontSize: 14,
                              fontWeight: level == currentLevel
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                      const SizedBox(width: 10),
                      Text(kQualityLabels[i].$2,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 11.5)),
                      const Spacer(),
                      if (level == currentLevel)
                        Icon(Icons.check_rounded,
                            size: 18, color: style.accent),
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

/// 播放页视觉设置行：点击弹出模式选择弹层（黑胶动效 / 经典静态）。
class _VisualTile extends StatelessWidget {
  final AppStyle style;
  final String current;
  final ValueChanged<String> onSelected;
  const _VisualTile({
    required this.style,
    required this.current,
    required this.onSelected,
  });

  String _labelOf(String visual) {
    final i = kNowPlayingVisuals.indexOf(visual);
    return i >= 0 ? kNowPlayingVisualLabels[i].$1 : visual;
  }

  Future<void> _pick(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VisualSheet(style: style, current: current),
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(style.uiRadius),
      onTap: () => _pick(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('播放页视觉',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('唱片呈现与播放动效，返回播放页即可生效',
                      style: TextStyle(
                          color: style.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: style.accent.withValues(alpha: 0.5)),
              ),
              child: Text(_labelOf(current),
                  style: TextStyle(
                      color: style.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.chevron_right, size: 18, color: style.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 播放页视觉选择弹层：单选列表，当前模式带 accent 勾选。
class _VisualSheet extends StatelessWidget {
  final AppStyle style;
  final String current;
  const _VisualSheet({required this.style, required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          // 半透明 surface 叠 55% 黑：低透明度主题（如柔焦）下压得住背景内容。
          color: Color.alphaBlend(style.surface, const Color(0x8C000000)),
          borderRadius: BorderRadius.circular(style.uiRadius + 8),
          border: Border.all(color: style.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('播放页视觉',
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
            for (final (i, visual) in kNowPlayingVisuals.indexed)
              InkWell(
                borderRadius: BorderRadius.circular(style.uiRadius),
                onTap: () => Navigator.of(context).pop(visual),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Text(kNowPlayingVisualLabels[i].$1,
                          style: TextStyle(
                              color: visual == current
                                  ? style.accent
                                  : style.textPrimary,
                              fontSize: 14,
                              fontWeight: visual == current
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                      const SizedBox(width: 10),
                      Text(kNowPlayingVisualLabels[i].$2,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 11.5)),
                      const Spacer(),
                      if (visual == current)
                        Icon(Icons.check_rounded,
                            size: 18, color: style.accent),
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

/// 通用设置行：图标 + 标题/副标题 + 当前值 + chevron。
class _EntryRow extends StatelessWidget {
  final AppStyle style;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showDivider;
  const _EntryRow({
    required this.style,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(style.uiRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 11.5)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: style.textSecondary, fontSize: 12)),
                ),
                Icon(Icons.chevron_right, size: 18, color: style.textSecondary),
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

/// 确认型动作行：点击弹确认框，确认后执行。
class _ActionTile extends StatelessWidget {
  final AppStyle style;
  final IconData icon;
  final String title;
  final String subtitle;
  final String confirm;
  final VoidCallback onTap;
  final bool showDivider;
  const _ActionTile({
    required this.style,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirm,
    required this.onTap,
    this.showDivider = false,
  });

  Future<void> _run(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 6),
          side: BorderSide(color: style.surfaceBorder),
        ),
        title: Text(title,
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w700)),
        content: Text(confirm,
            style: TextStyle(color: style.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('取消', style: TextStyle(color: style.textSecondary))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: style.accent,
                  foregroundColor: style.bgBottom),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定', style: TextStyle(fontSize: 13))),
        ],
      ),
    );
    if (ok == true) onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(style.uiRadius),
          onTap: () => _run(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: style.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
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
