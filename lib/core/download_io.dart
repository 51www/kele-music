import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 移动端/桌面端：HttpClient 拉取音源字节流，经平台通道写入系统
/// Download 目录（Android 10+ 走 MediaStore，无需存储权限）。
const MethodChannel _channel = MethodChannel('kele_music/downloads');

Future<bool> downloadFile(String url, String filename) async {
  HttpClient? client;
  try {
    client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) return false;
    final builder = BytesBuilder();
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final mime =
        url.toLowerCase().contains('.flac') ? 'audio/flac' : 'audio/mpeg';
    await _channel.invokeMethod<String>('saveToDownloads', {
      'bytes': bytes,
      'filename': filename,
      'mime': mime,
    });
    return true;
  } catch (_) {
    return false;
  } finally {
    client?.close(force: true);
  }
}
