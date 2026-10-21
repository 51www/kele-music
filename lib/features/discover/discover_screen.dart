import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  List<Playlist> _playlists = [];
  List<Ranking> _rankings = [];
  List<Song> _newSongs = [];
  bool _loading = true;
  bool _busyHero = false;
  bool _showAllRankings = false;
  /// 每日推荐已置顶（Hero 徽章用）：/recommend/resource 需登录，游客态降级。
  bool _dailyFirst = false;
  String? _error;

  // 快捷入口锚点。
  final _newSongsKey = GlobalKey();
  final _rankKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.personalizedPlaylists(),
        api.rankings(),
        api.newSongs(),
        // 每日推荐需登录，游客/接口失败时静默降级为空。
        api.recommendPlaylists().catchError(
            (Object _) => const <Playlist>[]),
      ]);
      if (!mounted) return;
      final playlists = [...results[0] as List<Playlist>];
      // 「今日推荐歌单」固定置顶（名称含「今日推荐/每日推荐」），其余保持原顺序。
      final todayIdx = playlists.indexWhere(
          (p) => p.name.contains('今日推荐') || p.name.contains('每日推荐'));
      if (todayIdx > 0) {
        playlists.insert(0, playlists.removeAt(todayIdx));
      }
      // 每日推荐歌单放在第一个位置（登录态有效时），Hero 大卡展示它。
      final daily = results[3] as List<Playlist>;
      var dailyFirst = false;
      if (daily.isNotEmpty) {
        playlists.removeWhere((p) => p.id == daily.first.id);
        playlists.insert(0, daily.first);
        dailyFirst = true;
      }
      setState(() {
        _playlists = playlists;
        _dailyFirst = dailyFirst;
        _rankings = results[1] as List<Ranking>;
        _newSongs = results[2] as List<Song>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Hero 大卡 CTA：立即跳播放页，歌单详情拉取与起播在后台完成。
  Future<void> _playPlaylist(Playlist p) async {
    if (_busyHero) return;
    setState(() => _busyHero = true);
    context.push('/now-playing');
    try {
      final detail =
          await ref.read(apiProvider).playlistDetail(p.id);
      await play.playQueue(ref, detail.tracks, 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.userMessage : e.toString()),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2)));
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
                              _dailyFirst ||
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
            onPressed: () => context.push('/all-playlists'),
            child: Text('更多', style: TextStyle(color: style.accent)),
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
                        onPressed: () => play.playAndOpen(ref, context, [s], 0),
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
