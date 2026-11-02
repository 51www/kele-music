// IO 平台交付：移动端（Android/iOS）落临时文件后弹系统分享面板（share_plus），
// 用户可发微信/网盘/存到文件管理任意位置；桌面端用 file_picker 另存为对话框。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<bool> deliverBackupFileImpl(String filename, Uint8List bytes) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '可乐音乐数据备份',
        text: '在「设置 → 存储与隐私 → 导入备份」中选择此文件即可完成迁移。',
      );
      return true;
    }

    // 桌面：另存为对话框（传入 bytes 时由 file_picker 直接写盘并返回路径）。
    final path = await FilePicker.saveFile(
      fileName: filename,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return path != null;
  } catch (_) {
    return false;
  }
}
