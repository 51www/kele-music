import 'package:dio/dio.dart';

/// 请求频率闸门：按「路径桶」强制最小请求间隔，同桶请求串行排队。
///
/// 背景：开发调试时频繁刷新页面 / 反复走登录流程，会把官方接口
/// （经任意后端最终转发到 music.163.com）打到风控，导致账号被禁。
/// 本拦截器在 HTTP 层统一兜底，真实模式与 mock 模式共用：
/// mock 模式下它排在 MockInterceptor 之后，不会拖慢离线开发。
class ThrottleInterceptor extends Interceptor {
  /// 同桶请求的最小间隔（毫秒）。按「路径前缀」区分桶，顺序敏感：前缀长的必须在前。
  /// 命中同一前缀的请求共享一个桶（串行 + 最小间隔）；不同前缀属于不同桶，互不排队。
  /// 这样发现页四个并行接口（/personalized、/toplist、/personalized/newsong、
  /// /recommend/resource）各占一桶，能真正同时发出，不会被串行拖慢。
  static const List<MapEntry<String, int>> _rules = [
    MapEntry('/login/refresh', 10 * 60 * 1000), // 续期：10 分钟最多一次
    MapEntry('/login/qr/check', 4000), // QR 轮询：≥4s/次（官方建议间隔）
    MapEntry('/login/', 10 * 1000), // 其它登录动作：≥10s/次
    MapEntry('/captcha/', 30 * 1000), // 短信验证码：≥30s/次（发送本身有频控）
    MapEntry('/daily_signin', 10 * 60 * 1000), // 签到：写操作，限 10 分钟
  ];

  static const int _defaultIntervalMs = 250; // 普通查询接口的温和间隔

  final Map<String, DateTime> _lastAt = {};
  final Map<String, Future<void>> _chains = {};

  /// 默认按完整路径分桶（互不排队），但对同一路径仍强制最小间隔，
  /// 保留「防高频触发风控」的兜底作用。
  (String, int) _match(String path) {
    for (final r in _rules) {
      if (path.startsWith(r.key)) return (r.key, r.value);
    }
    return (path, _defaultIntervalMs);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final (bucket, interval) = _match(options.path);
    final prev = _chains[bucket] ?? Future<void>.value();
    // 同桶请求排队：每个请求等「前一个完成 + 距上次发出 ≥ interval」。
    final next = prev.then((_) async {
      final last = _lastAt[bucket];
      if (last != null) {
        final wait = interval - DateTime.now().difference(last).inMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      }
      _lastAt[bucket] = DateTime.now();
    });
    // 链上异常不能卡死后续请求。
    _chains[bucket] = next.catchError((_) {});
    next.then((_) => handler.next(options));
  }
}
