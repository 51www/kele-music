// 备份文件交付：平台差异收敛到条件导入（同 download.dart 模式）。
// - Web：Blob + <a download> 触发浏览器下载
// - Android/iOS：落临时文件 + 系统分享面板
// - 桌面（Windows/macOS/Linux）：file_picker 另存为对话框

import 'dart:typed_data';

import 'backup_share_stub.dart'
    if (dart.library.html) 'backup_share_web.dart'
    if (dart.library.io) 'backup_share_io.dart';

/// 交付备份文件；返回是否成功（用户取消另存为也视为 false）。
Future<bool> deliverBackupFile(String filename, Uint8List bytes) =>
    deliverBackupFileImpl(filename, bytes);
