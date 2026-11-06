// 「扫描文件夹导入」的跨平台门面：共享类型 + 平台实现转发。
// 平台差异收敛到条件导入（同 backup_share.dart 模式）：
// - Android：SAF 目录授权 + 原生递归扫描/复制（content:// 无法用 dart:io 读）
// - iOS：系统目录选择器 + security-scoped 访问，dart:io 遍历并复制进沙盒
// - 桌面：系统目录选择器 + dart:io 遍历，直接引用原文件
// - Web：不支持（文件选择器拿不到目录）

import 'local_audio_folder_stub.dart'
    if (dart.library.io) 'local_audio_folder_io.dart' as impl;

/// 本地播放支持的音频扩展名（小写、不含点）。单文件选择与目录扫描共用，
/// 也作为扩展名白名单传给 Android 原生通道，避免两端规则漂移。
const List<String> kLocalAudioExtensions = <String>[
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
  'opus',
  'aif',
  'aiff',
];

/// 取小写扩展名（不含点）；无扩展名返回空串。
String localAudioExtension(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// 扩展名是否在支持列表内。
bool isSupportedLocalAudio(String path) =>
    kLocalAudioExtensions.contains(localAudioExtension(path));

/// 用户选中的目录句柄：Android 为 SAF tree uri，iOS/桌面为绝对路径。
class FolderHandle {
  final String id;
  final String name;
  const FolderHandle({required this.id, required this.name});
}

/// 校验通过、可以直接入库的本地音频文件。
class LocalAudioFileInfo {
  final String path;
  const LocalAudioFileInfo(this.path);
}

/// 目录扫描产出的单个音频文件。
/// [path] 为设备上可播放的 file 路径；[displayName] 为原始文件名（含扩展名）。
class LocalAudioEntry {
  final String path;
  final String displayName;
  final String relativePath;
  const LocalAudioEntry({
    required this.path,
    required this.displayName,
    required this.relativePath,
  });
}

/// 目录导入进度。[phase]：scanning（扫描中，total 未知）/ importing（复制中）。
class FolderImportProgress {
  final String phase;
  final int processed;
  final int total;
  final int success;
  final int failed;
  const FolderImportProgress({
    required this.phase,
    required this.processed,
    required this.total,
    required this.success,
    required this.failed,
  });

  const FolderImportProgress.scanning()
      : phase = 'scanning',
        processed = 0,
        total = -1,
        success = 0,
        failed = 0;

  bool get isScanning => phase == 'scanning';
}

/// 目录导入结果。[files] 为已复制好的文件（取消时为已完成部分）。
class FolderImportOutcome {
  final List<LocalAudioEntry> files;
  final int total;
  final int failed;
  final bool cancelled;
  const FolderImportOutcome({
    required this.files,
    required this.total,
    required this.failed,
    required this.cancelled,
  });
}

/// 目录导入失败（权限被撤销、目录不存在等），message 可直接提示用户。
class LocalFolderImportException implements Exception {
  final String message;
  const LocalFolderImportException(this.message);
  @override
  String toString() => message;
}

/// 目录导入的平台能力。
abstract class LocalFolderImporter {
  /// 当前平台是否支持扫描目录导入。
  bool get supported;

  /// 弹出系统目录选择器；用户取消返回 null。
  Future<FolderHandle?> pickFolder();

  /// 递归扫描 [handle] 并导入其中的音频文件。
  /// 通过 [onProgress] 汇报进度；[isCancelled] 为真时尽快停止并返回已完成部分。
  Future<FolderImportOutcome> importFolder(
    FolderHandle handle, {
    required void Function(FolderImportProgress) onProgress,
    required bool Function() isCancelled,
  });

  /// 请求取消正在进行的导入（原生实现需要它通知后台线程）。
  void cancel();
}

/// 按当前平台创建实现。
LocalFolderImporter createLocalFolderImporter() =>
    impl.createLocalFolderImporter();

/// 校验单个本地音频路径（扩展名 / 存在性 / 非空）。
/// 通过返回文件信息，失败返回 null（不支持或不可读）。
Future<LocalAudioFileInfo?> inspectLocalAudioFile(String path) =>
    impl.inspectLocalAudioFile(path);
