import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/glass.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'play_utils.dart' as play;

/// 应用壳：三 Tab 导航（发现 / 音乐库 / 我的）+ 迷你播放条。
/// 搜索页不占导航位，由发现页顶部的搜索按钮进入。
/// 导航与迷你条为中性半透明材质，细线进度，可关闭。
/// 本地音乐不占导航位：在「音乐库」页内以「本地」页签呈现。
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 滚动强度 0..1：驱动贴边浮层的「材质加厚」过渡。
  /// 用 ValueNotifier 而非 setState，页面内容经 ValueListenableBuilder 的
  /// child 参数复用，滚动时只重建浮层，不重建整棵页面树。
  final ValueNotifier<double> _scrollIntensity = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrollIntensity.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final next = (n.metrics.pixels / 160).clamp(0.0, 1.0);
    if ((next - _scrollIntensity.value).abs() > 0.02) {
      _scrollIntensity.value = next;
    }
    return false;
  }

  int _indexFor(String loc) {
    if (loc.startsWith('/search') || loc.startsWith('/playlist')) return 1;
    if (loc.startsWith('/library')) return 2;
    // 本地歌单详情属于「音乐库」页内的本地页签，高亮归属音乐库。
    if (loc.startsWith('/local')) return 2;
    // 设置 / 历史 / 收听统计入口都在「我的」，导航高亮归属「我的」。
    if (loc.startsWith('/profile') ||
        loc.startsWith('/settings') ||
        loc.startsWith('/history') ||
        loc.startsWith('/listen-stats')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 播放失败轻提示（全局唯一出口）：下一曲/上一曲、播放队列页点歌、
    // 播放按钮重试、自动切歌等 handler 内部兜底的失败在此统一弹出。
    // AppShell 常驻，SnackBar 经根 ScaffoldMessenger 显示在当前顶层页面。
    ref.listen(playErrorProvider, (prev, next) {
      final msg = next.valueOrNull;
      if (msg == null || !context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
    });
    final style = kStyles[ref.watch(styleIndexProvider)];
    final item = ref.watch(currentMediaItemProvider);
    final resume = ref.watch(resumePromptProvider);
    final playing =
        ref.watch(playbackStateProvider).valueOrNull?.playing ?? false;
    // 冷启动断点待机：用户尚未确认续播（或已忽略提示但从未起播）时，
    // 不弹固定播放条。「真的已在播」（热重启 / 系统媒体键起播）不抑制。
    final idle = resume.awaitingFirstPlay && !playing;
    final hasItem = item.hasValue && item.valueOrNull != null;
    final showPrompt = resume.prompt != null && !playing;
    final showBar = hasItem && !idle && !showPrompt;

    // 桌面（宽窗）用左侧导航栏；窄屏（手机/小窗）用贴底标签栏。
    final width = MediaQuery.sizeOf(context).width;
    final useSidebar = width >= 820;
    final loc = GoRouterState.of(context).uri.toString();
    final index = _indexFor(loc);
    const paths = <String>['/', '/search', '/library', '/profile'];

    // 主路由切换：淡入 + 上移 3.5% + 轻微放大，编排在一个时刻里。
    // 系统开启「减少动态效果」时时长归零，退化为瞬时切换。
    Widget pageTransition(Widget page) => AnimatedSwitcher(
          duration: AMTokens.pageDuration(context),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (w, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
                      .animate(anim),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(anim),
                child: w,
              ),
            ),
          ),
          child: KeyedSubtree(key: ValueKey<String>(loc), child: page),
        );
    // macOS 隐藏标题栏后内容会铺到交通灯之下，顶部留出交通灯高度避免遮挡。
    final macInset =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ? 30.0 : 0.0;

    // 滚动通知只更新 intensity；页面内容作为 ValueListenableBuilder 的
    // child 复用，滚动时只重建浮层材质，不重建整棵页面树。
    final page = NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: pageTransition(widget.child),
    );

    return ValueListenableBuilder<double>(
      valueListenable: _scrollIntensity,
      child: page,
      builder: (context, intensity, pageChild) {
        if (useSidebar) {
          // Apple Music 桌面骨架：侧栏 + 内容区（顶部 44pt 工具栏）+
          // 横跨整个窗口宽度的 72pt 通栏播放条。extendBody 让页面内容
          // 穿过播放条下方，浮层的背景模糊才真正可见。
          return Scaffold(
            backgroundColor: style.bgTop,
            extendBody: true,
            body: Container(
              color: style.bgTop,
              child: Padding(
                padding: EdgeInsets.only(top: macInset),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(
                        index: index,
                        intensity: intensity,
                        onSelect: (i) => context.go(paths[i])),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AMToolbar(
                            style: style,
                            intensity: intensity,
                            onAccount: () => context.go('/profile'),
                          ),
                          Expanded(child: pageChild!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: showPrompt
                ? _ResumePromptBar(prompt: resume.prompt!, intensity: intensity)
                : (showBar
                    ? NowPlayingBar(item: item.value!, intensity: intensity)
                    : null),
          );
        }

        // 移动端：贴底迷你播放器 + 贴底标签栏。外层不再垫不透明底色，
        // 否则会把浮层的背景模糊完全挡住。
        return Scaffold(
          backgroundColor: style.bgTop,
          extendBody: true,
          body: Container(color: style.bgTop, child: pageChild!),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPrompt)
                  _ResumePromptBar(prompt: resume.prompt!, intensity: intensity)
                else if (showBar)
                  NowPlayingBar(item: item.value!, intensity: intensity),
                _NavDock(
                    index: index,
                    intensity: intensity,
                    onSelect: (i) => context.go(paths[i])),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 内容区顶部系统工具栏：44pt，前进/后退（无历史时禁用态）+ 账户入口。
/// 账户入口复用原有 /profile 导航，不新增功能。
class _AMToolbar extends StatelessWidget {
  final AppStyle style;
  final VoidCallback onAccount;
  final double intensity;
  const _AMToolbar({
    required this.style,
    required this.onAccount,
    this.intensity = 0,
  });

  @override
  Widget build(BuildContext context) => AMGlass(
        kind: AMGlassKind.bar,
        intensity: intensity,
        edges: const {AMGlassEdge.bottom},
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Icon(Icons.chevron_left,
                  size: 20, color: style.textSecondary.withValues(alpha: 0.35)),
              const SizedBox(width: 16),
              Icon(Icons.chevron_right,
                  size: 20, color: style.textSecondary.withValues(alpha: 0.35)),
              const Spacer(),
              GestureDetector(
                onTap: onAccount,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.textSecondary.withValues(alpha: 0.18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.person, size: 16, color: style.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
}

/// 底部标签栏：贴底全宽 49pt 系统材质，替代悬浮玻璃坞与彩色药丸。
class _NavDock extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final double intensity;
  const _NavDock({
    required this.index,
    required this.onSelect,
    this.intensity = 0,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '现在听'),
    (Icons.search_outlined, Icons.search_rounded, '搜索'),
    (Icons.library_music_outlined, Icons.library_music_rounded, '资料库'),
    (Icons.person_outline, Icons.person_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return AMGlass(
      kind: AMGlassKind.bar,
      intensity: intensity,
      edges: const {AMGlassEdge.top},
      child: SizedBox(
        height: 49,
        child: Row(
          children: [
            for (final (i, it) in _items.indexed)
              // 搜索项（索引 1）不进导航菜单；_items 索引与 paths 保持原样。
              if (i != 1)
                Expanded(
                  child: _NavItem(
                    style: style,
                    icon: it.$1,
                    activeIcon: it.$2,
                    label: it.$3,
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 单个导航项：选中仅图标与文字变品牌红并切填充图标，无药丸底。
class _NavItem extends ConsumerWidget {
  final AppStyle style;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.style,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = selected ? style.accent : style.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 结构红指示条：只在当前标签出现，编码「当前所在」。
            Container(
              width: 24,
              height: AMTokens.signalIndicator,
              decoration: BoxDecoration(
                color: selected ? AMTokens.signal : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 3),
            Icon(selected ? activeIcon : icon, color: fg, size: 24),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// 桌面左侧栏：三个分组导航（APPLE MUSIC / 资料库 / 账户）。
/// 搜索入口已从导航移除，但 _items 索引与 paths 的对应关系保持不变；
/// 搜索页仍由发现页顶部的搜索按钮进入。
/// 底部不再放迷你播放器，由横跨全宽的通栏播放条承担。
class _Sidebar extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final double intensity;
  const _Sidebar({
    required this.index,
    required this.onSelect,
    this.intensity = 0,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '现在听'),
    (Icons.search_outlined, Icons.search_rounded, '搜索'),
    (Icons.library_music_outlined, Icons.library_music_rounded, '资料库'),
    (Icons.person_outline, Icons.person_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];

    Widget group(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(title,
              style: TextStyle(
                  color: style.textSecondary.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2)),
        );

    Widget item(int i) => _SidebarItem(
          style: style,
          icon: _items[i].$1,
          activeIcon: _items[i].$2,
          label: _items[i].$3,
          selected: i == index,
          onTap: () => onSelect(i),
        );

    return AMGlass(
      kind: AMGlassKind.bar,
      intensity: intensity,
      edges: const {AMGlassEdge.right},
      child: SizedBox(
        width: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.music_note, color: style.accent, size: 18),
                  const SizedBox(width: 10),
                  Text('可乐音乐',
                      style: TextStyle(
                          color: style.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2)),
                ],
              ),
            ),
            group('APPLE MUSIC'),
            item(0),
            group('资料库'),
            item(2),
            group('账户'),
            item(3),
            _SidebarPlaylists(style: style),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text('可乐音乐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: style.textSecondary.withValues(alpha: 0.55),
                      fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧栏「播放列表」分组：只读展示已创建歌单，点击沿用资料库页原有跳转规则
/// （本地歌单 /user-playlist/:id，云端歌单 /playlist/:id），不新增数据或业务。
class _SidebarPlaylists extends ConsumerWidget {
  final AppStyle style;
  const _SidebarPlaylists({required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(createdPlaylistsProvider).valueOrNull?.playlists ?? [];
    if (list.isEmpty) return const Spacer();
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text('播放列表',
                style: TextStyle(
                    color: style.textSecondary.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: list.length,
              itemBuilder: (c, i) {
                final pl = list[i];
                return InkWell(
                  onTap: () => context.push(pl.local
                      ? '/user-playlist/${pl.id}'
                      : '/playlist/${pl.id}'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                    child: Row(
                      children: [
                        Icon(Icons.queue_music,
                            size: 16, color: style.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(pl.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textPrimary, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏导航项：选中态 accent 药丸高亮，悬停显次级高亮，鼠标点击光标。
class _SidebarItem extends StatefulWidget {
  final AppStyle style;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.style,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final fg = widget.selected ? AMTokens.signalOn : style.textPrimary;
    final bg = widget.selected
        ? AMTokens.signal
        : (_hover ? style.surfaceBorder : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AMTokens.reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: AMTokens.motionMicro),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AMTokens.radiusArt),
          ),
          child: Row(
            children: [
              Icon(widget.selected ? widget.activeIcon : widget.icon,
                  color: fg, size: 20),
              const SizedBox(width: 12),
              Text(widget.label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w400)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「继续收听」提示栏：冷启动检测到上次未播完的歌曲时，取代固定播放条
/// 出现在同一位置（宽屏底部通栏 / 窄屏标签栏上沿）。只占一条细栏、
/// 不遮挡内容、不弹窗，可整条点击续播，也可一键忽略。
///
/// 展示位置：只在 AppShell 内的主路由（发现 / 搜索 / 资料库 / 歌单 / 我的等）
/// 出现。/now-playing、/queue、/login 等 Shell 外全屏页自带播放控制或属
/// 独立流程，不叠提示；用户从这些页面返回时若仍未续播，提示依然在。
class _ResumePromptBar extends ConsumerWidget {
  final ResumePrompt prompt;
  final double intensity;
  const _ResumePromptBar({required this.prompt, this.intensity = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final reduced = AMTokens.reduceMotion(context);
    final song = prompt.song;

    void resume() {
      // 防重入：整条与右侧按钮共用同一动作。
      final ctrl = ref.read(resumePromptProvider.notifier);
      if (ref.read(resumePromptProvider).prompt == null) return;
      // 先结束待续播阶段（正常播放条随之出现），再交给既有断点续播路径：
      // restoreQueue 已 seek 到断点，play() 会消费冷启动重建标记从断点起播；
      // 恢复装载失败时 play() 会自动重试解析并补上断点进度。
      ctrl.markStarted();
      unawaited(ref.read(audioHandlerProvider).play());
    }

    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    Widget cover(double z) => ClipRRect(
          borderRadius: BorderRadius.circular(AMTokens.radiusThumb),
          child: song.coverUrl.isNotEmpty
              ? SafeNetworkImage(
                  url: song.coverUrl, width: z, height: z, fit: BoxFit.cover)
              : Container(
                  width: z,
                  height: z,
                  color: style.surfaceBorder,
                  child: Icon(Icons.music_note,
                      size: z * 0.5, color: style.textSecondary)),
        );

    final subtitle = prompt.position > Duration.zero
        ? '${song.name} · 上次听到 ${fmt(prompt.position)}'
        : '${song.name} · ${song.artistName}';

    final content = Row(
      children: [
        // 结构红：整条提示唯一的强调，编码「这首歌正等你继续」。
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AMTokens.signal,
            borderRadius: BorderRadius.circular(AMTokens.radiusPill),
          ),
          child:
              const Icon(Icons.play_arrow, size: 18, color: AMTokens.signalOn),
        ),
        const SizedBox(width: 12),
        if (wide) ...[cover(36), const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('继续收听',
                  maxLines: 1,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: style.textSecondary, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: resume,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AMTokens.signal,
              borderRadius: BorderRadius.circular(AMTokens.radiusPill),
            ),
            child: Text(wide ? '继续收听' : '继续',
                style: const TextStyle(
                    color: AMTokens.signalOn,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, size: 18, color: style.textSecondary),
          tooltip: '忽略',
          onPressed: () => ref.read(resumePromptProvider.notifier).dismiss(),
        ),
      ],
    );

    // 轻微上移淡入，尊重系统「减少动态效果」。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduced
          ? Duration.zero
          : const Duration(milliseconds: AMTokens.motionReveal),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: resume,
        child: AMGlass(
          kind: AMGlassKind.bar,
          intensity: intensity,
          edges: const {AMGlassEdge.top},
          padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 16),
          child: SizedBox(
            height: wide ? 60 : 54,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 播放条：宽屏 = 横跨全窗口的 72pt 三分区通栏条（曲目 / 传输+进度 / 队列+关闭），
/// 窄屏 = 贴标签栏上沿的 56pt 迷你条。两者共用同一套状态、回调与路由。
class NowPlayingBar extends ConsumerWidget {
  final MediaItem item;
  final double intensity;
  const NowPlayingBar({super.key, required this.item, this.intensity = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final playing =
        ref.watch(playbackStateProvider).valueOrNull?.playing ?? false;
    final handler = ref.watch(audioHandlerProvider);
    final pos = ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final dur = item.duration ?? Duration.zero;
    final f = dur <= Duration.zero
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final wide = MediaQuery.sizeOf(context).width >= 820;

    void open() {
      final r = ModalRoute.of(context);
      if (r != null && !r.isCurrent) return;
      context.push('/now-playing');
    }

    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$sec';
    }

    Widget cover(double z) => ClipRRect(
          borderRadius: BorderRadius.circular(AMTokens.radiusThumb),
          child: item.artUri != null
              ? SafeNetworkImage(
                  url: item.artUri.toString(),
                  width: z,
                  height: z,
                  fit: BoxFit.cover)
              : Container(
                  width: z,
                  height: z,
                  color: style.surfaceBorder,
                  child: Icon(Icons.music_note,
                      size: z * 0.45, color: style.textSecondary)),
        );

    Widget info() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: style.textSecondary, fontSize: 11)),
          ],
        );

    Widget playBtn(double z) => IconButton(
          visualDensity: VisualDensity.compact,
          icon: AnimatedSwitcher(
            duration: AMTokens.reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: AMTokens.motionPop),
            transitionBuilder: (w, a) => ScaleTransition(
              scale: a,
              child: FadeTransition(opacity: a, child: w),
            ),
            child: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              key: ValueKey<bool>(playing),
              color: style.textPrimary,
              size: z,
            ),
          ),
          tooltip: playing ? '暂停' : '播放',
          onPressed: handler.togglePlayPause,
        );

    Widget nextBtn(double z) => Consumer(builder: (c, cr, _) {
          final q = cr.watch(queueProvider).valueOrNull;
          final m = cr.watch(playModeProvider);
          final ok = q != null &&
              q.songs.isNotEmpty &&
              (m != PlayMode.sequential || q.index < q.songs.length - 1);
          return IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.skip_next,
                size: z,
                color: ok
                    ? style.textPrimary
                    : style.textSecondary.withValues(alpha: 0.35)),
            tooltip: ok ? '下一首' : '没有下一曲',
            onPressed: ok ? () => play.skipNext(ref, context) : null,
          );
        });

    Widget closeBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: style.textSecondary, size: 18),
          tooltip: '关闭播放器',
          onPressed: () => handler.clearQueue(),
        );

    final ts = TextStyle(
        color: style.textSecondary,
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()]);
    Widget progress() => Row(children: [
          Text(fmt(pos), style: ts),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AMTokens.radiusLine),
              child: LinearProgressIndicator(
                value: f,
                minHeight: AMTokens.signalBar,
                backgroundColor: style.textSecondary.withValues(alpha: 0.25),
                valueColor: AlwaysStoppedAnimation(style.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(fmt(dur), style: ts),
        ]);

    return AMGlass(
      kind: AMGlassKind.bar,
      intensity: intensity,
      edges: const {AMGlassEdge.top},
      child: SizedBox(
        height: wide ? 72 : 56,
        child: wide
            ? Row(children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: open,
                      child: Row(children: [
                        cover(48),
                        const SizedBox(width: 12),
                        Expanded(child: info()),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            playBtn(28),
                            const SizedBox(width: 8),
                            nextBtn(24),
                          ],
                        ),
                        const SizedBox(height: 4),
                        progress(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.queue_music,
                              color: style.textSecondary, size: 20),
                          tooltip: '播放队列',
                          onPressed: () => context.push('/queue'),
                        ),
                        closeBtn(),
                      ],
                    ),
                  ),
                ),
              ])
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: open,
                  child: Row(children: [
                    cover(40),
                    const SizedBox(width: 12),
                    Expanded(child: info()),
                    playBtn(24),
                    nextBtn(20),
                    closeBtn(),
                  ]),
                ),
              ),
      ),
    );
  }
}
