// Web 平台交付：Blob + <a download> 触发浏览器下载（复用 download_web.dart
// 的成熟模式），objectURL 延迟回收。

import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> deliverBackupFileImpl(String filename, Uint8List bytes) async {
  try {
    final blob = html.Blob([bytes]);
    final objUrl = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: objUrl)
      ..download = filename
      ..click();
    Timer(const Duration(seconds: 10), () => html.Url.revokeObjectUrl(objUrl));
    return true;
  } catch (_) {
    return false;
  }
}
