import 'package:dio/dio.dart';
import '../core/errors.dart';
import 'app_config.dart';
import 'models.dart';

/// 类型化网易云 API 客户端，封装 Dio、cookie 注入与错误归一化。
/// 仅做 HTTP 与 JSON 层，不持有业务状态。
class NcmApi {
  final Dio _dio;
  String? _cookie;

  /// 登录态失效回调：当 checkCode=true 的接口返回 301（需要登录）时触发，
  /// 由认证层注册，用于统一把全局登录态翻成「未登录」并跳登录页。
  void Function()? onUnauthorized;

  /// 参数缺省时读取 AppConfig（main 在任何请求前已 load 完成），
  /// 支持通过配置文件 / --dart-define 灵活切换 API 地址与密钥。
  NcmApi({String? baseUrl, String? apiKey, int? connectTimeoutMs, int? receiveTimeoutMs})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? AppConfig.instance.baseUrl,
          connectTimeout: Duration(
              milliseconds:
                  connectTimeoutMs ?? AppConfig.instance.connectTimeoutMs),
          receiveTimeout: Duration(
              milliseconds:
                  receiveTimeoutMs ?? AppConfig.instance.receiveTimeoutMs),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Flutter ncm-client)',
            // 网关鉴权预留：apiKey 非空时自动附加。
            if ((apiKey ?? AppConfig.instance.apiKey).isNotEmpty)
              'X-API-Key': apiKey ?? AppConfig.instance.apiKey,
          },
        )) {
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
    ));
  }

  void setCookie(String? c) => _cookie = (c == null || c.isEmpty) ? null : c;
  String? get cookie => _cookie;

  /// 运行时切换 API 地址（登录页设置面板保存后调用，立即生效）。
  void setBaseUrl(String url) => _dio.options.baseUrl = url;

  Map<String, dynamic> _params(Map<String, dynamic>? params) {
    final q = <String, dynamic>{};
    if (params != null) q.addAll(params);
    if (_cookie != null) q['cookie'] = _cookie;
    return q;
  }

  /// [checkCode] 为 false 时不把非 200 code 当异常抛出，
  /// 用于二维码登录轮询等有「中间状态码」的端点（801/802/800/803）。
  /// 注意：GET 也必须带 timestamp——服务端部署在 Vercel，GET 响应带
  /// Cache-Control: max-age=120，浏览器/边缘节点会缓存同一 URL，
  /// 否则 qr/check 轮询永远拿到缓存里的旧「801 等待扫码」。
  Future<Map<String, dynamic>> get(String path,
      [Map<String, dynamic>? params, bool checkCode = true]) async {
    final q = _params(params)
      ..['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    try {
      final resp = await _dio.get(path, queryParameters: q);
      return _normalize(resp.data, checkCode: checkCode);
    } on DioException catch (e) {
      throw ApiException(e.response?.statusCode, _serverMessage(e));
    }
  }

  /// api-enhanced 要求 POST 带 timestamp 防止缓存。
  /// [checkCode] 同 get：二维码轮询等中间态端点需传 false。
  Future<Map<String, dynamic>> post(String path,
      [Map<String, dynamic>? params, bool checkCode = true]) async {
    final q = _params(params)
      ..['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    try {
      final resp = await _dio.post(path, queryParameters: q);
      return _normalize(resp.data, checkCode: checkCode);
    } on DioException catch (e) {
      throw ApiException(e.response?.statusCode, _serverMessage(e));
    }
  }

  /// 从 HTTP 层异常里提取服务端返回的业务错误消息（如「验证码错误」），
  /// 提取不到再按状态码给中文兜底——避免 dio 的英文原始文案漏到 UI。
  String _serverMessage(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      final m = d['message'] ?? d['msg'];
      if (m != null && m.toString().isNotEmpty) return m.toString();
    }
    final status = e.response?.statusCode ?? 0;
    if (status == 400) return '请求参数有误';
    if (status == 401) return '未登录或登录已失效';
    if (status == 429) return '请求过于频繁，请稍后再试';
    if (status >= 500) return '服务暂时不可用，请稍后再试';
    return '网络请求失败';
  }

  Map<String, dynamic> _normalize(dynamic data, {bool checkCode = true}) {
    if (data is! Map<String, dynamic>) {
      throw const ApiException(null, '返回数据格式异常');
    }
    final code = data['code'];
    if (checkCode && code is int && code != 200) {
      if (code == 301) onUnauthorized?.call();
      throw ApiException(code, (data['message'] ?? '请求失败').toString());
    }
    return data;
  }

  // ---- 业务端点（类型化封装） ----

  Future<List<BannerItem>> banners() async {
    final d = await get('/banner', {'type': 0});
    final list = d['banners'] as List? ?? [];
    return list.map((e) => BannerItem.fromJson(e)).toList();
  }

  Future<List<Song>> search(String keyword, {int limit = 30}) async {
    final d = await get('/search', {'keywords': keyword, 'limit': limit});
    final list = (d['result']?['songs'] as List? ?? []);
    return list.map((e) => Song.fromJson(e)).toList();
  }

  Future<List<Playlist>> personalizedPlaylists() async {
    final d = await get('/personalized');
    final list = (d['result'] as List? ?? []);
    return list.map((e) => Playlist.fromJson(e)).toList();
  }

  Future<List<Ranking>> rankings() async {
    final d = await get('/toplist');
    final list = (d['list'] as List? ?? []);
    return list.map((e) => Ranking.fromJson(e)).toList();
  }

  /// 新歌速递（无需登录），picUrl 在条目上，艺术家/时长在 song 内。
  Future<List<Song>> newSongs() async {
    final d = await get('/personalized/newsong');
    final list = (d['result'] as List? ?? []);
    return list.map((e) {
      final song = e['song'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return Song.fromJson(<String, dynamic>{
        'id': e['id'] ?? song['id'] ?? 0,
        'name': e['name'] ?? song['name'] ?? '',
        'album': <String, dynamic>{'picUrl': e['picUrl'] ?? song['album']?['picUrl'] ?? ''},
        'artists': song['artists'] ?? <dynamic>[],
        'duration': song['duration'] ?? 0,
        'fee': song['fee'] ?? 0,
      });
    }).toList();
  }

  /// 热搜关键词榜。/search/hot/detail 返回 data[].searchWord；
  /// 兼容旧版 /search/hot 的 result.hots[].first 结构。
  Future<List<String>> hotSearch() async {
    final d = await get('/search/hot/detail');
    final list = (d['data'] as List? ?? d['result']?['hots'] as List? ?? []);
    return list
        .map((e) => (e is Map
                ? (e['searchWord'] ?? e['first'] ?? '')
                : e)
            .toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 当前登录用户资料（未登录返回空 profile）。
  Future<UserProfile> userAccount() async {
    final d = await get('/user/account');
    final p = d['profile'] as Map<String, dynamic>?;
    if (p == null) return const UserProfile(userId: 0, nickname: '', avatarUrl: '');
    return UserProfile(
      userId: p['userId'] ?? 0,
      nickname: (p['nickname'] ?? '').toString(),
      avatarUrl: (p['avatarUrl'] ?? '').toString(),
    );
  }

  /// 用户自己创建的歌单：/user/playlist 返回「创建 + 收藏」合集，
  /// 这里过滤 userId == uid 的条目（含「我喜欢的音乐」）。需登录 cookie。
  Future<List<Playlist>> createdPlaylists(int uid) async {
    final d = await get('/user/playlist', {'uid': uid});
    final list = d['playlist'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .where((p) => (p['userId'] ?? p['creator']?['userId']) == uid)
        .map((e) => Playlist.fromJson(e))
        .toList();
  }

  /// 歌单详情：一次拿到元信息（收藏用）与完整曲目。
  Future<PlaylistDetail> playlistDetail(int id) async {
    final d = await get('/playlist/detail', {'id': id});
    final p = d['playlist'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final tracks = p['tracks'] as List? ?? d['songs'] as List? ?? [];
    return PlaylistDetail(
      playlist: Playlist.fromJson(p),
      tracks: tracks.map((e) => Song.fromJson(e)).toList(),
    );
  }

  Future<String?> songUrl(int id, {String level = 'standard'}) async {
    final d = await get('/song/url/v1', {'id': id, 'level': level});
    final list = (d['data'] as List? ?? []);
    if (list.isEmpty) return null;
    return (list.first['url'] as String?);
  }

  Future<Lyric> lyric(int id) async {
    final d = await get('/lyric', {'id': id});
    return Lyric.fromJson(d);
  }

  Future<void> dailySignin({int type = 0}) async {
    await post('/daily_signin', {'type': type});
  }
}
