import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'play_utils.dart' as play;

/// 应用壳：四 Tab 导航（发现 / 搜索 / 音乐库 / 我的）+ 迷你播放条。
/// 导航为玻璃悬浮坞，迷你条为悬浮玻璃卡（环形进度 + 可关闭）。
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  int _indexFor(String loc) {
    if (loc.startsWith('/search') || loc.startsWith('/playlist')) return 1;
    if (loc.startsWith('/library')) return 2;
    // 设置页/历史页入口都在「我的」，导航高亮归属「我的」。
    if (loc.startsWith('/profile') ||
        loc.startsWith('/settings') ||
        loc.startsWith('/history')) return 3;
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
    final radius = BorderRadius.circular(style.uiRadius + 6);

    return Padding(
      // 左右外边距直接取页面留白，导航坞边缘与页面内容边缘严格对齐。
      padding: EdgeInsets.fromLTRB(sp.gutter, sp.micro, sp.gutter, sp.inline),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              // 深色玻璃底：保证任意主题/背景下图标文字可读。
              color: Color.alphaBlend(style.surface, const Color(0x66000000)),
              borderRadius: radius,
              border: Border.all(color: style.surfaceBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          // 选中药丸：accent 低透明度填充，随 uiRadius 缩放。
          color: selected
              ? style.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(style.uiRadius),
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
    final radius = BorderRadius.circular(style.uiRadius + 4);

    return Padding(
      // 与导航坞共用同一组左右留白，两块悬浮卡的宽度因此始终相等。
      padding: EdgeInsets.fromLTRB(sp.gutter, 0, sp.gutter, sp.micro),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: Color.alphaBlend(style.surface, const Color(0x66000000)),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: style.surfaceBorder),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: () => context.push('/now-playing'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    // 封面 + 环形进度圈
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              value: fraction,
                              strokeWidth: 2.5,
                              strokeCap: StrokeCap.round,
                              valueColor: AlwaysStoppedAnimation(style.accent),
                              backgroundColor:
                                  style.textSecondary.withValues(alpha: 0.25),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(5.5),
                            child: item.artUri != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SafeNetworkImage(
                                        url: item.artUri.toString(),
                                        width: 33,
                                        height: 33,
                                        fit: BoxFit.cover),
                                  )
                                : Icon(Icons.music_note,
                                    size: 16, color: style.textSecondary),
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
                      onPressed: () =>
                          playing ? handler.pause() : handler.play(),
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
