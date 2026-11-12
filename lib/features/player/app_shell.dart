import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'play_utils.dart' as play;

/// 应用壳：四 Tab 导航（发现 / 搜索 / 音乐库 / 我的）+ 迷你播放条。
/// 导航与迷你条为中性半透明材质，细线进度，可关闭。
/// 本地音乐不占导航位：在「音乐库」页内以「本地」页签呈现。
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

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
  Widget build(BuildContext context, WidgetRef ref) {
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

    // 桌面（宽窗）用左侧玻璃导航栏；窄屏（手机/小窗）沿用底部悬浮坞。
    final width = MediaQuery.sizeOf(context).width;
    final useSidebar = width >= 820;
    // macOS 隐藏标题栏后内容会铺到交通灯之下，顶部留出交通灯高度避免遮挡。
    final macInset =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ? 30.0 : 0.0;

    if (useSidebar) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(gradient: style.backgroundGradient),
          child: Padding(
            padding: EdgeInsets.only(top: macInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  index: _indexFor(location),
                  onSelect: (i) {
                    const paths = ['/', '/search', '/library', '/profile'];
                    context.go(paths[i]);
                  },
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: child,
      ),
      // bottomNavigationBar 是独立插槽，body 渐变覆盖不到；铺 bgBottom
      // 与主体渐变末端无缝衔接，消除透明 Scaffold 露出的白色画布底。
      bottomNavigationBar: Container(
        color: style.bgBottom,
        child: SafeArea(
          top: false,
          // 与 body 用同一套内容列封顶规则：宽屏下悬浮坞边缘与正文内容边缘
          // 严格对齐，避免出现「正文居中、底栏通栏」的两种节奏。
          child: AppContentColumn(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.hasValue && item.valueOrNull != null)
                  NowPlayingBar(item: item.value!),
                _NavDock(
                  index: _indexFor(location),
                  onSelect: (i) {
                    const paths = ['/', '/search', '/library', '/profile'];
                    context.go(paths[i]);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部导航坞：毛玻璃悬浮条 + 描边圆角，替代原生 NavigationBar。
/// 选中项：accent 药丸底 + 实心图标 + 加粗标签；未选中：次级色调线框图标。
class _NavDock extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _NavDock({required this.index, required this.onSelect});

  static const _items = [
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.search, Icons.search, '搜索'),
    (Icons.library_music_outlined, Icons.library_music, '音乐库'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final radius = BorderRadius.circular(AMTokens.radiusPanel);

    return Padding(
      // 左右外边距直接取页面留白，导航坞边缘与页面内容边缘严格对齐。
      padding: EdgeInsets.fromLTRB(sp.gutter, sp.micro, sp.gutter, sp.inline),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: AMTokens.barBlur, sigmaY: AMTokens.barBlur),
          child: Container(
            decoration: BoxDecoration(
              // 中性半透明材质 + 极淡 hairline，无压黑、无重投影。
              color: style.surface,
              borderRadius: radius,
              border: Border.all(color: style.surfaceBorder, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                for (final (i, it) in _items.indexed)
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
        ),
      ),
    );
  }
}

/// 单个导航项：选中态药丸高亮 + 图标/标签同步变色，切换带动效。
class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final fg = selected ? style.accent : style.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          // 选中态：淡红底 + 8pt 圆角，不用高饱和药丸。
          color: selected
              ? style.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AMTokens.radiusArt),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: fg, size: 22),
            const SizedBox(height: AppSpacing.micro),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
      ),
    );
  }
}

