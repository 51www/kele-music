/// IO 平台后端：单文件 JSON 持久化。
///
/// 为什么不用 shared_preferences：其底层用 Android 的
/// `SharedPreferences.Editor.apply()`，是**异步**写盘。在 ColorOS / 多数国产 ROM 上，
/// 从最近任务划掉应用 = 立即 force-kill 进程，未刷盘的写入会直接丢失。
/// 这里 init 时缓存文件句柄，之后每次写入都 `writeAsStringSync(flush: true)`
/// 立即落盘，进程被杀也不丢。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

File? _stateFile;

Future<String?> readPersistedState() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/app_state.json');
  _stateFile = file;
  if (!await file.exists()) return null;
  return file.readAsString();
}

void writePersistedState(String raw) {
  final file = _stateFile;
  if (file == null) return; // init 未完成（正常不会发生）
  try {
    file.writeAsStringSync(raw, flush: true);
  } catch (_) {
    // 写盘失败（如存储满）不影响本次会话的内存态。
  }
}
