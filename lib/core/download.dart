/// 跨平台下载辅助：Web 平台走 Blob + <a download>，其余平台为桩实现。
export 'download_stub.dart' if (dart.library.html) 'download_web.dart';
