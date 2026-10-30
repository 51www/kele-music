/// 文件完整性校验（跨平台）：Web 走 stub 返回 null（跳过校验），
/// 移动 / 桌面端用 dart:io + crypto 计算 SHA-256。
/// 条件导出顺序与 `download.dart` 一致：io 命中 `dart.library.io`，其余用 stub。
export 'update_verify_stub.dart'
    if (dart.library.io) 'update_verify_io.dart';
