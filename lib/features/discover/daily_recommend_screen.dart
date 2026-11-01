import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../core/download.dart';
import '../../core/download_manager.dart';
import '../../core/download_registry.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 行内三点菜单的操作项（与专辑详情页一致）。
enum _RowAction { favorite, download, playNext }

/// 每日推荐页：需登录（平台 /recommend/songs 依赖 cookie）。
/// 未登录引导去登录；已登录拉取当日推荐歌曲。
/// 页面结构与专辑详情页统一：Hero 头（封面作背景）+ 操作条 + 曲目列表，
/// 支持随机播放与「批量下载」（多选模式，交互一致）。
/// 封面图取推荐列表首首歌的专辑封面，加载/失败兜底走 SafeNetworkImage，
/// 与专辑页封面行为完全一致。
class DailyRecommendScreen extends ConsumerStatefulWidget {
  const DailyRecommendScreen({super.key});
  @override
  ConsumerState<DailyRecommendScreen> createState() =>
      _DailyRecommendScreenState();
}

class _DailyRecommendScreenState extends ConsumerState<DailyRecommendScreen> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  // 多选状态：进入多选模式后可勾选曲目并批量下载（与专辑详情页一致）。
  bool _selectMode = false;
  final Set<int> _selectedIds = {};
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loggedIn =
        ref.read(authStateProvider).status == AuthStatus.authenticated;
    if (!loggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final songs = await ref.read(apiProvider).recommendSongs();
      if (mounted) {
        setState(() {
          _songs = songs;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException ? e.userMessage : e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 播放整个推荐列表；[shuffle] 为随机起点。
  /// 立即跳播放页，起播（含随机起点计算）在后台完成。
  Future<void> _playAll({bool shuffle = false}) async {
    if (_busy || _songs.isEmpty) return;
    setState(() => _busy = true);
    final index = shuffle ? Random().nextInt(_songs.length) : 0;
    ref.read(playStartErrorProvider.notifier).state = null;
    try {
      await play.playAndOpen(ref, context, _songs, index);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.userMessage : '播放失败'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2)));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onRowAction(_RowAction a, Song s) async {
    switch (a) {
      case _RowAction.favorite:
        final liked = ref.read(likedSongsProvider.notifier);
        final willFav = !liked.isFavorite(s.id);
        try {
          await liked.toggle(s);
          _toast(willFav ? '已收藏' : '已取消收藏');
        } catch (e) {
          _toast(e is ApiException ? e.userMessage : '收藏失败，请稍后重试');
        }
      case _RowAction.download:
        if (_isDownloaded(s)) {
          _toast('已下载过：${s.name}');
        } else {
          _toast('正在下载：${s.name}');
          final ok = await _downloadSong(s);
          if (mounted) _toast(ok ? '已开始下载：${s.name}' : '下载失败：${s.name}');
        }
      case _RowAction.playNext:
        try {
          await ref.read(audioHandlerProvider).insertNext([s]);
          _toast('已加入下一首播放');
        } catch (_) {
          _toast('操作失败，请稍后重试');
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
            Text(label, style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ],
        ),
      );

  /// 行尾三点菜单：收藏 / 下载 / 下首播放（与专辑详情页一致）。
  Widget _rowTrailing(Song s, AppStyle style) {
    return PopupMenuButton<_RowAction>(
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
        _menuItem(style, Icons.add, '下首播放', _RowAction.playNext),
      ],
    );
  }

  /// 图标按钮（无文字）：用于「随机播放」与「进入多选」。
  Widget _iconButton({
    required AppStyle style,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) =>
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: style.surfaceBorder),
          foregroundColor: style.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius),
          ),
        ),
        child: Icon(icon, size: 20),
      );

  // ── 多选模式 ────────────────────────────────────────────────
  void _enterSelect() => setState(() {
        _selectMode = true;
        _selectedIds.clear();
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });

  void _toggleSelect(int id) => setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
      });

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  /// 是否已下载（同曲且同下载音质档位，换档允许重新下载）。
  bool _isDownloaded(Song s) => ref
      .read(downloadRegistryProvider.notifier)
      .isDownloaded(s.id,
          level: ref.read(playbackSettingsProvider).downloadLevel);

  /// 解析音源并下载单曲到系统下载目录；返回是否成功触发下载。
  /// 已下载（同曲同音质）直接跳过返回 true，避免重复下载。
  /// 下载成功时同步落一份应用内缓存并登记（播放直读本地文件、去重的依据）。
  /// 同时向下载管理器登记任务（进度/状态/时间），供「下载管理」页展示。
  Future<bool> _downloadSong(Song s) async {
    if (_isDownloaded(s)) return true;
    final level = ref.read(playbackSettingsProvider).downloadLevel;
    final url = await ref.read(apiProvider).songUrl(s.id, level: level);
    if (url == null) return false;
    final safe = '${s.artistName} - ${s.name}'
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fileName = '$safe.mp3';
    final mgr = ref.read(downloadManagerProvider.notifier);
    final id = mgr.addTask(fileName);
    Uint8List? cacheBytes;
    final ok = await downloadFile(url, fileName,
        onProgress: (r, t) => mgr.updateProgress(id, r, t),
        onBytes: (b) => cacheBytes = b);
    if (ok) {
      final registry = ref.read(downloadRegistryProvider.notifier);
      final path = await registry.saveCacheFile(s.id, fileName, cacheBytes);
      registry.register(DownloadedSong(
        songId: s.id,
        fileName: fileName,
        localPath: path,
        sizeBytes: cacheBytes?.length ?? 0,
        level: level,
        downloadedAt: DateTime.now(),
        song: s,
      ));
    }
    mgr.complete(id, ok);
    return ok;
  }

  Future<void> _batchDownload() async {
    final sel = _songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (sel.isEmpty) return;
    setState(() => _downloading = true);
    int ok = 0;
    int skipped = 0;
    for (final s in sel) {
      if (_isDownloaded(s)) {
        skipped++; // 已下载：自动跳过，不计入下载。
        continue;
      }
      if (await _downloadSong(s)) ok++;
    }
    if (mounted) setState(() => _downloading = false);
    _toast(skipped > 0
        ? '已下载 $ok 首，跳过已下载 $skipped 首'
        : '已下载 $ok / ${sel.length} 首');
  }

  Future<void> _batchFavorite() async {
    final sel = _songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (sel.isEmpty) return;
    final liked = ref.read(likedSongsProvider.notifier);
    int ok = 0;
    for (final s in sel) {
      if (!liked.isFavorite(s.id)) {
        try {
          await liked.toggle(s);
          ok++;
        } catch (_) {
          // 单首失败不影响其余。
        }
      }
    }
    _toast('已收藏 $ok 首');
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final loggedIn =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          child: _selectMode
              ? AppContentColumn(child: _buildSelectMode(style))
              : AppContentColumn(child: _buildContent(style, loggedIn)),
        ),
      ),
    );
  }

  /// 非多选态的页面主体：登录引导 / 加载 / 错误 / 曲目列表。
  /// 结构与专辑详情页一致：Hero 头 + 操作条 + 列表，单曲点按播放。
  Widget _buildContent(AppStyle style, bool loggedIn) {
    if (!loggedIn) return _buildLoginHint(style);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _songs.isEmpty) {
      final sp = AppSpacing.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: style.textSecondary)),
            SizedBox(height: sp.block),
            OutlinedButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh, color: style.textSecondary),
              label: Text('重试',
                  style: TextStyle(color: style.textSecondary)),
            ),
          ],
        ),
      );
    }
    return _buildBody(style);
  }

  /// 页面主体：Hero 头（封面背景）+ 操作条 + 曲目列表（与专辑详情页一致）。
  Widget _buildBody(AppStyle style) {
    final sp = AppSpacing.of(context);
    return CustomScrollView(
      slivers: [
        // Hero 头：封面作背景 + 压暗渐变，浮动返回按钮。
        SliverToBoxAdapter(
          child:
              _songs.isEmpty ? const SizedBox(height: 120) : _buildHero(style),
        ),
        // 操作条：播放全部 + 随机播放（纯图标）+ 进入多选。
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                sp.gutter, sp.block, sp.gutter, sp.inline),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _playAll(),
                    style: FilledButton.styleFrom(
                      backgroundColor: style.accent,
                      foregroundColor: style.bgBottom,
                    ),
                    icon: _busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: style.bgBottom))
                        : const Icon(Icons.play_arrow, size: 20),
                    label: const Text('播放全部'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _iconButton(
                  style: style,
                  icon: Icons.shuffle,
                  tooltip: '随机播放',
                  onPressed: _busy ? null : () => _playAll(shuffle: true),
                ),
                const SizedBox(width: AppSpacing.md),
                _iconButton(
                  style: style,
                  icon: Icons.checklist,
                  tooltip: '多选下载',
                  onPressed: _enterSelect,
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.all(sp.inline),
                child: Text(_error!,
                    style:
                        TextStyle(color: Colors.redAccent, fontSize: 13))),
          ),
        // 曲目列表。
        if (_songs.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
                icon: Icons.music_off_outlined,
                title: '今日暂无推荐',
                hint: '没有可播放的曲目'),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(
                horizontal: sp.gutter, vertical: sp.inline),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) => SongTile(
                  song: _songs[i],
                  index: i + 1,
                  onTap: () => play.playAndOpen(ref, context, _songs, i),
                  trailing: _rowTrailing(_songs[i], style),
                ),
                childCount: _songs.length,
              ),
            ),
          ),
      ],
    );
  }

  /// Hero 头：以推荐列表首首歌的专辑封面为背景 + 压暗渐变，
  /// 左上浮动返回按钮，底部信息层放 88x88 封面缩略 + 标题 + 曲目数。
  /// 封面加载失败由 SafeNetworkImage 统一兜底为本地占位图（与专辑页一致）。
  Widget _buildHero(AppStyle style) {
    final sp = AppSpacing.of(context);
    final cover = _songs.first.coverUrl;
    final now = DateTime.now();
    return Stack(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeNetworkImage(url: cover, fit: BoxFit.cover),
              DecoratedBox(
                  decoration: BoxDecoration(gradient: style.scrim)),
            ],
          ),
        ),
        Positioned(
          top: 4,
          left: 4,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        // 信息层：封面缩略 + 标题 + 曲目数/更新日期。
        Positioned(
          left: sp.gutter,
          right: sp.gutter,
          bottom: sp.block,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SafeNetworkImage(
                    url: cover,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover),
              ),
              SizedBox(width: sp.block),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每日推荐',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.3)),
                    SizedBox(height: sp.inline),
                    Text(
                        '${_songs.length} 首 · ${now.month}月${now.day}日更新',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 多选模式界面 ────────────────────────────────────────────
  Widget _buildSelectMode(AppStyle style) {
    final sp = AppSpacing.of(context);
    return Column(
      children: [
        _buildSelectAppBar(style),
        Divider(height: 1, thickness: 1, color: style.surfaceBorder),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: sp.gutter, vertical: sp.inline),
            itemCount: _songs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.xxs),
            itemBuilder: (c, i) {
              final s = _songs[i];
              final sel = _selectedIds.contains(s.id);
              return _SelectTile(
                style: style,
                song: s,
                selected: sel,
                onTap: () => _toggleSelect(s.id),
              );
            },
          ),
        ),
        _buildSelectActions(style),
      ],
    );
  }

  /// 多选模式顶部条：退出 + 已选择 N 项 + 全选（与专辑页一致，配色走主题色，
  /// 不依赖深色 Hero 背景，浅色主题下也清晰）。
  Widget _buildSelectAppBar(AppStyle style) {
    final allSelected =
        _songs.isNotEmpty && _selectedIds.length == _songs.length;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: style.textPrimary),
            onPressed: _exitSelect,
            tooltip: '退出选择',
          ),
          Expanded(
            child: Text(
              '已选择 ${_selectedIds.length} 项',
              style: TextStyle(
                  color: style.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              if (allSelected) {
                _selectedIds.clear();
              } else {
                _selectedIds.addAll(_songs.map((s) => s.id));
              }
            }),
            child: Text(allSelected ? '取消全选' : '全选',
                style: TextStyle(color: style.accent, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _SelectTile({
    required AppStyle style,
    required Song song,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(style.uiRadius / 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.micro, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? style.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(style.uiRadius / 2),
        ),
        child: Row(
          children: [
            _checkBox(selected, style),
            SizedBox(width: AppSpacing.inline),
            CoverImage(
                url: song.coverUrl,
                size: 44,
                radius: BorderRadius.circular(style.uiRadius / 2)),
            SizedBox(width: AppSpacing.inline),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected ? style.accent : style.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(song.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: style.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkBox(bool selected, AppStyle style) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? style.accent : Colors.transparent,
          border: Border.all(
            color: selected
                ? style.accent
                : style.textSecondary.withValues(alpha: 0.6),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: selected
            ? Icon(Icons.check, size: 16, color: style.bgBottom)
            : null,
      );

  /// 多选底部操作条：收藏 + 批量下载（无勾选时禁用）。
  Widget _buildSelectActions(AppStyle style) {
    final sp = AppSpacing.of(context);
    final hasSel = _selectedIds.isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(sp.gutter, sp.inline, sp.gutter, sp.block),
      decoration: BoxDecoration(
        color: Color.alphaBlend(style.surface, style.bgBottom),
        border: Border(top: BorderSide(color: style.surfaceBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasSel && !_downloading ? _batchFavorite : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: style.surfaceBorder),
                foregroundColor: style.textPrimary,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.uiRadius),
                ),
              ),
              icon: const Icon(Icons.favorite_border, size: 18),
              label: const Text('收藏'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              onPressed: hasSel && !_downloading ? _batchDownload : null,
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.uiRadius),
                ),
              ),
              icon: _downloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: style.bgBottom))
                  : const Icon(Icons.download_outlined, size: 18),
              label: Text(_downloading ? '下载中…' : '下载'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHint(AppStyle style) {
    final sp = AppSpacing.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.recommend_outlined,
                size: 56, color: style.textSecondary.withValues(alpha: 0.7)),
            SizedBox(height: sp.block),
            Text('每日推荐需要登录',
                style: TextStyle(color: style.textPrimary, fontSize: 16)),
            const SizedBox(height: AppSpacing.micro),
            Text('登录后为你精选当日好歌',
                style: TextStyle(color: style.textSecondary, fontSize: 12)),
            SizedBox(height: sp.block),
            FilledButton.icon(
              onPressed: () => context.push('/login'),
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: 10),
              ),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
