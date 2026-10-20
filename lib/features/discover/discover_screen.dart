import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  List<BannerItem> _banners = [];
  List<Playlist> _playlists = [];
  List<Ranking> _rankings = [];
  List<Song> _newSongs = [];
  bool _loading = true;
  bool _busyHero = false;
  bool _showAllRankings = false;
  String? _error;

  // Banner 自动轮播状态。
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _bannerPage = 0;
  int _bannerDir = 1; // 到端点后反向（ping-pong），避免跨页回跳。
  static const Duration _bannerInterval = Duration(seconds: 4);

  // 快捷入口锚点。
  final _newSongsKey = GlobalKey();
  final _rankKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(_bannerInterval, (_) {
      if (!mounted || _banners.length < 2 || !_bannerController.hasClients) {
        return;
      }
      // 用户正在手动滑动时跳过本轮，避免抢手势。
      if (_bannerController.position.isScrollingNotifier.value) return;
      var next = _bannerPage + _bannerDir;
      if (next >= _banners.length || next < 0) {
        _bannerDir = -_bannerDir;
        next = _bannerPage + _bannerDir;
      }
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.banners(),
        api.personalizedPlaylists(),
        api.rankings(),
        api.newSongs(),
      ]);
      if (!mounted) return;
      final playlists = [...results[1] as List<Playlist>];
      // 「今日推荐歌单」固定置顶（名称含「今日推荐/每日推荐」），其余保持原顺序。
      final todayIdx = playlists.indexWhere(
          (p) => p.name.contains('今日推荐') || p.name.contains('每日推荐'));
      if (todayIdx > 0) {
        playlists.insert(0, playlists.removeAt(todayIdx));
      }
      setState(() {
        _banners = results[0] as List<BannerItem>;
        _playlists = playlists;
        _rankings = results[2] as List<Ranking>;
        _newSongs = results[3] as List<Song>;
        _bannerPage = 0;
        _bannerDir = 1;
        _loading = false;
      });
      _startBannerTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Hero 大卡 CTA：直接播放该歌单。
  Future<void> _playPlaylist(Playlist p) async {
    if (_busyHero) return;
    setState(() => _busyHero = true);
    try {
      final detail =
          await ref.read(apiProvider).playlistDetail(p.id);
      if (!mounted) return;
      await playQueue(ref, detail.tracks, 0);
      if (mounted) context.push('/now-playing');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _busyHero = false);
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: style.textSecondary)),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: Icon(Icons.refresh,
                                color: style.textSecondary),
                            label: Text('重试',
                                style: TextStyle(color: style.textSecondary)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _buildHeader(style),
                          const SizedBox(height: 16),
                          _buildHero(style),
                          const SizedBox(height: 16),
                          _buildQuickEntries(style),
                          const SizedBox(height: 20),
                          if (_banners.isNotEmpty) ...[
                            _buildBanner(style),
                            const SizedBox(height: 20),
                          ],
                          _buildPlaylistsSection(style),
                          const SizedBox(height: 20),
                          _buildNewSongsSection(style),
                          const SizedBox(height: 20),
                          _buildRankingsSection(style),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  /// 问候头：按时段问候 + 日期，右侧搜索入口。
  Widget _buildHeader(AppStyle style) {
    final now = DateTime.now();
    final greeting = now.hour < 5
        ? '夜深了'
        : now.hour < 11
            ? '早上好'
            : now.hour < 13
                ? '中午好'
                : now.hour < 18
                    ? '下午好'
                    : '晚上好';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final date = '${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(date,
                  style: TextStyle(
                      color: style.textSecondary,
                      fontSize: 13,
                      letterSpacing: 1)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => context.go('/search'),
          icon: Icon(Icons.search, color: style.textPrimary),
          style: IconButton.styleFrom(
            backgroundColor: style.surface,
            side: BorderSide(color: style.surfaceBorder),
          ),
          tooltip: '搜索',
        ),
      ],
    );
  }

  /// Hero 大卡（签名元素）：今日推荐歌单封面作背景，压暗渐变 + 信息层 + 播放 CTA。
  Widget _buildHero(AppStyle style) {
    if (_playlists.isEmpty) return const SizedBox.shrink();
    final p = _playlists.first;
    return GestureDetector(
      onTap: () => context.push('/playlist/${p.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(style.uiRadius + 2),
        child: SizedBox(
          height: 168,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeNetworkImage(url: p.coverImgUrl, fit: BoxFit.cover),
              // 压暗渐变（HTML 渲染器不支持 BackdropFilter，用 scrim 代替模糊）。
              DecoratedBox(decoration: BoxDecoration(gradient: style.scrim)),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: style.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.name.contains('今日推荐') ||
                                      p.name.contains('每日推荐')
                                  ? '每日推荐'
                                  : '编辑精选',
                              style: TextStyle(
                                  color: style.bgBottom,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${fmtCount(p.playCount)} 次播放',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed:
                            _busyHero ? null : () => _playPlaylist(p),
                        style: FilledButton.styleFrom(
                          backgroundColor: style.accent,
                          foregroundColor: style.bgBottom,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        icon: _busyHero
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.play_arrow, size: 20),
                        label: const Text('播放'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 快捷入口：锚点跳到对应板块。
  Widget _buildQuickEntries(AppStyle style) {
    return Row(
      children: [
        Expanded(
          child: _QuickEntry(
            style: style,
            icon: Icons.fiber_new_outlined,
            label: '新歌速递',
            onTap: () => _scrollTo(_newSongsKey),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickEntry(
            style: style,
            icon: Icons.leaderboard_outlined,
            label: '排行榜',
            onTap: () => _scrollTo(_rankKey),
          ),
        ),
      ],
    );
  }

  /// Banner：自动轮播 + 指示器（页面右下角圆点）。
  Widget _buildBanner(AppStyle style) {
    return SizedBox(
      height: 140,
      child: Stack(
        children: [
          PageView(
            controller: _bannerController,
            onPageChanged: (i) {
              setState(() => _bannerPage = i);
              // 用户手动翻页后重新计时，保证停留时间完整。
              _startBannerTimer();
            },
            children: _banners
                .map((b) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(style.uiRadius),
                        child: SafeNetworkImage(
                            url: b.imageUrl, fit: BoxFit.cover),
                      ),
                    ))
                .toList(),
          ),
          Positioned(
            right: 12,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_banners.length, (i) {
                final active = i == _bannerPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? style.accent
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 推荐歌单：横向滚动（跳过 Hero 已展示的第一张）。
  Widget _buildPlaylistsSection(AppStyle style) {
    final rest = _playlists.length > 1 ? _playlists.sublist(1) : <Playlist>[];
    if (rest.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '推荐歌单',
          action: TextButton(
            onPressed: () => _scrollTo(_rankKey),
            child: Text('榜单', style: TextStyle(color: style.accent)),
          ),
        ),
        const SizedBox(height: 12),
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
            scrollbars: false,
          ),
          child: SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: rest.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (c, i) => PlaylistCard(
                playlist: rest[i],
                size: 130,
                onTap: () => context.push('/playlist/${rest[i].id}'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 新歌速递：横向卡片，封面 + 歌名 + 歌手 + 单曲播放按钮。
  Widget _buildNewSongsSection(AppStyle style) {
    if (_newSongs.isEmpty) return const SizedBox.shrink();
    return Column(
      key: _newSongsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: '新歌速递'),
        const SizedBox(height: 12),
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
            scrollbars: false,
          ),
          child: SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _newSongs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (c, i) {
                final s = _newSongs[i];
                return GlassPanel(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      CoverImage(
                          url: s.coverUrl,
                          size: 52,
                          radius: BorderRadius.circular(8)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 108,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: style.textPrimary, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(s.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: style.textSecondary,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.play_circle_fill,
                            color: style.accent, size: 30),
                        tooltip: '播放',
                        onPressed: () async {
                          try {
                            await playSong(ref, s);
                            if (context.mounted) {
                              context.push('/now-playing');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 排行榜：默认只展示前 8 个（官方榜优先），可展开全部；宽屏自适应列数。
  Widget _buildRankingsSection(AppStyle style) {
    final shown =
        _showAllRankings ? _rankings : _rankings.take(8).toList();
    return Column(
      key: _rankKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '排行榜',
          action: _rankings.length > 8
              ? TextButton(
                  onPressed: () => setState(
                      () => _showAllRankings = !_showAllRankings),
                  child: Text(_showAllRankings ? '收起' : '全部',
                      style: TextStyle(color: style.accent)),
                )
              : null,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final columns = w >= 960 ? 4 : (w >= 640 ? 3 : 2);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 64,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: shown.length,
            itemBuilder: (c, i) {
              final r = shown[i];
              return GlassPanel(
                radius: BorderRadius.circular(style.uiRadius),
                child: InkWell(
                  onTap: () => context.push('/playlist/${r.id}'),
                  borderRadius: BorderRadius.circular(style.uiRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        CoverImage(
                            url: r.coverImgUrl,
                            size: 44,
                            radius: BorderRadius.circular(8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: style.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(r.updateFrequency,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: style.textSecondary,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

/// 快捷入口小卡。
class _QuickEntry extends StatelessWidget {
  final AppStyle style;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickEntry({
    required this.style,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(style.uiRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: style.accent),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 16, color: style.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
