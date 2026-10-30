import 'dart:io';

import 'package:crypto/crypto.dart';

/// 计算文件 SHA-256（小写 hex）；文件不存在或读取失败返回 null（表示「无法校验」，
/// 由调用方决定是放行还是换源，不抛异常）。
Future<String?> fileSha256(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString(); // crypto 的 Digest.toString() 即小写 hex
  } catch (_) {
    return null;
  }
}
