/// 跨平台下载辅助：Web 走 Blob + <a download>；移动/桌面端经平台通道
/// 写入系统 Download 目录（Android 10+ MediaStore，无需存储权限）。
/// 条件导出顺序：Web 优先命中 dart.library.html，其余命中 dart.library.io。
export 'download_stub.dart'
    if (dart.library.html) 'download_web.dart'
    if (dart.library.io) 'download_io.dart';
