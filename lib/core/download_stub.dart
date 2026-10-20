/// 非 Web 平台的下载桩：桌面/移动端暂未实现文件保存，
/// 返回 false 由调用方提示「当前平台暂不支持下载」。
Future<bool> downloadFile(String url, String filename) async => false;
