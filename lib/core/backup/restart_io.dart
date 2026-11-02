// IO 平台：Android/iOS 用 restart_app 重启进程（1.10.2 返回结构化结果，
// 参数全部可选）；桌面端按方案不做自动重启，返回 false 由 UI 提示手动重启。

import 'dart:io';

import 'package:restart_app/restart_app.dart';

Future<bool> tryRestartApp() async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final result = await Restart.restartApp();
      return result.success;
    } catch (_) {
      return false;
    }
  }
  return false;
}
