import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/download_queue.dart';
import '../../core/download_registry.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/add_to_playlist_sheet.dart';
import '../player/play_utils.dart' as play;

/// 专辑详情页。
///
/// 骨架与交互参考歌单页（Hero → 操作条 → 曲目列表，返回 / 播放全部 /
/// 随机播放 / 行内三点菜单），但 Hero 信息层用专辑的「艺人 · 发行」
/// 而非歌单的「播放量 · 曲目数」。曲目号是真实序列，因此列表用
/// 01/02/03 编号（SongTile.index），而非装饰性序号。
///
/// 结构红只用于眉标竖块、分区标题竖块与「播放全部」主操作，
/// 与全应用「结构红 = 当前 / 主操作」的语义一致。
class AlbumDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const AlbumDetailScreen({super.key, required this.id});

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

/// 行内三点菜单的操作项。
enum _RowAction { favorite, download, addToPlaylist, playNext }

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  AlbumInfo? _meta;
  List<Song> _songs = [];
  bool _loading = true;
  bool _busy = false;
  bool _descExpanded = false;
  String? _error;

  int get _albumId => int.tryParse(widget.id) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 重试时回到 loading；首次由 initState 进入，无需额外 setState。
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await ref.read(apiProvider).albumDetail(_albumId);
      _meta = detail.album;
      _songs = detail.songs;
    } catch (e) {
      _error = e is ApiException ? e.userMessage : e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 整张专辑按顺序起播（随机播放只换起点，队列仍是完整曲目表）。
  Future<void> _playAll({bool shuffle = false}) async {
    if (_songs.isEmpty || _busy) return;
    setState(() => _busy = true);
    final index = shuffle ? Random().nextInt(_songs.length) : 0;
    await play.playAndOpen(ref, context, _songs, index);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onTap(Song s) async {
    final index = _songs.indexOf(s);
    await play.playAndOpen(ref, context, _songs, index < 0 ? 0 : index);
  }

  Future<void> _onRowAction(_RowAction a, Song s) async {
    switch (a) {
      case _RowAction.favorite:
        final liked = ref.read(likedSongsProvider.notifier);
        final willFav = !liked.isFavorite(s.id);
        try {
          await liked.toggle(s);
          if (mounted) {
            showAppToast(context, ref, willFav ? '已收藏' : '已取消收藏');
          }
        } catch (e) {
          if (mounted) showErrorToast(context, ref, e);
        }
      case _RowAction.download:
        final downloaded = ref
            .read(downloadRegistryProvider.notifier)
            .isDownloaded(s.id,
                level: ref.read(playbackSettingsProvider).downloadLevel);
        if (downloaded) {
          showAppToast(context, ref, '已下载过：${s.name}');
          return;
        }
        showAppToast(context, ref, '正在下载：${s.name}');
        final ok = await ref.read(songDownloadExecutorProvider)(s);
        if (!mounted) return;
        showAppToast(context, ref, ok ? '已开始下载：${s.name}' : '下载失败：${s.name}',
            success: ok);
      case _RowAction.addToPlaylist:
        await showAddToPlaylistSheet(context, ref, [s]);
      case _RowAction.playNext:
        try {
          await ref.read(audioHandlerProvider).insertNext([s]);
          if (mounted) showAppToast(context, ref, '已加入下一首播放');
        } catch (e) {
          if (mounted) showErrorToast(context, ref, e);
        }
    }
  }

  PopupMenuItem<_RowAction> _menuItem(
    AppStyle style,
    IconData icon,
    String label,
    _RowAction value,
  ) =>
      PopupMenuItem<_RowAction>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 19, color: style.textPrimary),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ],
        ),
      );

  Widget _rowTrailing(Song s, AppStyle style) => PopupMenuButton<_RowAction>(
        icon: Icon(Icons.more_vert, color: style.textSecondary, size: 20),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        color: Color.alphaBlend(style.surface, style.bgBottom),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius),
          side: BorderSide(color: style.surfaceBorder),
        ),
        onSelected: (a) => _onRowAction(a, s),
        itemBuilder: (c) => [
          _menuItem(style, Icons.favorite_border, '收藏', _RowAction.favorite),
          _menuItem(style, Icons.download_outlined, '下载', _RowAction.download),
          _menuItem(style, Icons.library_add_rounded, '添加到歌单',
              _RowAction.addToPlaylist),
          _menuItem(style, Icons.add, '下首播放', _RowAction.playNext),
        ],
      );

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
              : _error != null && _meta == null
                  ? _errorView(style)
                  : _content(style),
        ),
      ),
    );
  }

  Widget _errorView(AppStyle style) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: style.textSecondary, fontSize: 13)),
            ),
            SizedBox(height: AppSpacing.of(context).block),
            OutlinedButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh, color: style.textSecondary),
              label: Text('重试', style: TextStyle(color: style.textSecondary)),
            ),
          ],
        ),
      );

  /// 页面唯一的一次编排动效：整体淡入 + 上移 12pt。
  /// 系统开启「减少动态效果」时由 AMTokens 把时长归零，退化为瞬时呈现。
  Widget _content(AppStyle style) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AMTokens.revealDuration(context),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, (1 - t) * 12), child: child),
        ),
        child: AppContentColumn(
          child: CustomScrollView(
            slivers: [
              _hero(style),
              _actions(style),
              if (_meta != null && _meta!.description.trim().isNotEmpty)
                _description(style),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.of(context).gutter),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ),
                ),
              _tracksHeader(style),
              if (_songs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                      icon: Icons.album_outlined,
                      title: '这张专辑暂无曲目',
                      hint: '暂时没有可播放的歌曲'),
                )
              else
                _tracks(style),
            ],
          ),
        ),
      );

  /// Hero：封面压暗铺底 + 返回 + 眉标 / 专辑名 / 艺人·发行。
  /// 与歌单页同高同结构，但信息层不写「播放量 · 曲目数」。
  Widget _hero(AppStyle style) {
    final sp = AppSpacing.of(context);
    final meta = _meta;
    return SliverToBoxAdapter(
      child: meta == null
          ? const SizedBox(height: 120)
          : Stack(
              children: [
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 背景虚化成氛围层，与左下角清晰缩略封面拉开层次，
                      // 避免同一张封面在 Hero 里重复出现两次。
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                            sigmaX: AMTokens.backdropBlur,
                            sigmaY: AMTokens.backdropBlur),
                        child: SafeNetworkImage(
                            url: meta.picUrl, fit: BoxFit.cover),
                      ),
                      DecoratedBox(
                          decoration: BoxDecoration(gradient: style.scrim)),
                      // 额外中性压暗：浅色封面下白字仍可读。
                      Container(color: Colors.black.withValues(alpha: 0.18)),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.30)),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: sp.gutter,
                  right: sp.gutter,
                  bottom: sp.block,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AMTokens.radiusArt),
                        child: SafeNetworkImage(
                            url: meta.picUrl,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover),
                      ),
                      SizedBox(width: sp.block),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 眉标：结构红竖块编码「这是一张专辑」。
                            Row(
                              children: [
                                Container(
                                    width: AMTokens.signalIndicator,
                                    height: 12,
                                    color: AMTokens.signal),
                                const SizedBox(width: 6),
                                Text(
                                  meta.subType.isEmpty
                                      ? '专辑'
                                      : meta.subType.toUpperCase(),
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(meta.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                    height: 1.2)),
                            const SizedBox(height: 6),
                            Text(
                                '${meta.artistName.isEmpty ? '未知艺人' : meta.artistName} · ${meta.publishLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 操作条：与歌单页一致的「播放全部 + 随机播放」。
  /// 专辑聚焦整轨收听，不引入歌单页的批量下载多选模式。
  Widget _actions(AppStyle style) {
    final sp = AppSpacing.of(context);
    final enabled = !_busy && _songs.isNotEmpty;
    return SliverToBoxAdapter(
      child: Padding(
        // 顶部留白承接 Hero（规格条移除后由操作条接管这段间距）。
        padding: EdgeInsets.fromLTRB(sp.gutter, sp.block, sp.gutter, sp.block),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: enabled ? () => _playAll() : null,
                style: FilledButton.styleFrom(
                  backgroundColor: style.accent,
                  foregroundColor: AMTokens.signalOn,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(style.uiRadius)),
                ),
                icon: _busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AMTokens.signalOn))
                    : const Icon(Icons.play_arrow, size: 20),
                label: const Text('播放全部'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton(
              onPressed: enabled ? () => _playAll(shuffle: true) : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: style.surfaceBorder),
                foregroundColor: style.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(style.uiRadius)),
              ),
              child: const Icon(Icons.shuffle, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// 专辑简介：默认 3 行，长文案才提供展开 / 收起；文案为空时整块缺席。
  Widget _description(AppStyle style) {
    final sp = AppSpacing.of(context);
    final text = _meta!.description.trim();
    // 短简介本来就完整可见，不摆一个点了没反应的「展开全部」。
    final collapsible = text.length > 90;
    void toggle() {
      if (!collapsible) return;
      setState(() => _descExpanded = !_descExpanded);
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(sp.gutter, 0, sp.gutter, sp.block),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: AMTokens.signalBar,
                    height: 16,
                    color: AMTokens.signal),
                const SizedBox(width: 8),
                Text('专辑简介',
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: collapsible ? toggle : null,
              child: Text(
                text,
                maxLines: _descExpanded ? 12 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: style.textSecondary, fontSize: 12.5, height: 1.5),
              ),
            ),
            if (collapsible) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: toggle,
                child: Text(_descExpanded ? '收起' : '展开全部',
                    style: TextStyle(
                        color: style.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tracksHeader(AppStyle style) {
    final sp = AppSpacing.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(sp.gutter, 0, sp.gutter, sp.inline),
        child: Row(
          children: [
            Container(
                width: AMTokens.signalBar, height: 18, color: AMTokens.signal),
            const SizedBox(width: 8),
            Text('曲目',
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AMTokens.trackingSection)),
            const SizedBox(width: 8),
            Text('${_songs.length}',
                style: TextStyle(
                    color: style.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }

  Widget _tracks(AppStyle style) {
    final sp = AppSpacing.of(context);
    return SliverPadding(
      // 列表末尾留白：专辑页是 Shell 外全屏页，最后一行不贴屏幕底边。
      padding:
          EdgeInsets.fromLTRB(sp.gutter, sp.inline, sp.gutter, sp.block + 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (c, i) => SongTile(
            song: _songs[i],
            index: i + 1,
            highlightTopRank: false,
            durationMs: _songs[i].duration,
            onTap: () => _onTap(_songs[i]),
            trailing: _rowTrailing(_songs[i], style),
          ),
          childCount: _songs.length,
        ),
      ),
    );
  }
}
