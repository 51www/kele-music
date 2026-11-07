import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'constants.dart';
import 'local_store.dart';

/// 全局统一的安全存储实例：所有读写必须用同一份配置，否则 macOS 上
/// 「写入用 A 配置、读取用 B 配置」会因钥匙串不同项而互相读不到。
///
/// macOS 背景：Release 包为 adhoc 签名（TeamIdentifier=not set），而
/// flutter_secure_storage_macos 默认启用 `kSecUseDataProtectionKeyChain`
/// （数据保护钥匙串），它要求有效 Team ID + keychain entitlement，
/// 沙盒内 `SecItemAdd` 会直接失败 → 登录 cookie 无法保存，表现为
/// 「导入配置后绑定账号不生效 / 登录态重启即丢」。
/// 关闭该选项后使用沙盒容器内的传统钥匙串，无需 Team ID 即可读写。
///
/// `mOptions` 仅作用于 macOS；Android / iOS / 其它平台沿用插件默认配置，
/// 因此手机端行为与改动前完全一致。
const FlutterSecureStorage kSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);

/// 仅 macOS 启用的兜底键：钥匙串彻底不可用（如 adhoc 签名 + 沙盒）时，
/// 把登录 cookie 退到应用沙盒私有的 app_state.json（已验证可写），
/// 保证导入的账号重启后仍在。手机端不启用，行为不变。
const String kCookieFallbackKey = 'ncm_cookie_fallback';

bool get _macFallback =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// 读取登录 cookie，按「统一钥匙串 → 旧数据保护钥匙串 → macOS 兜底」顺序。
/// 主路径命中即返回；手机端首次就命中，无额外开销。
Future<String?> readCookie() async {
  try {
    final v = await kSecureStorage.read(key: kCookieKey);
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {
    // 钥匙串不可用：走兼容 / 兜底路径。
  }
  try {
    final v = await const FlutterSecureStorage().read(key: kCookieKey);
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {
    // 兼容路径也不可用：继续兜底。
  }
  if (_macFallback) {
    final v = LocalStore.instance.getString(kCookieFallbackKey);
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// 写入登录 cookie。返回 true 表示已持久化（重启后仍在），
/// false 表示仅能保留在本次会话内存中。
Future<bool> writeCookie(String value) async {
  try {
    await kSecureStorage.write(key: kCookieKey, value: value);
    // 同时清掉旧版本（数据保护钥匙串）残留，避免 readCookie 的兼容路径
    // 读回更早的过期 cookie 覆盖刚写入的新值。
    try {
      await const FlutterSecureStorage().delete(key: kCookieKey);
    } catch (_) {
      // 旧通道不可用，忽略。
    }
    // 钥匙串恢复可用后清掉旧的兜底副本，避免两处数据不一致。
    if (_macFallback) LocalStore.instance.remove(kCookieFallbackKey);
    return true;
  } catch (_) {
    if (!_macFallback) return false;
    // 仅 macOS：落到沙盒私有文件，确保导入账号重启后不丢。
    LocalStore.instance.setString(kCookieFallbackKey, value);
    return true;
  }
}

/// 清除登录态（新旧两个钥匙串通道 + 兜底副本一起清，
/// 避免登出后重启又被兼容读取读回）。
Future<void> deleteCookie() async {
  try {
    await kSecureStorage.delete(key: kCookieKey);
  } catch (_) {
    // 钥匙串不可用时忽略，兜底副本仍需清理。
  }
  try {
    await const FlutterSecureStorage().delete(key: kCookieKey);
  } catch (_) {
    // 旧通道不可用，忽略。
  }
  if (_macFallback) LocalStore.instance.remove(kCookieFallbackKey);
}
