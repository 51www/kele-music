import 'dart:typed_data';

/// Web 桩：不支持裸 Socket，恒返回 null（Web 端图片加载走浏览器栈，无此问题）。
Future<Uint8List?> rawHttpGet(String url, {int maxRedirects = 2}) async =>
    null;
