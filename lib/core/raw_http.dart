/// 裸 Socket HTTP GET（平台条件导入）：
/// - IO 平台（Android/iOS/桌面）：真实实现（dart:io Socket 手工拼报文）；
/// - Web：桩实现（浏览器有 <img>/XHR 可用，无需此兜底）。
export 'raw_http_stub.dart' if (dart.library.io) 'raw_http_io.dart';
