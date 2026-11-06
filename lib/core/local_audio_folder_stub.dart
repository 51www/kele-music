// Web 平台实现：目录扫描导入不可用（浏览器文件选择器拿不到目录句柄）。
import 'local_audio_folder.dart';

LocalFolderImporter createLocalFolderImporter() =>
    const _UnsupportedFolderImporter();

Future<LocalAudioFileInfo?> inspectLocalAudioFile(String path) async => null;

class _UnsupportedFolderImporter implements LocalFolderImporter {
  const _UnsupportedFolderImporter();

  @override
  bool get supported => false;

  @override
  Future<FolderHandle?> pickFolder() async => null;

  @override
  Future<FolderImportOutcome> importFolder(
    FolderHandle handle, {
    required void Function(FolderImportProgress) onProgress,
    required bool Function() isCancelled,
  }) async =>
      const FolderImportOutcome(
          files: [], total: 0, failed: 0, cancelled: false);

  @override
  void cancel() {}
}
