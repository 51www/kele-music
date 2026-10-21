import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

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
  final int connectTimeoutMs;
  final int receiveTimeoutMs;

  const AppConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.connectTimeoutMs,
    required this.receiveTimeoutMs,
  });

  /// 编译期环境兜底（--dart-define）。
  factory AppConfig.fromEnvironment() => AppConfig(
        baseUrl: const String.fromEnvironment('API_BASE_URL',
            defaultValue: kBaseUrl),
        apiKey: const String.fromEnvironment('API_KEY'),
        connectTimeoutMs: const int.fromEnvironment('API_CONNECT_TIMEOUT_MS',
            defaultValue: 15000),
        receiveTimeoutMs: const int.fromEnvironment('API_RECEIVE_TIMEOUT_MS',
            defaultValue: 20000),
      );

  static AppConfig _instance = AppConfig.fromEnvironment();

  /// 全局唯一实例：main 里 load() 之后方可访问（NcmApi 构造时读取）。
  static AppConfig get instance => _instance;

  /// 在 main() 里 runApp 之前 await 调用。
  /// 配置文件缺失/损坏时静默回落到 dart-define / 默认值，不阻断启动。
  static Future<AppConfig> load(
      {String assetPath = 'assets/config/app_config.json'}) async {
    var cfg = _instance;
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

        cfg = AppConfig(
          baseUrl: pick('baseUrl', cfg.baseUrl),
          apiKey: pick('apiKey', cfg.apiKey),
          connectTimeoutMs: pickInt('connectTimeoutMs', cfg.connectTimeoutMs),
          receiveTimeoutMs: pickInt('receiveTimeoutMs', cfg.receiveTimeoutMs),
        );
      }
    } catch (e) {
      debugPrint('[AppConfig] load failed ($assetPath): $e');
    }
    // 用户保存的覆盖（登录页设置面板）：最高优先级。
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getString(kApiBaseUrlKey);
      if (saved != null && saved.trim().isNotEmpty) {
        cfg = AppConfig(
            baseUrl: saved.trim(),
            apiKey: cfg.apiKey,
            connectTimeoutMs: cfg.connectTimeoutMs,
            receiveTimeoutMs: cfg.receiveTimeoutMs);
      }
    } catch (_) {
      // 存储不可用时忽略，沿用上面的配置。
    }
    _instance = cfg;
    debugPrint('[AppConfig] baseUrl=${cfg.baseUrl} '
        'apiKey=${cfg.apiKey.isEmpty ? '<empty>' : '<set>'} '
        'timeouts=${cfg.connectTimeoutMs}/${cfg.receiveTimeoutMs}ms');
    return cfg;
  }

  /// 设置面板保存 baseUrl：更新单例（当前会话立即生效）+ 持久化（下次启动生效）。
  static Future<void> saveBaseUrl(String url) async {
    final u = url.trim();
    _instance = AppConfig(
        baseUrl: u,
        apiKey: _instance.apiKey,
        connectTimeoutMs: _instance.connectTimeoutMs,
        receiveTimeoutMs: _instance.receiveTimeoutMs);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kApiBaseUrlKey, u);
    debugPrint('[AppConfig] baseUrl saved: $u');
  }

  /// 恢复默认 baseUrl：清除保存的覆盖后重载（回落到 asset / dart-define / 内置默认值），
  /// 当前会话立即生效。用于排查"saved 值覆盖默认配置"的问题。
  static Future<void> resetBaseUrl() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(kApiBaseUrlKey);
    await load();
    debugPrint('[AppConfig] baseUrl reset to default: ${_instance.baseUrl}');
  }
}
