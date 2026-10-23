import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/constants.dart';
import '../../core/local_store.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 上次命中的雷达歌单缓存：两个接口都刷不到时回退使用，保证「私人雷达」
/// 在个人专属板块内「刷不出也不消失」（跨发现页重建仍有效，应用内常驻）。
/// 同时持久化到 LocalStore，应用重启后首进也能显示（见 _loadRadarCache）。
Playlist? _radarCache;

/// LocalStore 中雷达歌单缓存键。
const String kRadarCacheKey = 'radar_playlist_cache';

/// 横向列表里歌单卡的封面边长（同时决定整排卡片宽度与列表容器高度）。
/// 随断点放大，宽屏一屏能看到更多内容；卡片间距仍由 `AppSpacing` 统一。
double _playlistCardSize(AppSpacingMetrics sp) =>
    sp.isCompact ? 130 : (sp.isMedium ? 146 : 158);

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

  /// 个人专属板块数据源（/recommend/resource，需登录），含真实推荐歌单。
  List<Playlist> _recommendPlaylists = [];

  /// 固定钉在个人专属的「私人雷达」歌单（去重后），未命中则为 null。
  Playlist? _pinnedRadar;

  /// 登录态缓存（来自 authStateProvider），控制个人专属板块可见性。
  bool _loggedIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRadarCache();
    _load();
  }

  /// 启动即从 LocalStore 读回上次持久化的雷达歌单，保证首进（含重启后）
  /// 即使接口没返回也能显示，不依赖当次接口命中。
  void _loadRadarCache() {
    final raw = LocalStore.instance.getString(kRadarCacheKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _radarCache = Playlist(
        id: m['id'] as int,
        name: m['name'] as String? ?? '私人雷达',
        coverImgUrl: m['cover'] as String? ?? '',
        trackCount: m['trackCount'] as int? ?? 0,
        playCount: m['playCount'] as int? ?? 0,
      );
    } catch (_) {
      // 数据损坏：忽略，相当于无缓存。
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final loggedIn =
          ref.read(authStateProvider).status == AuthStatus.authenticated;
      final results = await Future.wait([
        api.personalizedPlaylists(),
        api.rankings(),
        api.newSongs(),
        // 仅登录态拉 /recommend/resource（个人专属板块数据源），
        // 游客态跳过，避免 301 触发统一登出；接口失败由调用方容错。
        if (loggedIn)
          api.recommendPlaylists()
        else
          Future.value(const <Playlist>[]),
      ]);
      if (!mounted) return;
      // 注：原本为 Hero / 推荐歌单区「每日推荐」置顶的逻辑已迁到「个人专属」板块，
      // 这里 _playlists 尽量保留 /personalized 原始顺序（首张即编辑精选），
      // 去重导致为空时回退全量，见下方 playlists 的推导。
      final recommend = results[3] as List<Playlist>;
      // 「私人雷达」等雷达类歌单固定归属「个人专属」板块：
      // 1) 从推荐歌单（/personalized）剔除已在个人专属出现的歌单，及雷达类歌单；
      // 2) 从两个接口里挑出雷达歌单（优先用 /recommend/resource 的真实项），
      //    去重后固定钉入个人专属，避免两处重复或都缺失。
      final recommendIds = recommend.map((p) => p.id).toSet();
      final rawPlaylists = results[0] as List<Playlist>;
      // 去重只影响「推荐歌单」的展示项，绝不能把整个板块清空：
      // 「推荐歌单」标题右侧的「更多」是进入 /all-playlists 的唯一入口
      // （见 _buildPlaylistsSection），板块缺席 = 入口消失。登录态下
      // /personalized 与 /recommend/resource 内容高度重合，按 id 去重可能
      // 清空列表，故去重后为空时逐级回退全量，保证「只要接口有数据就非空」。
      final deduped = rawPlaylists
          .where((p) => !recommendIds.contains(p.id) && !p.name.contains('雷达'))
          .toList();
      final radarFree =
          rawPlaylists.where((p) => !p.name.contains('雷达')).toList();
      final playlists = deduped.isNotEmpty
          ? deduped
          : (radarFree.isNotEmpty ? radarFree : rawPlaylists);
      Playlist? radar;
      for (final p in recommend) {
        if (p.name.contains('雷达')) {
          radar = p;
          break;
        }
      }
      if (radar == null) {
        for (final p in rawPlaylists) {
          if (p.name.contains('雷达')) {
            radar = p;
            break;
          }
        }
      }
      // 命中则刷新缓存（内存 + 本地持久化）；两个接口都刷不到时回退到
      // 上次命中的雷达歌单，保证「刷不出也不消失」。/recommend/resource
      // 可能返回多条同名「私人雷达」（同名单不同 id），钉入一条后按同名
      // 全部剔除，只留一张。
      if (radar != null) {
        _radarCache = radar;
        LocalStore.instance.setString(
            kRadarCacheKey,
            jsonEncode({
              'id': radar.id,
              'name': radar.name,
              'cover': radar.coverImgUrl,
              'trackCount': radar.trackCount,
              'playCount': radar.playCount,
            }));
      }
      final effectiveRadar = radar ?? _radarCache;
      final recommendClean = effectiveRadar != null
          ? recommend.where((p) => p.name != effectiveRadar!.name).toList()
          : recommend;
      setState(() {
        _playlists = playlists;
        _recommendPlaylists = recommendClean;
        _pinnedRadar = effectiveRadar;
        _loggedIn = loggedIn;
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
    // 每日推荐合成入口：直接起播每日推荐歌曲（与「个人专属」板块一致）。
    if (p.id == kDailyRecommendId) {
      _playDailyRecommend();
      return;
    }
    setState(() => _busyHero = true);
    context.push('/now-playing');
    try {
      final detail = await ref.read(apiProvider).playlistDetail(p.id);
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

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    // 登录态变化（游客 → 已登录）时重新加载，使「个人专属」板块即时出现。
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        _load();
      }
    });
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
                          SizedBox(height: sp.block),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon:
                                Icon(Icons.refresh, color: style.textSecondary),
                            label: Text('重试',
                                style: TextStyle(color: style.textSecondary)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: AppContentColumn(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: sp.listPadding,
                          children: [
                            _buildHeader(style),
                            // 每个板块自带上边距（AppSection 承担），因此板块缺席
                            // （游客态 / 空数据）时不会残留空档，相邻留白恒定。
                            _buildHero(style),
                            _buildPersonalSection(style),
                            _buildPlaylistsSection(style),
                            _buildNewSongsSection(style),
                            _buildRankingsSection(style),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  /// 板块标题右侧动作按钮的统一样式：高度压到标题行内（24），不撑高标题行；
  /// 字号与卡片标题一致（12.5），保证「更多 / 全部」与板块标题同级。
  ButtonStyle _sectionActionStyle(AppStyle style) => TextButton.styleFrom(
        foregroundColor: style.accent,
        minimumSize: const Size(0, 24),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      );

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
              const SizedBox(height: AppSpacing.micro),
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
  /// 高度随断点放大，宽屏下信息层不至于被压扁。
  Widget _buildHero(AppStyle style) {
    if (_playlists.isEmpty) return const SizedBox.shrink();
    final sp = AppSpacing.of(context);
    final p = _playlists.first;
    final double height = sp.isCompact ? 168 : (sp.isMedium ? 200 : 224);
    return AppSection(
      child: GestureDetector(
        onTap: () => p.id == kDailyRecommendId
            ? context.push('/daily-recommend')
            : context.push('/playlist/${p.id}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(style.uiRadius + 2),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SafeNetworkImage(url: p.coverImgUrl, fit: BoxFit.cover),
                // 压暗渐变（HTML 渲染器不支持 BackdropFilter，用 scrim 代替模糊）。
                DecoratedBox(decoration: BoxDecoration(gradient: style.scrim)),
                Positioned(
                  left: sp.gutter,
                  right: sp.gutter,
                  bottom: sp.block,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: style.accent,
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.micro),
                              ),
                              child: Text(
                                '编辑精选',
                                style: TextStyle(
                                    color: style.bgBottom,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            SizedBox(height: sp.inline),
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: AppSpacing.xxs),
                            Text('${fmtCount(p.playCount)} 次播放',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      SizedBox(width: sp.block),
                      SizedBox(
                        height: 40,
                        child: FilledButton.icon(
                          onPressed: _busyHero ? null : () => _playPlaylist(p),
                          style: FilledButton.styleFrom(
                            backgroundColor: style.accent,
                            foregroundColor: style.bgBottom,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                          ),
                          icon: _busyHero
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
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
      ),
    );
  }

  /// 推荐歌单：横向滚动（去重后的 /personalized，去重后为空则回退全量）。
  /// 只要 /personalized 有数据板块就在——标题右侧「更多」是进入
  /// /all-playlists 的唯一入口，板块不能因为去重而缺席。
  Widget _buildPlaylistsSection(AppStyle style) {
    if (_playlists.isEmpty) return const SizedBox.shrink();
    final size = _playlistCardSize(AppSpacing.of(context));
    return AppSection(
      title: '推荐歌单',
      action: TextButton(
        onPressed: () => context.push('/all-playlists'),
        style: _sectionActionStyle(style),
        child: const Text('更多'),
      ),
      child: AppHorizontalStrip(
        // 高度与卡片实际高度一致，避免列表容器下方出现一条死白
        //（那条死白会让本处的板块间距看起来比别处宽）。
        height: PlaylistCard.cardHeight(size),
        itemCount: _playlists.length,
        itemBuilder: (c, i) => PlaylistCard(
          playlist: _playlists[i],
          size: size,
          onTap: () => context.push('/playlist/${_playlists[i].id}'),
        ),
      ),
    );
  }

  /// 个人专属：仅登录用户展示。横向滑动，第一张固定「每日推荐」（文字设计封面，
  /// 点击直接起播），其余为 /recommend/resource 返回的每日推荐歌单（点击进歌单详情页）。
  /// 已登录但推荐接口为空/失败时，仅保留「每日推荐」单卡。
  Widget _buildPersonalSection(AppStyle style) {
    if (!_loggedIn) return const SizedBox.shrink();
    final sp = AppSpacing.of(context);
    final size = _playlistCardSize(sp);
    final items = <Playlist>[
      const Playlist(
        id: kDailyRecommendId,
        name: '每日推荐',
        coverImgUrl: '',
        trackCount: 0,
        playCount: 0,
      ),
      if (_pinnedRadar != null) _pinnedRadar!,
      ..._recommendPlaylists,
    ];
    return AppSection(
      title: '个人专属',
      child: AppHorizontalStrip(
        // 与歌单卡同高：每日推荐卡也补了说明行，一排卡片底边齐平。
        height: PlaylistCard.cardHeight(size),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final p = items[i];
          if (p.id == kDailyRecommendId) {
            return _buildDailyRecommendTile(style, size);
          }
          return PlaylistCard(
            playlist: p,
            size: size,
            onTap: () => context.push('/playlist/${p.id}'),
          );
        },
      ),
    );
  }

  /// 「每日推荐」文字封面（签名元素）：强调色渐变打底，大号「每日/推荐」
  /// 错位排版为主角，左上角当天日期小字（每日更新语义），右下角低透明度
  /// 唱片圆环做质感。边长与同排歌单卡一致（[size]），底边齐平。
  Widget _buildDailyRecommendTile(AppStyle style, double size) {
    final now = DateTime.now();
    final deep = Color.lerp(style.accent, Colors.black, 0.42)!;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    Widget ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: alpha), width: 1.5)));
    return GestureDetector(
      onTap: _playDailyRecommend,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(style.uiRadius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [style.accent, deep],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(style.uiRadius),
                child: Stack(
                  children: [
                    // 唱片圆环：右下角探出画布，只留弧线，克制不抢主体。
                    Positioned(right: -38, bottom: -52, child: ring(116, 0.20)),
                    Positioned(right: -10, bottom: -24, child: ring(64, 0.14)),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${now.month}.${now.day.toString().padLeft(2, '0')} '
                            '周${weekdays[now.weekday - 1]}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1),
                          ),
                          const Spacer(),
                          Text('每日',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                  letterSpacing: 3)),
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text('推荐',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                    letterSpacing: 3)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 说明行：与普通歌单卡的两行名称等高，使一排卡片底边齐平。
            const SizedBox(height: PlaylistCard.coverGap),
            SizedBox(
              height: PlaylistCard.titleBlockHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('每日更新',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 12.5,
                          height: 1.3)),
                  Text('为你挑的专属好歌',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: style.textSecondary,
                          fontSize: 11,
                          height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 每日推荐起播：拉 /recommend/songs → 进播放页并起播（与 Hero 播放按钮同款忙锁）。
  Future<void> _playDailyRecommend() async {
    if (_busyHero) return;
    setState(() => _busyHero = true);
    context.push('/now-playing');
    try {
      final songs = await ref.read(apiProvider).recommendSongs();
      await play.playQueue(ref, songs, 0);
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

  /// 新歌速递：横向卡片，封面 + 歌名 + 歌手 + 单曲播放按钮。
  Widget _buildNewSongsSection(AppStyle style) {
    if (_newSongs.isEmpty) return const SizedBox.shrink();
    final sp = AppSpacing.of(context);
    // 卡片高 = 上下内边距 × 2 + 封面 52，与容器高度严格相等（不留死白）。
    final pad = sp.inline;
    return AppSection(
      title: '新歌速递',
      child: AppHorizontalStrip(
        height: pad * 2 + 52,
        itemCount: _newSongs.length,
        itemBuilder: (c, i) {
          final s = _newSongs[i];
          return GlassPanel(
            padding: EdgeInsets.all(pad),
            child: Row(
              children: [
                CoverImage(
                    url: s.coverUrl,
                    size: 52,
                    radius: BorderRadius.circular(pad)),
                SizedBox(width: sp.inline),
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
                      const SizedBox(height: AppSpacing.xxs),
                      Text(s.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: style.textSecondary, fontSize: 11)),
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
    );
  }

  /// 排行榜：全部展示（官方榜优先）；列数与间距随断点自适应。
  Widget _buildRankingsSection(AppStyle style) {
    final shown = _rankings;
    final sp = AppSpacing.of(context);
    return AppSection(
      title: '排行榜',
      child: LayoutBuilder(builder: (context, constraints) {
        // 列数走全应用共用的断点推导，卡片正好填满列宽，右侧不剩空档。
        final columns = sp.gridColumns(constraints.maxWidth, minCard: 190);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            // 行高 = 封面 44 + 上下留白 8，网格更紧凑。
            mainAxisExtent: 60,
            // 两个方向的单元格间距统一取 inline，避免网格内出现两种节奏。
            crossAxisSpacing: sp.inline,
            mainAxisSpacing: sp.inline,
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
                  padding: EdgeInsets.symmetric(horizontal: sp.inline),
                  child: Row(
                    children: [
                      CoverImage(
                          url: r.coverImgUrl,
                          size: 44,
                          radius: BorderRadius.circular(sp.inline)),
                      SizedBox(width: sp.inline),
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
                            const SizedBox(height: AppSpacing.xxs),
                            Text(r.updateFrequency,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: style.textSecondary, fontSize: 11)),
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
    );
  }
}