/// 桌面左侧玻璃导航栏：品牌 + 导航项 + 底部迷你播放器。
/// 与底部悬浮坞共享同一套选中逻辑与视觉语言（glass + accent），
/// 但改为竖向排布，更贴合 macOS 窗口的导航习惯。
class _Sidebar extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

  static const _items = [
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.search, Icons.search, '搜索'),
    (Icons.library_music_outlined, Icons.library_music, '音乐库'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Container(
      width: 250,
      decoration: BoxDecoration(
        // 中性材质 + 右沿 0.5pt hairline。
        color: style.surface,
        border: Border(
            right: BorderSide(color: style.surfaceBorder, width: 0.5)),
      ),
      child: Column(
        children: [
          // 品牌 + 分组标题：小字低调呈现，不再用大号粗体。
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 20, 14),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 20, 6),
            child: Text('浏览',
                style: TextStyle(
                    color: style.textSecondary.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ),
          for (final (i, it) in _items.indexed)
            _SidebarItem(
              style: style,
              icon: it.$1,
              activeIcon: it.$2,
              label: it.$3,
              selected: i == index,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          const _SidebarMiniPlayer(),
          const SizedBox(height: 14),
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
    final fg = widget.selected ? style.accent : style.textPrimary;
    final bg = widget.selected
        ? style.accent.withValues(alpha: 0.12)
        : (_hover ? style.surfaceBorder : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
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
                  color: fg, size: 18),
              const SizedBox(width: 12),
              Text(widget.label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w400)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏底部迷你播放器：紧凑横向卡，封面 + 标题/歌手 + 播放/下一首，
/// 点击进入全屏播放页。与底部悬浮坞的迷你条共享同一份播放状态。
class _SidebarMiniPlayer extends ConsumerWidget {
  const _SidebarMiniPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final item = ref.watch(currentMediaItemProvider);
    if (!item.hasValue || item.valueOrNull == null) return const SizedBox.shrink();
    final m = item.value!;
    final ps = ref.watch(playbackStateProvider);
    final playing = ps.valueOrNull?.playing ?? false;
    final handler = ref.watch(audioHandlerProvider);
    final radius = BorderRadius.circular(AMTokens.radiusPanel);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: AMTokens.barBlur, sigmaY: AMTokens.barBlur),
          child: Material(
            color: style.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: style.surfaceBorder, width: 0.5),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: () {
                final route = ModalRoute.of(context);
                if (route != null && !route.isCurrent) return;
                context.push('/now-playing');
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    CoverImage(
                        url: m.artUri?.toString() ?? '',
                        size: 40,
                        radius: BorderRadius.circular(4)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(m.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                          color: style.textPrimary, size: 20),
                      tooltip: playing ? '暂停' : '播放',
                      onPressed: handler.togglePlayPause,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.skip_next,
                          color: style.textPrimary, size: 18),
                      tooltip: '下一首',
                      onPressed: () => play.skipNext(ref, context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你播放条：悬浮玻璃卡，封面外圈为环形进度（替代旧版通栏 2px 线），
/// 点击整条进入全屏播放页，右侧 X 停止播放并清空队列（迷你条随之消失）。
class NowPlayingBar extends ConsumerWidget {
  final MediaItem item;
  const NowPlayingBar({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final ps = ref.watch(playbackStateProvider);
    final playing = ps.valueOrNull?.playing ?? false;
    final handler = ref.watch(audioHandlerProvider);
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final fraction = duration <= Duration.zero
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final radius = BorderRadius.circular(AMTokens.radiusPanel);

    return Padding(
      // 与导航坞共用同一组左右留白，两块悬浮卡的宽度因此始终相等。
      padding: EdgeInsets.fromLTRB(sp.gutter, 0, sp.gutter, sp.micro),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: AMTokens.barBlur, sigmaY: AMTokens.barBlur),
          child: Material(
            color: style.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: style.surfaceBorder, width: 0.5),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: () {
                // /now-playing 转场窗口内连点：本页已非顶层（播放页正在
                // 入栈动画中）时不重复 push，避免叠出多个播放页实例。
                final route = ModalRoute.of(context);
                if (route != null && !route.isCurrent) return;
                context.push('/now-playing');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    // 封面 + 环形进度圈 + 右下角状态角标（播放中跳动音符）
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Apple Music：3pt 细线进度（保留原有 fraction 计算）。
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  AMTokens.radiusLine),
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 3,
                                backgroundColor: style.textSecondary
                                    .withValues(alpha: 0.25),
                                valueColor:
                                    AlwaysStoppedAnimation(style.accent),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5.5),
                            // 封面保持静态：不做呼吸缩放 / 辉光 / 压暗，
                            // 播放状态只由右下角角标表达。
                            child: item.artUri != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SafeNetworkImage(
                                        url: item.artUri.toString(),
                                        width: 33,
                                        height: 33,
                                        fit: BoxFit.cover),
                                  )
                                : Container(
                                    width: 33,
                                    height: 33,
                                    color: style.surfaceBorder
                                        .withValues(alpha: 0.4),
                                    child: Icon(Icons.music_note,
                                        size: 16,
                                        color: style.textSecondary),
                                  ),
                          ),
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: _StateBadge(
                                style: style, playing: playing),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                          color: style.textPrimary, size: 24),
                      tooltip: playing ? '暂停' : '播放',
                      onPressed: handler.togglePlayPause,
                    ),
                    // 下一曲：顺序模式到队尾置灰；循环/随机总可用。
                    Consumer(builder: (c, cref, _) {
                      final q = cref.watch(queueProvider).valueOrNull;
                      final mode = cref.watch(playModeProvider);
                      final ok = q != null &&
                          q.songs.isNotEmpty &&
                          (mode != PlayMode.sequential ||
                              q.index < q.songs.length - 1);
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.skip_next,
                            color: ok
                                ? style.textPrimary
                                : style.textSecondary.withValues(alpha: 0.35),
                            size: 20),
                        tooltip: ok ? '下一首' : '没有下一曲',
                        onPressed:
                            ok ? () => play.skipNext(ref, context) : null,
                      );
                    }),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close,
                          color: style.textSecondary.withValues(alpha: 0.8),
                          size: 17),
                      tooltip: '关闭播放器',
                      onPressed: () => handler.clearQueue(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面右下角状态标记：静态小圆点，播放中品牌红、暂停时中性灰。
class _StateBadge extends StatelessWidget {
  final AppStyle style;
  final bool playing;
  const _StateBadge({required this.style, required this.playing});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: AMTokens.motionMicro),
        curve: Curves.easeOutCubic,
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: playing ? style.accent : style.textSecondary,
        ),
      );
}
