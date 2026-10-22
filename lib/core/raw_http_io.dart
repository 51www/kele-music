import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 裸 Socket HTTP GET：绕过 dart:io HttpClient 的指纹。
///
/// 背景（2026-10-22 真机实测）：网易云图床 pX.music.126.net 的 WAF 会指纹
/// 识别 dart:io HttpClient 的 HTTP 报文（Host 小写、头序/头集与浏览器不同），
/// 对其一律 403——无论 UA/Referer 如何伪装、无论 p1/p2/p3 节点与 http/https。
/// 而手机浏览器（Chrome）与 curl 形态的请求均放行。
/// 因此这里直接用 [Socket] 手工拼一份与 curl 一致的最小报文拉取字节，
/// 绕开 HttpClient 层。仅作为 SafeNetworkImage 的最终兜底。
Future<Uint8List?> rawHttpGet(String url, {int maxRedirects = 2}) async {
  final first = Uri.tryParse(url);
  if (first == null ||
      (first.scheme != 'http' && first.scheme != 'https')) {
    return null;
  }
  Uri current = first;
  for (var hop = 0; hop <= maxRedirects; hop++) {
    final isTls = current.scheme == 'https';
    final port = current.port == 0 ? (isTls ? 443 : 80) : current.port;
    final Socket socket;
    try {
      socket = await (isTls
              ? SecureSocket.connect(current.host, port,
                  timeout: const Duration(seconds: 10))
              : Socket.connect(current.host, port,
                  timeout: const Duration(seconds: 10)))
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
    final path = StringBuffer(current.path.isEmpty ? '/' : current.path);
    if (current.hasQuery) path.write('?${current.query}');
    // 与 curl 默认形态一致的报文：头序 Host → UA → Accept → Connection。
    socket.write('GET $path HTTP/1.1\r\n'
        'Host: ${current.host}\r\n'
        'User-Agent: curl/8.4.0\r\n'
        'Accept: */*\r\n'
        'Connection: close\r\n\r\n');
    final bytes = <int>[];
    try {
      await for (final chunk in socket) {
        bytes.addAll(chunk);
      }
    } catch (_) {
      // 读中断也先用已收到的字节解析（Connection: close 下通常已完整）。
    }
    socket.destroy();

    final sep = _findHeaderEnd(bytes);
    if (sep < 0) return null;
    final String head;
    try {
      head = latin1.decode(bytes.sublist(0, sep));
    } catch (_) {
      return null;
    }
    final status =
        int.tryParse(head.split('\r\n').first.split(' ').elementAt(1)) ?? 0;

    if (status >= 300 && status < 400) {
      final loc = RegExp(r'location:\s*(\S+)', caseSensitive: false)
          .firstMatch(head)
          ?.group(1);
      if (loc == null) return null;
      final next = current.resolve(loc);
      if (next.scheme == 'http' || next.scheme == 'https') {
        current = next;
        continue;
      }
      return null;
    }
    if (status != 200) return null;

    var body = bytes.sublist(sep + 4);
    if (head.toLowerCase().contains('transfer-encoding: chunked')) {
      body = _dechunk(body);
    }
    if (body.isEmpty) return null;
    return Uint8List.fromList(body);
  }
  return null;
}

/// 定位 \r\n\r\n（头/体分界）。
int _findHeaderEnd(List<int> b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

/// 解析 chunked 传输编码。
Uint8List _dechunk(List<int> b) {
  final out = BytesBuilder();
  var i = 0;
  while (i < b.length) {
    var j = i;
    while (j + 1 < b.length && !(b[j] == 13 && b[j + 1] == 10)) {
      j++;
    }
    if (j + 1 >= b.length) break;
    final sizeStr = latin1.decode(b.sublist(i, j)).split(';').first.trim();
    final size = int.tryParse(sizeStr, radix: 16);
    if (size == null || size == 0) break;
    final start = j + 2;
    if (start + size > b.length) break;
    out.add(b.sublist(start, start + size));
    i = start + size + 2; // 块体 + 尾部 CRLF
  }
  return out.toBytes();
}
