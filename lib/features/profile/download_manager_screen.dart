import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/download_manager.dart';
import '../../core/download_registry.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 下载管理：上半区展示进行中/失败的下载任务（会话内），下半区展示
/// 已下载歌曲（持久化登记），支持「全部播放」与单曲点播——播放走统一
/// 播放队列（playAndOpen），暂停/继续/上下曲由标准播放页接管；正在播放
/// 的行以 accent 色动态图标标识。已下载行尾显示文件大小（时长不展示、
/// 不显示 VIP 标），行尾保留单条「移除」入口（仅删记录）。
/// 支持多选批量删除：长按歌曲行或点「管理」进入多选，批量删除歌曲时
/// 连同应用内缓存文件一起删除（系统下载目录文件不可删，见登记表注释）。
/// 视觉延续「我的」模块：渐变背景 + 列表直排；多选交互与专辑详情页一致。
class DownloadManagerScreen extends ConsumerStatefulWidget {
  const DownloadManagerScreen({super.key});
  @override
  ConsumerState<DownloadManagerScreen> createState() =>
      _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends ConsumerState<DownloadManagerScreen> {
  bool _selectMode = false;
  /// 选择集：复合 key——`task:<任务id>`（会话内下载任务）、
  /// `song:<songId>`（已下载歌曲），任务与歌曲统一进全选/计数/批量删除。
  final Set<String> _selectedIds = {};

  void _enterSelect() => setState(() {
        _selectMode = true;
        _selectedIds.clear();
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });

  void _toggleSelect(String id) => setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
      });

  Future<void> _confirmDeleteOne(DownloadTask t) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final ok = await showConfirmDialog(
      context,
      style: style,
      title: '删除下载记录',
      message: '确定删除「${t.fileName}」？\n该操作仅移除记录，已下载到系统的文件不会被删除。',
    );
    if (ok && mounted) {
      ref.read(downloadManagerProvider.notifier).remove(t.id);
      if (_selectedIds.contains('task:${t.id}')) {
        setState(() => _selectedIds.remove('task:${t.id}'));
      }
      if (_selectMode && _selectedIds.isEmpty) setState(() => _selectMode = false);
    }
  }

  Future<void> _confirmBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    final style = kStyles[ref.read(styleIndexProvider)];
    final taskIds = [
      for (final k in _selectedIds)
        if (k.startsWith('task:')) k.substring(5),
    ];
    final songIds = [
      for (final k in _selectedIds)
        if (k.startsWith('song:')) int.tryParse(k.substring(5)) ?? 0,
    ]..removeWhere((id) => id <= 0);
    final ok = await showConfirmDialog(
      context,
      style: style,
      title: '批量删除',
      message: '确定删除选中的 ${_selectedIds.length} 项？\n'
          '已下载歌曲将连同应用内缓存文件一起删除，'
          '已保存到系统下载目录的文件无法删除。',
    );
    if (ok && mounted) {
      // 任务：仅移除会话内记录（无本地文件）；歌曲：删应用内缓存文件后撤销登记。
      if (taskIds.isNotEmpty) {
        ref.read(downloadManagerProvider.notifier).removeMany(taskIds);
      }
      if (songIds.isNotEmpty) {
        ref.read(downloadRegistryProvider.notifier).forgetAndDeleteCache(songIds);
      }
      setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });
    }
  }

  /// 已下载歌曲（登记表，最新在前；旧记录缺歌曲信息的不可播放，不展示）。
  List<DownloadedSong> _downloadedSongs(Map<int, DownloadedSong> registry) =>
      [
        for (final r in registry.values)
          if (r.song != null) r,
      ].reversed.toList();

  /// 删除一条已下载登记（仅移除记录与播放资格，不删磁盘文件）。
  Future<void> _confirmForgetSong(DownloadedSong r) async {
    final style = kStyles[ref.read(styleIndexProvider)];
    final ok = await showConfirmDialog(
      context,
      style: style,
      title: '移除已下载歌曲',
      message: '确定移除「${r.song!.name}」？\n该操作仅移除记录，已下载到系统的文件不会被删除。',
    );
    if (ok && mounted) {
      ref.read(downloadRegistryProvider.notifier).forget(r.songId);
    }
  }

  /// 全部播放：以整个已下载列表为播放队列（播完自动切下一首），
  /// 暂停/继续/上一首/下一首由标准播放页与全局播放条接管。
  Future<void> _playAll(List<DownloadedSong> songs) async {
    if (songs.isEmpty) return;
    final queue = [for (final r in songs) r.song!];
    await play.playAndOpen(ref, context, queue, 0);
  }

  /// 单曲播放：以已下载列表为队列，从点击处起播（上下曲在队列内切换）。
  Future<void> _playAt(List<DownloadedSong> songs, int index) async {
    final queue = [for (final r in songs) r.song!];
    await play.playAndOpen(ref, context, queue, index);
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final tasks = ref
        .watch(downloadManagerProvider)
        .where((t) => t.status != DownloadStatus.completed)
        .toList(); // 已完成任务转入下方「已下载」歌单区，不再重复展示。
    final registry = ref.watch(downloadRegistryProvider);
    final songs = _downloadedSongs(registry);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          child: AppContentColumn(
            child: _selectMode
                ? _buildSelectMode(style, tasks, songs)
                : Column(
                    children: [
                      _buildAppBar(style, tasks.isNotEmpty),
                      if (songs.isNotEmpty) _buildPlayAllBar(style, songs),
                      Expanded(child: _buildList(style, tasks, songs)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// 「全部播放」操作条：以已下载列表为队列顺序播放；旁挂「管理」按钮
  /// 进入多选模式（与长按歌曲行等效）。
  Widget _buildPlayAllBar(AppStyle style, List<DownloadedSong> songs) {
    final sp = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(sp.gutter, sp.inline, sp.gutter, sp.inline),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _playAll(songs),
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.uiRadius),
                ),
              ),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text('全部播放（${songs.length} 首）'),
            ),
          ),
          SizedBox(width: sp.inline),
          OutlinedButton.icon(
            onPressed: _enterSelect,
            style: OutlinedButton.styleFrom(
              foregroundColor: style.textPrimary,
              minimumSize: const Size(0, 46),
              side: BorderSide(color: style.surfaceBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(style.uiRadius),
              ),
            ),
            icon: const Icon(Icons.checklist, size: 20),
            label: const Text('管理'),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(AppStyle style, bool hasTasks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: style.textPrimary),
          ),
          Expanded(
            child: Text('下载管理',
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          if (hasTasks)
            IconButton(
              onPressed: _enterSelect,
              icon: Icon(Icons.checklist, color: style.textPrimary),
              tooltip: '选择',
            ),
        ],
      ),
    );
  }

  Widget _buildSelectMode(AppStyle style, List<DownloadTask> tasks,
      List<DownloadedSong> songs) {
    final totalCount = tasks.length + songs.length;
    final allSelected = totalCount > 0 && _selectedIds.length == totalCount;
    return Column(
      children: [
        SizedBox(
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
                    _selectedIds
                      ..addAll(tasks.map((t) => 'task:${t.id}'))
                      ..addAll(songs.map((r) => 'song:${r.songId}'));
                  }
                }),
                child: Text(allSelected ? '取消全选' : '全选',
                    style: TextStyle(color: style.accent, fontSize: 14)),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: style.surfaceBorder),
        Expanded(child: _buildList(style, tasks, songs)),
        _buildSelectActions(style),
      ],
    );
  }

  Widget _buildList(
      AppStyle style, List<DownloadTask> tasks, List<DownloadedSong> songs) {
    if (tasks.isEmpty && songs.isEmpty) return _buildEmpty(style);
    final sp = AppSpacing.of(context);
    final q = ref.watch(queueProvider).valueOrNull;
    final currentId = (q != null && q.index >= 0 && q.index < q.songs.length)
        ? q.songs[q.index].id
        : -1;
    // 无卡片容器：列表直接融入页面渐变背景，仅保留分区标题与分隔线。
    return ListView(
      padding: EdgeInsets.fromLTRB(sp.gutter, sp.inline, sp.gutter, sp.inline),
      children: [
        // ── 进行中 / 失败任务区（会话内） ──
        if (tasks.isNotEmpty) ...[
          _sectionHeader(style, '下载任务', tasks.length),
          for (final t in tasks)
            _selectMode ? _selectTile(style, t) : _taskTile(style, t),
        ],
        // ── 已下载歌曲区（持久化登记，可播放） ──
        if (songs.isNotEmpty) ...[
          if (tasks.isNotEmpty)
            Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: style.textSecondary.withValues(alpha: 0.15)),
          _sectionHeader(style, '已下载', songs.length),
          for (var i = 0; i < songs.length; i++)
            _selectMode ? _songSelectTile(style, songs, i) : _songTile(style, songs, i, currentId),
        ],
      ],
    );
  }

  Widget _sectionHeader(AppStyle style, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  color: style.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('$count',
              style:
                  TextStyle(color: style.textSecondary.withValues(alpha: 0.7), fontSize: 12)),
        ],
      ),
    );
  }

  /// 已下载歌曲行：复用全应用共用的 SongTile（序号 + 封面同显）。
  /// 正在播放的行由 SongTile 内建高亮：accent 色歌名 + 播放中动态音波，
  /// 点按当前曲交给播放页处理。不显示 VIP 标与时长，行尾显示文件大小；
  /// 保留「移除」入口（仅删记录）；长按进入多选并预选该行。
  Widget _songTile(AppStyle style, List<DownloadedSong> songs, int i,
      int currentId) {
    final r = songs[i];
    final s = r.song!;
    final current = s.id == currentId;
    return SongTile(
      song: s,
      index: i + 1,
      showCover: true,
      showVip: false,
      durationMs: null, // 时长不展示，改为行尾文件大小。
      onLongPress: () => setState(() {
        _selectMode = true;
        _selectedIds..clear()..add('song:${r.songId}');
      }),
      onTap: current
          ? null
          : () => _playAt(songs, i), // 当前曲：交给播放页处理，避免重入。
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_fmtSize(r.sizeBytes),
              style: TextStyle(
                  color: style.textSecondary.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: style.textSecondary),
            tooltip: '移除',
            onPressed: () => _confirmForgetSong(r),
          ),
        ],
      ),
    );
  }

  /// 多选态歌曲行：勾选框 + 封面 + 歌名/歌手，点按切换选择。
  Widget _songSelectTile(
      AppStyle style, List<DownloadedSong> songs, int i) {
    final sp = AppSpacing.of(context);
    final r = songs[i];
    final s = r.song!;
    final key = 'song:${r.songId}';
    final sel = _selectedIds.contains(key);
    return InkWell(
      onTap: () => _toggleSelect(key),
      borderRadius: BorderRadius.circular(style.uiRadius / 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.micro, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? style.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(style.uiRadius / 2),
        ),
        child: Row(
          children: [
            _checkBox(sel, style),
            SizedBox(width: sp.block),
            CoverImage(
                url: s.coverUrl,
                size: 44,
                radius: BorderRadius.circular(style.uiRadius / 2)),
            SizedBox(width: sp.inline),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: sel ? style.accent : style.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(s.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: style.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Text(_fmtSize(r.sizeBytes),
                style: TextStyle(
                    color: style.textSecondary.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }

  /// 文件大小格式化：≥1MB 显示 x.x MB，否则 KB；无数据/异常值显示「—」。
  String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '—';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Widget _buildEmpty(AppStyle style) {
    final sp = AppSpacing.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_done_outlined,
                size: 56, color: style.textSecondary.withValues(alpha: 0.7)),
            SizedBox(height: sp.block),
            Text('暂无下载任务',
                style: TextStyle(color: style.textPrimary, fontSize: 16)),
            const SizedBox(height: AppSpacing.micro),
            Text('在专辑或每日推荐中批量下载后，任务会显示在这里',
                textAlign: TextAlign.center,
                style: TextStyle(color: style.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// 非多选态单行：状态图标 + 文件名 + 状态/进度/时间 + 删除按钮。
  Widget _taskTile(AppStyle style, DownloadTask t) {
    final sp = AppSpacing.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(_statusIcon(t.status), size: 22, color: _statusColor(style, t.status)),
          SizedBox(width: sp.block),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xxs),
                Text(_subtitle(t),
                    style: TextStyle(
                        color: style.textSecondary, fontSize: 12)),
                if (t.status == DownloadStatus.downloading) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: t.totalBytes > 0 ? t.progress : null,
                      minHeight: 4,
                      color: style.accent,
                      backgroundColor: style.surface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDeleteOne(t),
            icon: Icon(Icons.delete_outline,
                size: 20, color: style.textSecondary),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  /// 多选态单行：勾选框 + 文件名 + 状态，点按切换选择。
  Widget _selectTile(AppStyle style, DownloadTask t) {
    final sp = AppSpacing.of(context);
    final key = 'task:${t.id}';
    final sel = _selectedIds.contains(key);
    return InkWell(
      onTap: () => _toggleSelect(key),
      borderRadius: BorderRadius.circular(style.uiRadius / 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.micro, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? style.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(style.uiRadius / 2),
        ),
        child: Row(
          children: [
            _checkBox(sel, style),
            SizedBox(width: sp.block),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: sel ? style.accent : style.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(_subtitle(t),
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

  /// 多选底部操作条：批量删除（无勾选时禁用，红色强调）。
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
            child: FilledButton.icon(
              onPressed: hasSel ? _confirmBatchDelete : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.uiRadius),
                ),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(hasSel
                  ? '删除（${_selectedIds.length}）'
                  : '删除'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.downloading:
        return Icons.downloading_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_outline;
      case DownloadStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _statusColor(AppStyle style, DownloadStatus s) {
    switch (s) {
      case DownloadStatus.downloading:
        return style.accent;
      case DownloadStatus.completed:
        return Colors.green.shade400;
      case DownloadStatus.failed:
        return Colors.redAccent.shade200;
    }
  }

  String _subtitle(DownloadTask t) {
    final time = _fmt(t.status == DownloadStatus.downloading
        ? t.createdAt
        : (t.finishedAt ?? t.createdAt));
    switch (t.status) {
      case DownloadStatus.downloading:
        final pct = t.totalBytes > 0
            ? '${(t.progress * 100).toStringAsFixed(0)}%'
            : '进行中';
        return '下载中 · $pct · $time';
      case DownloadStatus.completed:
        return '已完成 · $time';
      case DownloadStatus.failed:
        return '失败 · $time';
    }
  }

  String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
