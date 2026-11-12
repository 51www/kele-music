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

    // 桌面（宽窗）用左侧导航栏；窄屏（手机/小窗）用贴底标签栏。
    final width = MediaQuery.sizeOf(context).width;
    final useSidebar = width >= 820;
    final loc = GoRouterState.of(context).uri.toString();
    final index = _indexFor(loc);
    const paths = <String>['/', '/search', '/library', '/profile'];
    // macOS 隐藏标题栏后内容会铺到交通灯之下，顶部留出交通灯高度避免遮挡。
    final macInset =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ? 30.0 : 0.0;

    if (useSidebar) {
      // Apple Music 桌面骨架：侧栏 + 内容区（顶部 44pt 工具栏）+
      // 横跨整个窗口宽度的 72pt 通栏播放条。
      return Scaffold(
        backgroundColor: style.bgTop,
        body: Container(
          color: style.bgTop,
          child: Padding(
            padding: EdgeInsets.only(top: macInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(index: index, onSelect: (i) => context.go(paths[i])),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AMToolbar(
                        style: style,
                        onAccount: () => context.go('/profile'),
                      ),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: (item.hasValue && item.valueOrNull != null)
            ? NowPlayingBar(item: item.value!)
            : null,
      );
    }

    // 移动端：贴底迷你播放器 + 贴底标签栏（不再是悬浮玻璃卡/悬浮坞）。
    return Scaffold(
      backgroundColor: style.bgTop,
      body: Container(color: style.bgTop, child: child),
      bottomNavigationBar: Container(
        color: style.bgBottom,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.hasValue && item.valueOrNull != null)
                NowPlayingBar(item: item.value!),
              _NavDock(index: index, onSelect: (i) => context.go(paths[i])),
            ],
          ),
        ),
      ),
    );
  }
}

/// 内容区顶部系统工具栏：44pt，前进/后退（无历史时禁用态）+ 账户入口。
/// 账户入口复用原有 /profile 导航，不新增功能。
class _AMToolbar extends StatelessWidget {
  final AppStyle style;
  final VoidCallback onAccount;
  const _AMToolbar({required this.style, required this.onAccount});

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: style.surface,
          border: Border(
              bottom: BorderSide(color: style.surfaceBorder, width: 0.5)),
        ),
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
                child: Icon(Icons.person,
                    size: 16, color: style.textPrimary),
              ),
            ),
          ],
        ),
      );
}

/// 底部标签栏：贴底全宽 49pt 系统材质，替代悬浮玻璃坞与彩色药丸。
class _NavDock extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _NavDock({required this.index, required this.onSelect});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '现在听'),
    (Icons.search_outlined, Icons.search_rounded, '搜索'),
    (Icons.library_music_outlined, Icons.library_music_rounded, '资料库'),
    (Icons.person_outline, Icons.person_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
            sigmaX: AMTokens.barBlur, sigmaY: AMTokens.barBlur),
        child: Container(
          height: 49,
          decoration: BoxDecoration(
            color: style.surface,
            border: Border(
                top: BorderSide(color: style.surfaceBorder, width: 0.5)),
          ),
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
            Icon(selected ? activeIcon : icon, color: fg, size: 24),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// 桌面左侧栏：Apple Music 信息架构 —— 顶部搜索框 + 三个分组。
/// 四个导航入口与索引完全不变；搜索从列表项改为顶部搜索框（仍走 onSelect(1)）。
/// 底部不再放迷你播放器，由横跨全宽的通栏播放条承担。
class _Sidebar extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

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

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: style.surface,
        border: Border(
            right: BorderSide(color: style.surfaceBorder, width: 0.5)),
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: () => onSelect(1),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: style.textSecondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: style.textSecondary),
                    const SizedBox(width: 8),
                    Text('搜索',
                        style: TextStyle(
                            color: style.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
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
    final list = ref.watch(createdPlaylistsProvider).valueOrNull?.playlists ?? [];
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 7),
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
                                  color: style.textPrimary,
                                  fontSize: 13)),
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

/// 播放条：宽屏 = 横跨全窗口的 72pt 三分区通栏条（曲目 / 传输+进度 / 队列+关闭），
/// 窄屏 = 贴标签栏上沿的 56pt 迷你条。两者共用同一套状态、回调与路由。
class NowPlayingBar extends ConsumerWidget {
  final MediaItem item;
  const NowPlayingBar({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final playing =
        ref.watch(playbackStateProvider).valueOrNull?.playing ?? false;
    final handler = ref.watch(audioHandlerProvider);
    final pos =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
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
                style: TextStyle(
                    color: style.textSecondary, fontSize: 11)),
          ],
        );

    Widget playBtn(double z) => IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow,
              color: style.textPrimary, size: z),
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
                minHeight: 3,
                backgroundColor:
                    style.textSecondary.withValues(alpha: 0.25),
                valueColor: AlwaysStoppedAnimation(style.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(fmt(dur), style: ts),
        ]);

    return Container(
      height: wide ? 72 : 56,
      decoration: BoxDecoration(
        color: style.surface,
        border: Border(
            top: BorderSide(color: style.surfaceBorder, width: 0.5)),
      ),
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
    );
  }
}
