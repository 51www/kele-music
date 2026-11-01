import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Web 平台：拉取音频字节流转 Blob，用 <a download> 触发浏览器下载；
/// 跨域 CORS 失败时退化为新标签页打开音源（返回 false 提示手动保存）。
Future<bool> downloadFile(String url, String filename,
    {void Function(int received, int total)? onProgress}) async {
  try {
    final resp = await html.HttpRequest.request(url,
        responseType: 'arraybuffer');
    onProgress?.call(1, 1); // Web 无流式进度，仅标记开始/结束。
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
