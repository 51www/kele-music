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

  /// 设置面板展示 / 编辑用的原始地址：保留「?」后的全部内容（含 sharecode
  /// 与其它 query 参数），避免「保存后丢 ? 后面内容」的错觉。
  /// 无用户自定义时回落到内置默认（与 baseUrl 同值，通常无 query）。
  final String rawUrl;

  /// 网关鉴权预留：非空时 NcmApi 自动附加 X-API-Key 请求头。
  final String apiKey;

  /// WorkBuddy 托管网关分享码：非空时 NcmApi 给每个请求附加
  /// sharecode 查询参数（从完整链接 ?sharecode=... 解析而来）。
  final String shareCode;
  final int connectTimeoutMs;
  final int receiveTimeoutMs;

  const AppConfig({
    required this.baseUrl,
    required this.rawUrl,
    required this.apiKey,
    required this.shareCode,
    required this.connectTimeoutMs,
    required this.receiveTimeoutMs,
  });

  /// 编译期环境兜底（--dart-define）。
  factory AppConfig.fromEnvironment() {
    final raw = const String.fromEnvironment('API_BASE_URL',
        defaultValue: kBaseUrl);
    final (url, code) = _splitShareCode(raw);
    final defineCode = const String.fromEnvironment('API_SHARE_CODE');
    return AppConfig(
      baseUrl: _normalizeUrl(url),
      rawUrl: raw,
      apiKey: const String.fromEnvironment('API_KEY'),
      shareCode: defineCode.isNotEmpty ? defineCode : code,
      connectTimeoutMs: const int.fromEnvironment('API_CONNECT_TIMEOUT_MS',
          defaultValue: 15000),
      receiveTimeoutMs: const int.fromEnvironment('API_RECEIVE_TIMEOUT_MS',
          defaultValue: 20000),
    );
  }

  /// 设置页展示 / 编辑用的原始地址：保留「?」后的全部内容（含 sharecode）。
  /// 无用户自定义时回落到 baseUrl 本身。
  String get displayUrl => rawUrl.isNotEmpty ? rawUrl : baseUrl;

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

        final (aUrl, aCode) = _splitShareCode(pick('baseUrl', cfg.rawUrl));
        cfg = AppConfig(
          baseUrl: _normalizeUrl(aUrl),
          rawUrl: pick('baseUrl', cfg.rawUrl),
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
            rawUrl: saved,
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
  /// "https://host/?sharecode=ABC&foo=1" → ('https://host/?foo=1', 'ABC')。
  /// sharecode 被拆出单独存储并随每个请求附加；其余 query 参数（含路径）
  /// 一律保留进 baseUrl，避免「保存后丢 ? 后面内容」。
  /// 无 sharecode 时原样返回（'', 保留原串避免破坏非标准写法）。
  static (String, String) _splitShareCode(String raw) {
    final u = Uri.tryParse(raw.trim());
    final code = u?.queryParameters['sharecode'];
    if (u == null || code == null || code.isEmpty) return (raw, '');
    final rest = Map<String, String>.from(u.queryParameters)..remove('sharecode');
    final query = rest.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final host = u.hasPort ? '${u.host}:${u.port}' : u.host;
    final pathAndQuery = u.path + (query.isNotEmpty ? '?$query' : '');
    return ('${u.scheme}://$host$pathAndQuery', code);
  }

  /// 设置面板保存 baseUrl：更新单例（当前会话立即生效）+ 持久化（下次启动生效）。
  /// 支持直接粘贴带 ?sharecode=... 的完整链接：sharecode 被拆出存入实例，
  /// 持久化时保留用户原始串（含全部 ? 后内容），下次 load 能再次解析、回显不丢。
  static Future<void> saveBaseUrl(String url) async {
    final raw = url.trim();
    final (u, code) = _splitShareCode(raw);
    final normalized = _normalizeUrl(u);
    _instance = AppConfig(
        baseUrl: normalized,
        rawUrl: raw,
        apiKey: _instance.apiKey,
        shareCode: code.isNotEmpty ? code : '',
        connectTimeoutMs: _instance.connectTimeoutMs,
        receiveTimeoutMs: _instance.receiveTimeoutMs);
    // 持久化原始输入，保证「?」后的 sharecode 与任何其它 query 都不丢。
    LocalStore.instance.setString(kApiBaseUrlKey, raw);
    debugPrint('[AppConfig] baseUrl saved: $raw');
  }

  /// 恢复默认 baseUrl：清除保存的覆盖后重载（回落到 asset / dart-define / 内置默认值），
  /// 当前会话立即生效。用于排查"saved 值覆盖默认配置"的问题。
  static Future<void> resetBaseUrl() async {
    LocalStore.instance.remove(kApiBaseUrlKey);
    await load();
    debugPrint('[AppConfig] baseUrl reset to default: ${_instance.baseUrl}');
  }
}
