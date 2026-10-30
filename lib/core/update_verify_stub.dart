/// Web 平台无 dart:io：跳过文件校验。
/// APK 下载安装本就仅在 Android 生效，此实现只保证 Web 编译通过。
Future<String?> fileSha256(String path) async => null;
