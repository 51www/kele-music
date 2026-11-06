// 本地歌单的两个导入入口（入口并排放在歌单详情页操作条，不另开菜单）：
// 1. 选择音频文件（多选）：iOS 用扩展名白名单走文档选择器，Android 用 audio 过滤；
// 2. 扫描文件夹：Android 走 SAF 原生递归，iOS/桌面用 dart:io 遍历。
// 两条链路都逐个校验、逐个入库；重复项单独计数并明确提示，不静默丢弃。
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/local_audio_folder.dart';
import '../../core/local_store.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 单文件多选导入。返回实际新增 / 重复跳过 / 校验失败数量。
Future<void> importLocalAudioFiles(
    BuildContext context, WidgetRef ref, int playlistId) async {
  if (kIsWeb) {
    showAppToast(context, ref, 'Web 端暂不支持导入本地音频，请在 App / 桌面端使用',
        success: false);
    return;
  }
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  List<PlatformFile> picked;
  try {
    final result = await FilePicker.platform.pickFiles(
      // iOS 的 FileType.audio 实际拉起 MPMediaPickerController（Apple Music
      // 媒体库），只能看到音乐 App / iTunes 里的条目，看不到「文件」App、
      // iCloud Drive 和「我的 iPhone」里的音频文件——这是 iOS 选不到音频的根因。
      // 改用扩展名白名单走 UIDocumentPickerController，导入模式会把文件复制进沙盒。
      type: ios ? FileType.custom : FileType.audio,
      allowedExtensions: ios ? kLocalAudioExtensions : null,
      allowMultiple: true,
    );
    picked = (result?.files ?? const <PlatformFile>[])
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .toList();
  } catch (_) {
    if (context.mounted) {
      showAppToast(context, ref, '打开文件选择器失败，请重试', success: false);
    }
    return;
  }
  if (picked.isEmpty) return;

  // 逐个校验扩展名 / 存在性 / 非空。小批量瞬间完成，不弹进度以免闪一下；
  // 大批量（20+）给出进度与取消，避免用户以为卡死。
  _ValidationResult validation;
  if (picked.length >= 20 && context.mounted) {
    final value = await _runWithProgress<_ValidationResult>(
      context: context,
      title: '正在导入 ${picked.length} 个文件',
      task: (progress, isCancelled) =>
          _validate(picked, progress: progress, isCancelled: isCancelled),
    );
    if (value == null) return;
    validation = value;
  } else {
    validation = await _validate(picked);
  }
  if (!context.mounted) return;

  final result = ref
      .read(localPlaylistsProvider.notifier)
      .addSongs(playlistId, validation.songs);
  showAppToast(
    context,
    ref,
    _summary(
        added: result.added,
        skipped: result.skippedDuplicate,
        failed: validation.failed),
    success: result.added > 0,
  );
}

/// 扫描目录导入：递归扫描所选目录下的全部受支持音频并一次性入库。
Future<void> importLocalAudioFolder(
    BuildContext context, WidgetRef ref, int playlistId) async {
  final importer = createLocalFolderImporter();
  if (!importer.supported) {
    showAppToast(context, ref, '当前平台暂不支持扫描文件夹导入', success: false);
    return;
  }

  FolderHandle? handle;
  final savedId = LocalStore.instance.getString(kLocalFolderUriKey);
  final savedName = LocalStore.instance.getString(kLocalFolderNameKey);
  if (savedId != null && savedId.isNotEmpty) {
    if (!context.mounted) return;
    // 上次记住的目录：权限由系统持久化（Android takePersistableUriPermission），
    // 可直接增量导入，也可重新选择。
    final reuse = await _askFolderReuse(
        context, kStyles[ref.read(styleIndexProvider)], savedName ?? '上次目录');
    if (reuse == null) return;
    if (reuse) handle = FolderHandle(id: savedId, name: savedName ?? '上次目录');
  }
  handle ??= await importer.pickFolder();
  final folder = handle;
  if (folder == null) return; // 用户取消
  LocalStore.instance.setString(kLocalFolderUriKey, folder.id);
  LocalStore.instance.setString(kLocalFolderNameKey, folder.name);
  if (!context.mounted) return;

  FolderImportOutcome? outcome;
  try {
    outcome = await _runWithProgress<FolderImportOutcome>(
      context: context,
      title: '扫描「${folder.name}」',
      onCancel: importer.cancel,
      task: (progress, isCancelled) => importer.importFolder(
        folder,
        onProgress: (p) => progress.value = p,
        isCancelled: isCancelled,
      ),
    );
  } on LocalFolderImportException catch (e) {
    if (context.mounted) showAppToast(context, ref, e.message, success: false);
    return;
  } catch (_) {
    if (context.mounted) {
      showAppToast(context, ref, '目录导入失败，请重试', success: false);
    }
    return;
  }
  if (outcome == null || !context.mounted) return;

  if (outcome.total == 0) {
    showAppToast(context, ref, '该目录下没有找到支持的音频文件', success: false);
    return;
  }

  final songs = <Song>[];
  var invalid = 0;
  for (final f in outcome.files) {
    // 复制成功不等于可播放：0 字节 / 已被删掉的文件在这里拦下并计入失败。
    final info = await inspectLocalAudioFile(f.path);
    if (info == null) {
      invalid++;
      continue;
    }
    songs.add(Song.fromLocalFilePath(f.path, displayName: f.displayName));
  }
  final result =
      ref.read(localPlaylistsProvider.notifier).addSongs(playlistId, songs);
  showAppToast(
    context,
    ref,
    _summary(
      added: result.added,
      skipped: result.skippedDuplicate,
      failed: outcome.failed + invalid,
      cancelled: outcome.cancelled,
    ),
    success: result.added > 0,
  );
}

