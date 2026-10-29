import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/constants.dart';
import '../core/local_store.dart';

/// API 接入层配置：应用初始化前（main 中 runApp 之前）加载完成。
///
/// 加载优先级（高 → 低）：
/// 1. 用户保存（登录页设置面板，SharedPreferences 持久化）
/// 2. assets/config/app_config.json —— 运行时覆盖，改文件无需重新编译
/// 3. --dart-define=API_BASE_URL=... —— 编译期注入，适合 CI / 多环境打包
/// 4. 内置默认值（constants.dart 的 kBaseUrl 等）
///
/// 登录依赖 baseUrl，因此本类必须在任何 API 调用（含登录）之前完成加载。
class AppConfig {
  final String baseUrl;

  /// 网关鉴权预留：非空时 NcmApi 自动附加 X-API-Key 请求头。
  final String apiKey;

  /// WorkBuddy 托管网关分享码：非空时 NcmApi 给每个请求附加
  /// sharecode 查询参数（从完整链接 ?sharecode=... 解析而来）。
  final String shareCode;
  final int connectTimeoutMs;
  final int receiveTimeoutMs;

  const AppConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.shareCode,
    required this.connectTimeoutMs,
    required this.receiveTimeoutMs,
  });

  /// 编译期环境兜底（--dart-define）。
  factory AppConfig.fromEnvironment() {
    final (url, code) = _splitShareCode(const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: kBaseUrl));
    final defineCode = const String.fromEnvironment('API_SHARE_CODE');
    return AppConfig(
      baseUrl: _normalizeUrl(url),
      apiKey: const String.fromEnvironment('API_KEY'),
      shareCode: defineCode.isNotEmpty ? defineCode : code,
      connectTimeoutMs: const int.fromEnvironment('API_CONNECT_TIMEOUT_MS',
          defaultValue: 15000),
      receiveTimeoutMs: const int.fromEnvironment('API_RECEIVE_TIMEOUT_MS',
          defaultValue: 20000),
    );
  }

  static AppConfig _instance = AppConfig.fromEnvironment();

  /// 全局唯一实例：main 里 load() 之后方可访问（NcmApi 构造时读取）。
  static AppConfig get instance => _instance;

  /// 在 main() 里 runApp 之前 await 调用。
  /// 配置文件缺失/损坏时静默回落到 dart-define / 默认值，不阻断启动。
  static Future<AppConfig> load(
      {String assetPath = 'assets/config/app_config.json'}) async {
    // 从「纯净默认」（dart-define / 内置值）起步重算，不从当前 _instance：
    // 否则「恢复默认地址」（删 saved 后重载）时 _instance 已被用户保存值污染，
    // asset 为空又会回落到 cfg.baseUrl 自身，永远算不回内置默认。
    var cfg = AppConfig.fromEnvironment();
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        String pick(String key, String fallback) {
          final v = json[key];
          return (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;
        }

        int pickInt(String key, int fallback) {
          final v = json[key];
          return (v is int && v > 0) ? v : fallback;
        }

        final (aUrl, aCode) = _splitShareCode(pick('baseUrl', cfg.baseUrl));
        cfg = AppConfig(
          baseUrl: _normalizeUrl(aUrl),
          apiKey: pick('apiKey', cfg.apiKey),
          shareCode: pick('shareCode', aCode.isNotEmpty ? aCode : cfg.shareCode),
          connectTimeoutMs: pickInt('connectTimeoutMs', cfg.connectTimeoutMs),
          receiveTimeoutMs: pickInt('receiveTimeoutMs', cfg.receiveTimeoutMs),
        );
      }
    } catch (e) {
      debugPrint('[AppConfig] load failed ($assetPath): $e');
    }
    // 用户保存的覆盖（登录页/设置面板）：最高优先级，保存什么就用什么。
    try {
      final saved = LocalStore.instance.getString(kApiBaseUrlKey);
      if (saved != null && saved.trim().isNotEmpty) {
        final (sUrl, sCode) = _splitShareCode(saved);
        cfg = AppConfig(
            baseUrl: _normalizeUrl(sUrl),
            apiKey: cfg.apiKey,
            shareCode: sCode.isNotEmpty ? sCode : cfg.shareCode,
            connectTimeoutMs: cfg.connectTimeoutMs,
            receiveTimeoutMs: cfg.receiveTimeoutMs);
      }
    } catch (_) {
      // 存储不可用时忽略，沿用上面的配置。
    }
    _instance = cfg;
    debugPrint('[AppConfig] baseUrl=${cfg.baseUrl} '
        'apiKey=${cfg.apiKey.isEmpty ? '<empty>' : '<set>'} '
        'shareCode=${cfg.shareCode.isEmpty ? '<empty>' : '<set>'} '
        'timeouts=${cfg.connectTimeoutMs}/${cfg.receiveTimeoutMs}ms');
    return cfg;
  }

  /// 地址归一：去空白 + 去掉末尾斜杠（约定 baseUrl 不带末尾斜杠，
  /// 见 docs/api-config.md）。只裁路径部分的斜杠，scheme 后的主机名保留，
  /// 因此 "https://music.2000321.xyz/" → "https://music.2000321.xyz"。
  static String _normalizeUrl(String raw) {
    final u = raw.trim();
    final i = u.indexOf('://');
    if (i < 0) return u;
    final scheme = u.substring(0, i + 3);
    final rest = u.substring(i + 3).replaceFirst(RegExp(r'/+$'), '');
    return rest.isEmpty ? u : '$scheme$rest';
  }

  /// 从完整链接中拆出 WorkBuddy 网关分享码：
  /// "https://host/?sharecode=ABC" → ('https://host', 'ABC')。
  /// 无 sharecode 时原样返回（'', 保留原串避免破坏非标准写法）。
  static (String, String) _splitShareCode(String raw) {
    final u = Uri.tryParse(raw.trim());
    final code = u?.queryParameters['sharecode'];
    if (u == null || code == null || code.isEmpty) return (raw, '');
    final host = u.hasPort ? '${u.host}:${u.port}' : u.host;
    return ('${u.scheme}://$host${u.path}', code);
  }

  /// 设置面板保存 baseUrl：更新单例（当前会话立即生效）+ 持久化（下次启动生效）。
  /// 支持直接粘贴带 ?sharecode=... 的完整链接：sharecode 被拆出存入实例，
  /// 持久化时保留在原始串里，下次 load 能再次解析。
  static Future<void> saveBaseUrl(String url) async {
    final (u, code) = _splitShareCode(url);
    final normalized = _normalizeUrl(u);
    _instance = AppConfig(
        baseUrl: normalized,
        apiKey: _instance.apiKey,
        shareCode: code.isNotEmpty ? code : '',
        connectTimeoutMs: _instance.connectTimeoutMs,
        receiveTimeoutMs: _instance.receiveTimeoutMs);
    final savedUrl =
        code.isNotEmpty ? '$normalized?sharecode=$code' : normalized;
    LocalStore.instance.setString(kApiBaseUrlKey, savedUrl);
    debugPrint('[AppConfig] baseUrl saved: $savedUrl');
  }

  /// 恢复默认 baseUrl：清除保存的覆盖后重载（回落到 asset / dart-define / 内置默认值），
  /// 当前会话立即生效。用于排查"saved 值覆盖默认配置"的问题。
  static Future<void> resetBaseUrl() async {
    LocalStore.instance.remove(kApiBaseUrlKey);
    await load();
    debugPrint('[AppConfig] baseUrl reset to default: ${_instance.baseUrl}');
  }
}
