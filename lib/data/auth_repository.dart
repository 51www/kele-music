import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import 'api_client.dart';

/// 调试用登录 cookie：只在编译期注入（`--dart-define=DEV_COOKIE=...`）。
///
/// 真实 cookie 属敏感信息，**不进仓库**（本地 `lib/data/dev_cookie.dart`
/// 已被 .gitignore 忽略），因此这里用 `String.fromEnvironment` 取值：
/// 干净检出与 CI 未注入时为空串，功能整体关闭，编译永远通过。
const String _devCookie = const String.fromEnvironment('DEV_COOKIE');
final bool _useDevCookie = _devCookie.isNotEmpty;

/// 平台对短信验证码登录校验「发送与登录同 IP」；Vercel 无服务器函数
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
    } else if (_useDevCookie) {
      api.setCookie(_devCookie);
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

  /// 手机 + 短信验证码登录（避开平台风控对密码登录的限制）。
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
    // 无参 GET，若不破缓存两次登录会复用 120s 内缓存的旧 unikey（可能已消费）。
    final d = await api.get('/login/qr/key', null, true, true);
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

  /// Cookie 登录兜底：手动粘贴有效登录态（含 MUSIC_U）直接建立会话，
  /// 绕过不稳定的短信验证码 / 二维码接口。
  /// 先以 /login/refresh 校验 cookie 是否仍有效；有效则持久化并视为登录成功。
  /// 校验失败（301 等）抛 ApiException，由调用方提示「Cookie 无效或已过期」。
  Future<void> loginWithCookie(String cookie) async {
    final c = cookie.trim();
    if (c.isEmpty) throw ApiException(null, '请输入 Cookie');
    final prev = api.cookie;
    api.setCookie(c);
    try {
      // 无效 cookie 由服务端返回 301（onUnauthorized 仅在 authenticated 态翻状态，这里无副作用）。
      await api.post('/login/refresh');
    } catch (e) {
      // 校验失败回滚内存态，避免无效 cookie 污染后续请求。
      api.setCookie(prev);
      rethrow;
    }
    _persist(c);
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
    final isDevCookie = _useDevCookie && api.cookie == _devCookie;
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
