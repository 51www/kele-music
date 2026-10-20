import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// 应用壳：四 Tab 导航（发现 / 搜索 / 音乐库 / 我的）+ 迷你播放条。
/// 导航为玻璃悬浮坞，迷你条为悬浮玻璃卡（环形进度 + 可关闭）。
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  int _indexFor(String loc) {
    if (loc.startsWith('/search') || loc.startsWith('/playlist')) return 1;
    if (loc.startsWith('/library')) return 2;
    // 设置页入口已移入「我的」，导航高亮归属「我的」。
    if (loc.startsWith('/profile') || loc.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final radius = BorderRadius.circular(style.uiRadius + 6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          // 选中药丸：accent 低透明度填充，随 uiRadius 缩放。
          color: selected ? style.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(style.uiRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: fg, size: 21),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    color: fg,
                    fontSize: 10.5,
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
    final ps = ref.watch(playbackStateProvider);
    final playing = ps.valueOrNull?.playing ?? false;
    final handler = ref.watch(audioHandlerProvider);
    final position = ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final fraction =
        duration <= Duration.zero ? 0.0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final radius = BorderRadius.circular(style.uiRadius + 4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Row(
                  children: [
                    // 封面 + 环形进度圈
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 42,
                            height: 42,
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
                                        width: 31,
                                        height: 31,
                                        fit: BoxFit.cover),
                                  )
                                : Icon(Icons.music_note,
                                    size: 16, color: style.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 1),
                          Text(item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                          color: style.textPrimary, size: 24),
                      tooltip: playing ? '暂停' : '播放',
                      onPressed: () => playing ? handler.pause() : handler.play(),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.skip_next,
                          color: style.textPrimary, size: 20),
                      tooltip: '下一首',
                      onPressed: () => handler.skipToNext(),
                    ),
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
