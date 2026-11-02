// Web 平台：导入备份写回 localStorage 后刷新页面，全部模块按新数据重建。

// ignore: deprecated_member_use
import 'dart:html' as html;

Future<bool> tryRestartApp() async {
  try {
    html.window.location.reload();
    return true;
  } catch (_) {
    return false;
  }
}
