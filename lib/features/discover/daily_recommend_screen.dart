import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../core/download.dart';
import '../../core/download_manager.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 每日推荐页：需登录（平台 /recommend/songs 依赖 cookie）。
/// 未登录引导去登录；已登录拉取当日推荐歌曲，支持「播放全部」与「批量下载」
/// （多选模式，交互与专辑详情页一致）。
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

  Future<void> _playAll() async {
    if (_busy || _songs.isEmpty) return;
    setState(() => _busy = true);
    ref.read(playStartErrorProvider.notifier).state = null;
    context.push('/now-playing');
    try {
      await play.playQueue(ref, _songs, 0);
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

  /// 解析音源并下载单曲到系统下载目录；返回是否成功触发下载。
  /// 同时向下载管理器登记任务（进度/状态/时间），供「下载管理」页展示。
  Future<bool> _downloadSong(Song s) async {
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
    final ok = await downloadFile(url, fileName,
        onProgress: (r, t) => mgr.updateProgress(id, r, t));
    mgr.complete(id, ok);
    return ok;
  }

  Future<void> _batchDownload() async {
    final sel = _songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (sel.isEmpty) return;
    setState(() => _downloading = true);
    int ok = 0;
    for (final s in sel) {
      if (await _downloadSong(s)) ok++;
    }
    if (mounted) setState(() => _downloading = false);
    _toast('已下载 $ok / ${sel.length} 首');
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
              : AppContentColumn(
                  child: Column(
                    children: [
                      _buildAppBar(style, loggedIn),
                      Expanded(child: _buildContent(style, loggedIn)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// 非多选态的页面主体：登录引导 / 加载 / 错误 / 空态 / 曲目列表，
  /// 用 if-else 平铺（避免深层三元嵌套），单曲点按播放。
  Widget _buildContent(AppStyle style, bool loggedIn) {
    if (!loggedIn) return _buildLoginHint(style);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
    if (_songs.isEmpty) {
      return Center(
          child: Text('今日暂无推荐',
              style: TextStyle(color: style.textSecondary)));
    }
    final sp = AppSpacing.of(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(sp.gutter, 0, sp.gutter, sp.section),
      itemCount: _songs.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppSpacing.xxs),
      itemBuilder: (c, i) => SongTile(
        song: _songs[i],
        onTap: () => play.playAndOpen(ref, context, _songs, i),
      ),
    );
  }

  Widget _buildAppBar(AppStyle style, bool loggedIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: style.textPrimary),
          ),
          Expanded(
            child: Text('每日推荐',
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          if (loggedIn && _songs.isNotEmpty) ...[
            IconButton(
              onPressed: _enterSelect,
              icon: Icon(Icons.checklist, color: style.textPrimary),
              tooltip: '多选下载',
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _playAll,
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              label: const Text('播放全部'),
            ),
          ],
        ],
      ),
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
