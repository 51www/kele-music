import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/download_manager.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// 下载管理：展示批量下载（及单曲下载）任务列表，支持查看每项状态
/// （下载中 / 已完成 / 失败）、进度与时间，并提供单项删除与批量删除
/// （均带确认）。视觉延续「我的」模块：渐变背景 + GlassPanel；多选交互
/// 与专辑详情页一致（勾选框 + 全选 + 底部操作条）。
class DownloadManagerScreen extends ConsumerStatefulWidget {
  const DownloadManagerScreen({super.key});
  @override
  ConsumerState<DownloadManagerScreen> createState() =>
      _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends ConsumerState<DownloadManagerScreen> {
  bool _selectMode = false;
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
      if (_selectedIds.contains(t.id)) setState(() => _selectedIds.remove(t.id));
      if (_selectMode && _selectedIds.isEmpty) setState(() => _selectMode = false);
    }
  }

  Future<void> _confirmBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    final style = kStyles[ref.read(styleIndexProvider)];
    final ids = _selectedIds.toList();
    final ok = await showConfirmDialog(
      context,
      style: style,
      title: '删除下载记录',
      message: '确定删除选中的 ${ids.length} 项记录？\n该操作仅移除记录，已下载到系统的文件不会被删除。',
    );
    if (ok && mounted) {
      ref.read(downloadManagerProvider.notifier).removeMany(ids);
      setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final tasks = ref.watch(downloadManagerProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          child: AppContentColumn(
            child: _selectMode
                ? _buildSelectMode(style, tasks)
                : Column(
                    children: [
                      _buildAppBar(style, tasks.isNotEmpty),
                      Expanded(child: _buildList(style, tasks)),
                    ],
                  ),
          ),
        ),
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

  Widget _buildSelectMode(AppStyle style, List<DownloadTask> tasks) {
    final allSelected = tasks.isNotEmpty && _selectedIds.length == tasks.length;
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
                    _selectedIds.addAll(tasks.map((t) => t.id));
                  }
                }),
                child: Text(allSelected ? '取消全选' : '全选',
                    style: TextStyle(color: style.accent, fontSize: 14)),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: style.surfaceBorder),
        Expanded(child: _buildList(style, tasks)),
        _buildSelectActions(style),
      ],
    );
  }

  Widget _buildList(AppStyle style, List<DownloadTask> tasks) {
    if (tasks.isEmpty) return _buildEmpty(style);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: tasks.length,
        separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: style.textSecondary.withValues(alpha: 0.15)),
        itemBuilder: (c, i) {
          final t = tasks[i];
          return _selectMode
              ? _selectTile(style, t)
              : _taskTile(style, t);
        },
      ),
    );
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
    final sel = _selectedIds.contains(t.id);
    return InkWell(
      onTap: () => _toggleSelect(t.id),
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
