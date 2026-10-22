import 'dart:convert';

import 'local_store_backend_io.dart'
    if (dart.library.html) 'local_store_backend_web.dart'
    if (dart.library.js_interop) 'local_store_backend_web.dart';

/// 同步、即时落盘的本地 KV 存储。
///
/// 平台后端由条件导入选择：
/// - IO 平台（Android/iOS/桌面）：文件持久化，每次写入 `writeAsStringSync(flush: true)`
///   立即 fsync。为什么不用 shared_preferences：其底层用 Android 的
///   `SharedPreferences.Editor.apply()`，是**异步**写盘。在 ColorOS / 多数国产 ROM 上，
///   从最近任务划掉应用 = 立即 force-kill 进程，未刷盘的写入会直接丢失，
///   表现为"每次关闭再打开，主题色 / 历史 / 设置都重置"。
/// - Web 平台：localStorage（本身同步读写）。
///
/// 本类在 `_bootstrap` 中 `await init()` 一次（runApp 之前），之后所有读写都是
/// 同步的，即使进程被立刻杀死，数据也已落盘，重新打开即可读回。
class LocalStore {
  LocalStore._();

  /// 必须在 runApp 之前 await 初始化。
  static late final LocalStore instance;

  final Map<String, dynamic> _data = {};

  /// 读取并解析本地状态；数据缺失/损坏时回落到空状态（不阻断启动）。
  static Future<LocalStore> init() async {
    Map<String, dynamic> data = {};
    final raw = await readPersistedState();
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // 数据损坏：忽略，相当于空状态重建。
      }
    }
    instance = LocalStore._().._data.addAll(data);
    return instance;
  }

  String? getString(String key) => _data[key] as String?;
  int? getInt(String key) => _data[key] as int?;
  bool? getBool(String key) => _data[key] as bool?;
  List<String>? getStringList(String key) {
    final v = _data[key];
    if (v is List) return List<String>.from(v);
    return null;
  }

  void setString(String key, String value) => _set(key, value);
  void setInt(String key, int value) => _set(key, value);
  void setBool(String key, bool value) => _set(key, value);
  void setStringList(String key, List<String> value) => _set(key, value);

  /// 删除某个键并立即落盘。
  void remove(String key) {
    _data.remove(key);
    _flush();
  }

  void _set(String key, dynamic value) {
    _data[key] = value;
    _flush();
  }

  /// 立即同步落盘（IO 平台含 fsync），保证进程被杀也不丢。
  void _flush() {
    writePersistedState(jsonEncode(_data));
  }
}
