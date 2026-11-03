import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../providers.dart';
import 'download.dart';
import 'download_manager.dart';
import 'download_registry.dart';

/// 单批任务量超过该值时，提交前向用户确认一次（任务量过大提示）。
const kLargeBatchThreshold = 20;

/// 后台并发下载数：同时传输的歌曲数（每首独立 HttpClient，互不影响）。
const kDownloadConcurrency = 2;

/// 一条后台下载作业：由调用方打包「单曲下载」闭包，队列按并发调度执行。
class DownloadJob {
  final Future<bool> Function() run;
  const DownloadJob({required this.run});
}

/// 批次状态：后台进行中 / 已结束（保留摘要，用户手动关闭）。
enum BatchStatus { running, done }

/// 一批后台下载任务的汇总进度（会话内存，供「下载管理」页展示）。
class BatchProgress {
  final String id;
  final String label;
  final int total;
  final int done;
  final int ok;
  final int failed;
  final BatchStatus status;

  const BatchProgress({
    required this.id,
    required this.label,
    required this.total,
    required this.done,
    required this.ok,
    required this.failed,
    required this.status,
  });

  double get progress => total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

  BatchProgress copyWith({
    int? done,
    int? ok,
    int? failed,
    BatchStatus? status,
  }) =>
      BatchProgress(
        id: id,
        label: label,
        total: total,
        done: done ?? this.done,
        ok: ok ?? this.ok,
        failed: failed ?? this.failed,
        status: status ?? this.status,
      );
}

class _PendingBatch {
  final String id;
  final List<DownloadJob> jobs;
  const _PendingBatch(this.id, this.jobs);
}

/// 批量下载后台队列：提交批次立即返回，FIFO 逐批执行；
/// 批内最多 [kDownloadConcurrency] 首同时在传。批次进度实时更新到
/// [downloadQueueProvider]，页面可随时离开，进度在「下载管理」页查看。
class DownloadQueueNotifier extends StateNotifier<List<BatchProgress>> {
  DownloadQueueNotifier() : super(const []);

  final List<_PendingBatch> _queue = [];
  bool _draining = false;
  int _seq = 0;

  /// 提交一批下载作业：登记批次并立即返回，后台排队执行。
  void enqueue(String label, List<DownloadJob> jobs) {
    if (jobs.isEmpty) return;
    _seq++;
    final id = 'batch_$_seq';
    state = [
      ...state,
      BatchProgress(
        id: id,
        label: label,
        total: jobs.length,
        done: 0,
        ok: 0,
        failed: 0,
        status: BatchStatus.running,
      ),
    ];
    _queue.add(_PendingBatch(id, jobs));
    _drain();
  }

  /// 关闭一条已结束批次的摘要（不触碰下载任务与文件）。
  void dismiss(String id) {
    state = state.where((b) => b.id != id).toList();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final b = _queue.removeAt(0);
        await _runBatch(b);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _runBatch(_PendingBatch batch) async {
    final it = batch.jobs.iterator;
    int done = 0, ok = 0, failed = 0;
    void bump(bool success) {
      done++;
      success ? ok++ : failed++;
      _patch(batch.id, done: done, ok: ok, failed: failed);
    }

    // 简易并发池：N 个 worker 从同一迭代器领任务（单线程模型下安全）。
    Future<void> worker() async {
      while (true) {
        if (!it.moveNext()) return;
        final job = it.current;
        bool success = false;
        try {
          success = await job.run();
        } catch (_) {
          success = false; // 单首失败不影响批次内其余歌曲。
        }
        bump(success);
      }
    }

    await Future.wait([
      for (var i = 0; i < kDownloadConcurrency; i++) worker(),
    ]);
    _patch(batch.id, status: BatchStatus.done);
  }

  void _patch(String id,
      {int? done, int? ok, int? failed, BatchStatus? status}) {
    state = [
      for (final b in state)
        if (b.id == id)
          b.copyWith(done: done, ok: ok, failed: failed, status: status)
        else
          b
    ];
  }
}

final downloadQueueProvider =
    StateNotifierProvider<DownloadQueueNotifier, List<BatchProgress>>(
        (ref) => DownloadQueueNotifier());

/// 单曲下载执行器：持有 Provider 级 ref（应用生命周期，后台任务可安全使用）。
/// 流程：解析音源 → 登记「下载中」任务 → 拉流写系统下载目录 + 落应用内缓存
/// → 登记已下载（播放直读本地、去重依据）。多选批量与单曲下载共用此入口。
final songDownloadExecutorProvider = Provider<Future<bool> Function(Song s)>(
    (ref) => (Song s) async {
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
});
