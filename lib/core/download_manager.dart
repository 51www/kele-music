import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载任务状态：下载中 / 已完成 / 失败。
enum DownloadStatus { downloading, completed, failed }

/// 单条下载任务的快照（不可变，供 Riverpod 直接比对重建）。
///
/// 仅本会话内存持有，与现有下载「即下即弃」的口径一致——不做持久化，
/// 应用重启后任务列表清空，已落到系统 Download 目录的文件不受影响。
class DownloadTask {
  final String id;
  final String fileName;
  final DownloadStatus status;
  final int receivedBytes;
  /// 总字节数；-1 表示未知（服务器未返回 content-length），进度条转不确定态。
  final int totalBytes;
  final DateTime createdAt;
  final DateTime? finishedAt;

  const DownloadTask({
    required this.id,
    required this.fileName,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    required this.createdAt,
    this.finishedAt,
  });

  /// 已知总大小时返回 0~1 进度；未知时恒为 0（调用方改用不确定态进度条）。
  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  DownloadTask copyWith({
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    DateTime? finishedAt,
  }) =>
      DownloadTask(
        id: id,
        fileName: fileName,
        status: status ?? this.status,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        createdAt: createdAt,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

/// 下载任务管理器：批量下载/单曲下载每首歌登记一条任务，页面据此展示
/// 进度与状态。最新任务置顶（新建即「下载中」），删除操作移除记录（不触碰磁盘文件）。
class DownloadManagerNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadManagerNotifier() : super(const []);

  int _seq = 0;

  /// 登记一条新下载（新建即「下载中」），返回任务 id 供后续更新进度/结束。
  String addTask(String fileName) {
    _seq++;
    final task = DownloadTask(
      id: 'dl_$_seq',
      fileName: fileName,
      status: DownloadStatus.downloading,
      receivedBytes: 0,
      totalBytes: -1,
      createdAt: DateTime.now(),
    );
    state = [task, ...state]; // 最新在前。
    return task.id;
  }

  /// 更新下载进度（received/total 字节）。total = -1 表示大小未知。
  void updateProgress(String id, int received, int total) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(receivedBytes: received, totalBytes: total)
        else
          t
    ];
  }

  /// 标记任务结束：success → 已完成，否则 → 失败，并记录完成时间。
  void complete(String id, bool success) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            status: success ? DownloadStatus.completed : DownloadStatus.failed,
            finishedAt: DateTime.now(),
          )
        else
          t
    ];
  }

  /// 单项删除：仅移除记录，不删除已下载到系统目录的文件。
  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  /// 批量删除：移除一组任务记录。
  void removeMany(List<String> ids) {
    final set = ids.toSet();
    state = state.where((t) => !set.contains(t.id)).toList();
  }
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, List<DownloadTask>>(
        (ref) => DownloadManagerNotifier());
