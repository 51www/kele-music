import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import 'api_client.dart';
import 'dev_cookie.dart';

/// 网易云对短信验证码登录校验「发送与登录同 IP」；Vercel 无服务器函数
/// 每次请求出口 IP 不同，正确验证码到登录一步也会被判无效（400）。
/// 两个接口统一携带相同的 realIP 规避（官方文档推荐做法）。
const String _captchaRealIP = '116.25.146.177';

/// 登录态仓库：cookie 持久化到安全存储，并提供手机验证码 / 二维码登录。
class AuthRepository {
  final NcmApi api;
  final FlutterSecureStorage _storage;

  AuthRepository(this.api, this._storage);

  /// 启动时从安全存储恢复登录态。
  /// 本地无 cookie 且开启 kUseDevCookie 时注入调试 cookie（仅开发用，见 dev_cookie.dart）。
  Future<void> init() async {
    final c = await _storage.read(key: kCookieKey);
    if (c != null && c.isNotEmpty) {
      api.setCookie(c);
    } else if (kUseDevCookie) {
      api.setCookie(kDevCookie);
    }
  }

  bool get isLoggedIn => api.cookie != null && api.cookie!.isNotEmpty;

  /// 校验并续期登录态：调用 /login/refresh 延长 cookie 有效期。
  /// 返回 true=仍有效并已续期；false=cookie 失效（通常是 301）；
  /// 其它异常（网络等）直接抛出，由调用方决定乐观保留还是登出。
  Future<bool> refresh() async {
    try {
      await api.post('/login/refresh');
      return true;
    } on ApiException catch (e) {
      if (e.code == 301) return false;
      rethrow;
    }
  }

  /// 仅清理本地登录态（不请求服务端），用于被服务端判定失效时立即登出。
  void clearLocal() {
    api.setCookie(null);
    _storage.delete(key: kCookieKey);
  }

  Future<void> sendCaptcha(String phone) =>
      api.post('/captcha/sent', {'phone': phone, 'realIP': _captchaRealIP});

  /// 手机 + 短信验证码登录（避开网易云盾对密码登录的限制）。
  Future<void> loginCellphone(String phone, String captcha) async {
    final data = await api.post('/login/cellphone', {
      'phone': phone,
      'countrycode': '86',
      'captcha': captcha,
      'realIP': _captchaRealIP,
    });
    _persist(data['cookie']);
  }

  Future<String> qrKey() async {
    final d = await api.get('/login/qr/key');
    return (d['data']?['unikey'] ?? '').toString();
  }

  Future<String> qrCreate(String key) async {
    final d = await api.get('/login/qr/create', {'key': key, 'qrimg': 1});
    return (d['data']?['qrimg'] ?? '').toString();
  }

  /// 轮询二维码状态：waiting / scanned / confirmed / expired
  /// 注意：qr/check 返回的 801/802/800/803 是轮询中间态，不是错误，
  /// 必须关闭 code 校验（checkCode=false），否则 _normalize 会抛飞。
  /// 另：部署的后端该路由只接受 POST（GET 返回 404 Not Found），必须用 post。
  Future<String> qrCheck(String key) async {
    final d = await api.post('/login/qr/check', {'key': key}, false);
    final code = d['code'] ?? 0;
    if (code == 803) {
      _persist(d['cookie']);
      return 'confirmed';
    }
    if (code == 800) return 'expired';
    if (code == 802) return 'scanned';
    return 'waiting';
  }

  void _persist(dynamic cookie) {
    final c = cookie?.toString();
    if (c != null && c.isNotEmpty) {
      api.setCookie(c);
      _storage.write(key: kCookieKey, value: c);
    }
  }

  Future<void> logout() async {
    // 调试 cookie 是共享的登录态，调 /logout 会在服务端把它作废，
    // 之后开发就没法用了——仅清本地，不打服务端。
    final isDevCookie = kUseDevCookie && api.cookie == kDevCookie;
    if (!isDevCookie) {
      try {
        await api.post('/logout');
      } catch (_) {
        // 忽略登出接口异常，本地清理为主。
      }
    }
    api.setCookie(null);
    await _storage.delete(key: kCookieKey);
  }
}
