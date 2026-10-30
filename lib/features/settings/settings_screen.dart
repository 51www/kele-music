import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/styles.dart';
import '../../core/updater.dart';
import '../../core/widgets.dart';
import '../../data/app_config.dart';
import '../../providers.dart';

/// 设置页：分组卡片布局。
/// 播放（音质档位）/ 界面（主题、语言）/ 存储与隐私（本地记录清理）/ 后端服务 / 关于（版本号）。
/// 全部修改即时持久化：音质经 playbackSettingsProvider 生效于下一次音源解析，
/// baseUrl 经 AppConfig 单例立即生效于后续请求。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// 版本信息只读一次并缓存：主题切换等页面重建不重复走平台通道。
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

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
                // ── 关于 ───────────────────────────────────────────────
                // 版本号取自构建产物内嵌信息（package_info_plus），与发布包始终一致；
                // 点击复制，便于与 GitHub 最新发布比对是否需要更新。
                _settingsBlock(
                  context,
                  style,
                  title: '关于',
                  icon: Icons.info_outline_rounded,
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snap) {
                        final v = snap.data;
                        final label = v == null || v.version.isEmpty
                            ? '—'
                            : 'v${v.version}'
                                '${v.buildNumber.isEmpty ? '' : '（build ${v.buildNumber}）'}';
                        return Column(
                          children: [
                            InkWell(
                              borderRadius:
                                  BorderRadius.circular(style.uiRadius),
                              onTap: () => _copyVersion(context, label),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('当前版本',
                                              style: TextStyle(
                                                  color: style.textPrimary,
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text('点击复制版本号；下方可检查更新',
                                              style: TextStyle(
                                                  color: style.textSecondary,
                                                  fontSize: 11.5)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: style.textSecondary,
                                              fontSize: 12,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures()
                                              ])),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Divider(
                                height: 1,
                                indent: 14,
                                endIndent: 14,
                                color: style.textSecondary
                                    .withValues(alpha: 0.15)),
                            // 检查更新：读同一份缓存的版本信息，Android 可应用内
                            // 下载安装，其余平台仅提示并跳转 GitHub Release 页。
                            _UpdateTile(
                                style: style, infoFuture: _packageInfo),
                          ],
                        );
                      },
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
      // 与 _editBaseUrl 对齐：同步到运行中的 Dio，否则仅配置值变了，
      // 当前会话请求仍走旧地址，要重启才生效。
      ref.read(apiProvider).setBaseUrl(AppConfig.instance.baseUrl);
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

  Future<void> _copyVersion(BuildContext context, String label) async {
    if (!label.startsWith('v')) return; // 版本尚未加载完成。
    await Clipboard.setData(ClipboardData(text: label));
    if (context.mounted) _toast(context, '已复制版本号：$label');
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

/// 「检查更新」行：点击请求 GitHub Releases 最新正式版。
///
/// 三态反馈：已是最新（Toast）/ 发现新版（弹窗，可下载可取消，永不强制）/
/// 检查失败（行内副标题 + Toast，可点击重试）。
class _UpdateTile extends StatefulWidget {
  final AppStyle style;
  final Future<PackageInfo> infoFuture; // 复用 SettingsScreen 缓存的版本信息
  const _UpdateTile({required this.style, required this.infoFuture});

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

enum _UpdatePhase { idle, checking, latest, found, failed }

class _UpdateTileState extends State<_UpdateTile> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  ReleaseInfo? _release;
  String _error = '';

  /// 已下载好的安装包（路径 + 版本）：同版本重复点「下载」直接复用，不重复下载。
  String? _apkPath;
  String? _apkTag;

  Future<void> _check() async {
    if (_phase == _UpdatePhase.checking) return;
    // 已确认有新版本时复用上次结果直接弹窗：网络抖动不丢更新，也省一次 API 调用。
    if (_phase == _UpdatePhase.found && _release != null) {
      await _present();
      return;
    }
    setState(() => _phase = _UpdatePhase.checking);
    try {
      final info = await widget.infoFuture;
      final release = await fetchLatestRelease();
      if (!mounted) return;
      if (release.tagName.isEmpty) {
        throw StateError('GitHub 未返回版本号');
      }
      final newer = isNewerVersion(release.tagName, info.version);
      if (_apkTag != release.tagName) _apkPath = null; // 换新版，旧包作废。
      setState(() {
        _release = release;
        _phase = newer ? _UpdatePhase.found : _UpdatePhase.latest;
      });
      if (newer) {
        await _present();
      } else {
        _toast('已是最新版本（v${info.version}）');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyUpdateError(e);
        _phase = _UpdatePhase.failed;
      });
      _toast('检查更新失败：$_error');
    }
  }

  Future<void> _present() async {
    final release = _release;
    if (release == null || !mounted) return;
    final cachedPath = _apkPath;
    await showDialog<void>(
      context: context,
      // 下载中途不给误触关闭；每个阶段都有显式按钮（取消 / 关闭）。
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(
        style: widget.style,
        release: release,
        apkPath: cachedPath,
        onApkReady: (path, tag) {
          _apkPath = path;
          _apkTag = tag;
        },
        onNotice: (msg) {
          if (mounted) _toast(msg);
        },
      ),
    );
    if (mounted) setState(() {}); // 弹窗关闭后刷新副标题。
  }

  String get _subtitle {
    switch (_phase) {
      case _UpdatePhase.idle:
        return '从 GitHub Releases 检查是否有新版本';
      case _UpdatePhase.checking:
        return '正在检查更新…';
      case _UpdatePhase.latest:
        return '当前已是最新版本';
      case _UpdatePhase.found:
        return '发现新版本 ${_release?.tagName ?? ''}，点击查看并下载';
      case _UpdatePhase.failed:
        return '检查失败：$_error（点击重试）';
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800)));
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return InkWell(
      borderRadius: BorderRadius.circular(style.uiRadius),
      onTap: _check,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded,
                size: 20, color: style.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('检查更新',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _phase == _UpdatePhase.found
                              ? style.accent
                              : style.textSecondary,
                          fontSize: 11.5)),
                ],
              ),
            ),
            if (_phase == _UpdatePhase.checking)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: style.accent)),
              )
            else ...[
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, size: 18, color: style.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 更新弹窗：版本说明与产物信息 →（Android）下载进度 → 完成后拉起系统安装。
/// 全程由用户主动点击推进，任何阶段都可取消，绝不强制。
class _UpdateDialog extends StatefulWidget {
  final AppStyle style;
  final ReleaseInfo release;
  final String? apkPath; // 上次已下载的安装包（同版本复用）
  final void Function(String path, String tag) onApkReady;
  final void Function(String message) onNotice;
  const _UpdateDialog({
    required this.style,
    required this.release,
    required this.onApkReady,
    required this.onNotice,
    this.apkPath,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateStage { info, downloading, ready }

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdateStage _stage = _UpdateStage.info;
  CancelToken? _token;
  int _received = 0;
  int _total = -1;
  String _error = '';
  String _notice = '';

  /// 当前下载来源（国内镜像域名 / GitHub 官方直连），用于进度页展示。
  String _source = '';
  bool _verified = false; // 是否通过 SHA-256 完整性校验。

  /// 本弹窗会话内已落盘的安装包；初始来自上一次会话（同版本复用）。
  late String? _apkPath = widget.apkPath;

  /// 弹窗里展示的产物：Android 取 APK，其余平台取对应平台包（仅供展示/跳转）。
  ReleaseAsset? get _asset => supportsInAppInstall
      ? pickAndroidApk(widget.release)
      : pickPlatformAsset(widget.release);

  @override
  void dispose() {
    _token?.cancel('dialog_closed'); // 关弹窗即中止后台下载。
    super.dispose();
  }

  Future<void> _startDownload() async {
    final asset = pickAndroidApk(widget.release);
    if (asset == null || asset.downloadUrl.isEmpty) {
      // 产物缺失（如发布时只挂了 aab）：退回 Release 页手动下载。
      setState(() => _error = '该版本未提供可下载的 APK 产物');
      await _openReleasePage();
      return;
    }
    // 同版本已下载过：跳过下载，直接进入安装环节。
    if (_apkPath != null && _apkPath!.isNotEmpty) {
      await _install();
      return;
    }
    setState(() {
      _stage = _UpdateStage.downloading;
      _received = 0;
      _total = -1;
      _error = '';
      _notice = '';
      _source = '';
      _verified = false;
    });
    _token = CancelToken();
    try {
      final res = await downloadApk(
        asset.downloadUrl,
        expectedSha256: asset.sha256,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
        onSource: (source) {
          if (!mounted) return;
          setState(() => _source = source); // 镜像失败切源时 UI 同步更新。
        },
        cancelToken: _token,
      );
      _apkPath = res.path;
      _source = res.source;
      _verified = res.verified;
      widget.onApkReady(res.path, widget.release.tagName);
      if (!mounted) return;
      await _install();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.type == DioExceptionType.cancel) {
        setState(() => _stage = _UpdateStage.info); // 用户主动取消，回到说明页。
        return;
      }
      setState(() {
        _stage = _UpdateStage.info;
        _error = '下载失败：${friendlyUpdateError(e)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.info;
        _error = '下载失败：${friendlyUpdateError(e)}';
      });
    }
  }

  /// 下载完成后的安装：Android 8+ 先确保「安装未知应用」授权，再拉起安装器。
  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    try {
      if (!await canRequestInstall()) {
        await openInstallPermissionSettings();
        if (!mounted) return;
        setState(() {
          _stage = _UpdateStage.ready;
          _notice =
              '安装包已下载。请在系统设置中允许本应用安装未知应用，返回后点击「立即安装」。';
        });
        return;
      }
      await installApk(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onNotice('已打开安装界面，请按系统提示完成安装');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.ready;
        _error = friendlyUpdateError(e);
        _notice = '安装包已就绪，可点击「立即安装」重试。';
      });
    }
  }

  Future<void> _openReleasePage() async {
    try {
      final ok = await launchUrl(
        Uri.parse(widget.release.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) setState(() => _error = '无法打开 Release 页面');
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开 Release 页面');
    }
  }

  void _cancelDownload() => _token?.cancel('user_cancel');

  TextStyle _titleStyle() => TextStyle(
      color: widget.style.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w700);

  TextStyle _bodyStyle({Color? color, double size = 12.5}) => TextStyle(
      color: color ?? widget.style.textSecondary,
      fontSize: size,
      height: 1.5);

  Widget _divider() => Divider(
      height: 20,
      color: widget.style.textSecondary.withValues(alpha: 0.15));

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: widget.style.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
      );

  /// 说明 / 进度 / 完成 三个阶段的正文。
  Widget _content() {
    final style = widget.style;
    final release = widget.release;
    switch (_stage) {
      case _UpdateStage.info:
        final asset = _asset;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('v${release.version}',
                      style: TextStyle(
                          color: style.accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: style.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: style.accent.withValues(alpha: 0.5)),
                    ),
                    child: Text('新版本',
                        style: TextStyle(
                            color: style.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (publishedDate(release.publishedAt).isNotEmpty)
                Text('发布于 ${publishedDate(release.publishedAt)}',
                    style: _bodyStyle(size: 11.5)),
              Text('更新非强制，可稍后再来，也可以随时关闭。',
                  style: _bodyStyle(size: 11.5)),
              _divider(),
              _label('更新说明'),
              Text(release.body.trim().isEmpty
                  ? '（该版本未附更新说明）'
                  : release.body.trim(),
                  style: _bodyStyle()),
              if (asset != null) ...[
                _divider(),
                Row(
                  children: [
                    Icon(Icons.archive_outlined,
                        size: 15, color: style.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _bodyStyle(size: 11.5)),
                    ),
                    Text(formatSize(asset.size),
                        style: _bodyStyle(size: 11.5)),
                  ],
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_error,
                    style:
                        _bodyStyle(color: Colors.redAccent.shade200, size: 12)),
              ],
            ],
          ),
        );

      case _UpdateStage.downloading:
        final known = _total > 0;
        final percent = known ? _received / _total : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在下载 ${_asset?.name ?? '安装包'}',
                style: _bodyStyle(size: 12)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: known ? percent : null,
                minHeight: 6,
                color: style.accent,
                backgroundColor: style.surface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              known
                  ? '${(percent * 100).toStringAsFixed(0)}%　'
                      '${(_received / 1048576).toStringAsFixed(1)} MB / '
                      '${formatSize(_total)}'
                  : '${(_received / 1048576).toStringAsFixed(1)} MB',
              style: _bodyStyle(size: 11.5),
            ),
            const SizedBox(height: 4),
            if (_source.isNotEmpty)
              Text(
                '下载源：$_source'
                '${_source == 'GitHub 官方直连' ? '' : '（国内镜像加速）'}',
                style: _bodyStyle(size: 11.5),
              ),
            Text('下载完成后自动拉起系统安装，可随时取消。',
                style: _bodyStyle(size: 11.5)),
          ],
        );

      case _UpdateStage.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: style.accent),
                const SizedBox(width: 8),
                Text('安装包已下载',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            if (_notice.isNotEmpty) Text(_notice, style: _bodyStyle()),
            if (_source.isNotEmpty)
              Text(
                '下载源：$_source'
                '${_source == 'GitHub 官方直连' ? '' : '（国内镜像加速）'}'
                '${_verified ? '，已通过 SHA-256 完整性校验' : ''}',
                style: _bodyStyle(size: 11.5),
              ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: _bodyStyle(color: Colors.redAccent.shade200)),
            ],
          ],
        );
    }
  }

  Widget _filledButton(String text, VoidCallback onPressed) => FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: widget.style.accent,
            foregroundColor: widget.style.bgBottom),
        onPressed: onPressed,
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );

  Widget _textButton(String text, VoidCallback onPressed) => TextButton(
        onPressed: onPressed,
        child: Text(text, style: TextStyle(color: widget.style.textSecondary)),
      );

  /// 每个阶段都有明确的推进/退出按钮 —— 下载、安装、关闭永远由用户主动触发。
  List<Widget> _actions() {
    switch (_stage) {
      case _UpdateStage.info:
        return [
          _textButton('稍后', () => Navigator.of(context).pop()),
          if (supportsInAppInstall)
            _filledButton('下载并安装', _startDownload)
          else
            _filledButton('打开发布页', _openReleasePage),
        ];
      case _UpdateStage.downloading:
        return [_textButton('取消下载', _cancelDownload)];
      case _UpdateStage.ready:
        return [
          _textButton('关闭', () => Navigator.of(context).pop()),
          _filledButton('立即安装', _install),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return AlertDialog(
      backgroundColor: Color.alphaBlend(style.surface, const Color(0x8C000000)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.uiRadius + 6),
        side: BorderSide(color: style.surfaceBorder),
      ),
      title: Text(
        _stage == _UpdateStage.downloading
            ? '下载更新'
            : _stage == _UpdateStage.ready
                ? '准备安装'
                : '发现新版本',
        style: _titleStyle(),
      ),
      content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400), child: _content()),
      actions: _actions(),
    );
  }
}
