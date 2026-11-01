// 非 Web 平台的下载桩：桌面/移动端暂未实现文件保存，
// 返回 false 由调用方提示「当前平台暂不支持下载」。
// [onBytes] 仅为与其他平台签名一致，本实现不会触发。
import 'dart:typed_data' show Uint8List;

Future<bool> downloadFile(String url, String filename,
        {void Function(int received, int total)? onProgress,
        void Function(Uint8List bytes)? onBytes}) async =>
    false;
