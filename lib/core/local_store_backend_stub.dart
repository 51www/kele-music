/// 平台持久化后端（由条件导入选择实现，本文件是兜底空实现）。
///
/// 实际生效的实现：
/// - IO 平台（Android/iOS/桌面）→ `local_store_backend_io.dart`（文件 + fsync）
/// - Web 平台 → `local_store_backend_web.dart`（localStorage，同步读写）
library;

Future<String?> readPersistedState() async => null;

void writePersistedState(String raw) {}