/// 逐个校验：不支持的扩展名、文件不存在 / 为空都计为失败，不静默丢弃。
Future<_ValidationResult> _validate(
  List<PlatformFile> files, {
  ValueNotifier<FolderImportProgress>? progress,
  bool Function()? isCancelled,
}) async {
  final songs = <Song>[];
  var failed = 0;
  for (var i = 0; i < files.length; i++) {
    if (isCancelled?.call() ?? false) break;
    final path = files[i].path;
    final info = (path == null || path.isEmpty)
        ? null
        : await inspectLocalAudioFile(path);
    if (info == null) {
      failed++;
    } else {
      songs.add(Song.fromLocalFilePath(path!, displayName: files[i].name));
    }
    progress?.value = FolderImportProgress(
      phase: 'importing',
      processed: i + 1,
      total: files.length,
      success: songs.length,
      failed: failed,
    );
  }
  return _ValidationResult(songs, failed);
}

String _summary({
  required int added,
  required int skipped,
  required int failed,
  bool cancelled = false,
}) {
  if (added == 0 && skipped == 0 && failed == 0) return '未找到可导入的音频文件';
  final buffer = StringBuffer(cancelled ? '已取消，导入 $added 首' : '已导入 $added 首');
  if (skipped > 0) buffer.write('，已跳过 $skipped 个重复');
  if (failed > 0) buffer.write('，$failed 个失败');
  return buffer.toString();
}

/// 上次目录复用询问：true=继续使用，false=重新选择，null=取消。
Future<bool?> _askFolderReuse(
    BuildContext context, AppStyle style, String name) {
  return showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: Color.alphaBlend(style.surface, const Color(0x8C000000)),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(style.uiRadius + 4),
          side: BorderSide(color: style.surfaceBorder)),
      title: Text('从上次的目录导入？',
          style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
      content: Text(
        '上次导入目录：$name\n继续使用可增量导入该目录新增的音频。',
        style: TextStyle(color: style.textSecondary, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: Text('取消', style: TextStyle(color: style.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: Text('重新选择', style: TextStyle(color: style.textPrimary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: style.accent,
            foregroundColor: style.bgBottom,
          ),
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('继续使用'),
        ),
      ],
    ),
  );
}

/// 展示进度弹窗并执行 [task]；任务完成 / 抛错后自动关闭。
/// 返回 null 表示任务被取消且没有产出。
Future<T?> _runWithProgress<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function(ValueNotifier<FolderImportProgress> progress,
          bool Function() isCancelled)
      task,
  VoidCallback? onCancel,
}) async {
  final progress = ValueNotifier<FolderImportProgress>(
      const FolderImportProgress.scanning());
  var cancelled = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogOpen = true;
  // showDialog 会同步压入路由，之后 pop 一定能命中弹窗自身。
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        title: title,
        progress: progress,
        onCancel: () {
          cancelled = true;
          onCancel?.call();
        },
      ),
    ).whenComplete(() => dialogOpen = false),
  );
  try {
    final value = await task(progress, () => cancelled);
    if (dialogOpen && navigator.mounted) navigator.pop();
    dialogOpen = false;
    return value;
  } catch (_) {
    if (dialogOpen && navigator.mounted) navigator.pop();
    dialogOpen = false;
    rethrow;
  }
}

class _ValidationResult {
  final List<Song> songs;
  final int failed;
  const _ValidationResult(this.songs, this.failed);
}

/// 导入进度弹窗：扫描阶段未知总量用不确定进度条，复制阶段显示 x/y 与计数。
class _ImportProgressDialog extends ConsumerStatefulWidget {
  final String title;
  final ValueNotifier<FolderImportProgress> progress;
  final VoidCallback onCancel;
  const _ImportProgressDialog({
    required this.title,
    required this.progress,
    required this.onCancel,
  });

  @override
  ConsumerState<_ImportProgressDialog> createState() =>
      _ImportProgressDialogState();
}

class _ImportProgressDialogState extends ConsumerState<_ImportProgressDialog> {
  bool _cancelRequested = false;

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor:
            Color.alphaBlend(style.surface, const Color(0x8C000000)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.uiRadius + 4),
            side: BorderSide(color: style.surfaceBorder)),
        title: Text(widget.title,
            style: TextStyle(color: style.textPrimary, fontSize: 16.5)),
        content: ValueListenableBuilder<FolderImportProgress>(
          valueListenable: widget.progress,
          builder: (context, p, _) {
            final total = p.total;
            final ratio = (!p.isScanning && total > 0)
                ? (p.processed / total).clamp(0.0, 1.0).toDouble()
                : null;
            final main = p.isScanning
                ? '正在扫描目录… 已发现 ${p.processed} 个音频'
                : (total > 0
                    ? '已处理 ${p.processed}/$total'
                    : '已处理 ${p.processed} 个文件');
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: style.surfaceBorder,
                    color: style.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(main,
                    style: TextStyle(color: style.textPrimary, fontSize: 13.5)),
                const SizedBox(height: AppSpacing.xs),
                Text('成功 ${p.success} · 失败 ${p.failed}',
                    style:
                        TextStyle(color: style.textSecondary, fontSize: 12.5)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: _cancelRequested
                ? null
                : () {
                    setState(() => _cancelRequested = true);
                    widget.onCancel();
                  },
            child: Text(_cancelRequested ? '正在取消…' : '取消',
                style: TextStyle(color: style.textSecondary)),
          ),
        ],
      ),
    );
  }
}
