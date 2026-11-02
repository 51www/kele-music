// 条件导入兜底桩：理论上 Web（dart.library.html）与 IO（dart.library.io）
// 已覆盖所有平台，此桩永远不会被选中，仅为满足条件导入完整链路。

import 'dart:typed_data';

Future<bool> deliverBackupFileImpl(String filename, Uint8List bytes) =>
    throw UnsupportedError('当前平台不支持交付备份文件');
