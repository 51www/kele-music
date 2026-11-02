import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data' show Uint8List, ByteBuffer;

/// Web 平台：拉取音频字节流转 Blob，用 <a download> 触发浏览器下载；
/// 跨域 CORS 失败时退化为新标签页打开音源（返回 false 提示手动保存）。
/// [onBytes] 回传完整字节：Web 无应用内缓存文件，但下载管理页需要登记
/// 文件大小，调用方据此写入 sizeBytes。
Future<bool> downloadFile(String url, String filename,
    {void Function(int received, int total)? onProgress,
    void Function(Uint8List bytes)? onBytes}) async {
  try {
    final resp = await html.HttpRequest.request(url,
        responseType: 'arraybuffer');
    final bytes = (resp.response as ByteBuffer).asUint8List();
    onProgress?.call(1, 1); // Web 无流式进度，仅标记开始/结束。
    onBytes?.call(bytes);
    final blob = html.Blob([resp.response]);
    final objUrl = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: objUrl)
      ..download = filename
      ..click();
    // 等浏览器拿到引用后再回收 object URL。
    Timer(const Duration(seconds: 10), () => html.Url.revokeObjectUrl(objUrl));
    onProgress?.call(1, 1);
    return true;
  } catch (_) {
    html.window.open(url, '_blank');
    return false;
  }
}
