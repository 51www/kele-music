import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import 'app_config.dart';
import 'mock_interceptor.dart';
import 'models.dart';
import 'throttle_interceptor.dart';

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
  /// [useMock] 优先级高于编译期 kUseMock：单测无法吃 --dart-define，
  /// 显式传 true 即可在测试中启用 mock；默认跟随 dart-define USE_MOCK。
  NcmApi({String? baseUrl, String? apiKey, int? connectTimeoutMs, int? receiveTimeoutMs, bool useMock = kUseMock})
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
    // 拦截器顺序即执行顺序：
    // 1) MockInterceptor（仅 USE_MOCK=1）：命中即短路，绝不拖慢/出网；
    // 2) ThrottleInterceptor：真实模式的频率闸门，防调试高频触发风控；
    // 3) LogInterceptor：日志。
    if (useMock) _dio.interceptors.add(MockInterceptor());
    _dio.interceptors.add(ThrottleInterceptor());
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

  /// 每日推荐歌单（需登录）：/recommend/resource 返回 recommend[]。
  /// 未登录/失败由调用方容错（301 等）。
  Future<List<Playlist>> recommendPlaylists() async {
    final d = await get('/recommend/resource');
    final list = (d['recommend'] as List? ?? []);
    return list.map((e) => Playlist.fromJson(e)).toList();
  }

  /// 每日推荐歌曲（需登录）：/recommend/songs 返回 data.dailySongs[]。
  /// 用于「每日推荐」独立页面；未登录会 301（onUnauthorized 触发统一登出）。
  Future<List<Song>> recommendSongs() async {
    final d = await get('/recommend/songs');
    final list = (d['data']?['dailySongs'] as List? ?? []);
    return list
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 全部歌单分类名列表：/playlist/catlist 的 sub[]（无需登录）。
  Future<List<String>> playlistCategories() async {
    final d = await get('/playlist/catlist');
    final subs = d['sub'] as List? ?? [];
    return subs
        .map((e) => (e['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 分类下的热门歌单：/top/playlist（order=hot），offset 翻页（无需登录）。
  /// cat 为空 = 全部。
  Future<List<Playlist>> topPlaylists(
      {String? cat, int offset = 0, int limit = 30}) async {
    final d = await get('/top/playlist', {
      'order': 'hot',
      'limit': limit,
      'offset': offset,
      if (cat != null && cat.isNotEmpty) 'cat': cat,
    });
    final list = d['playlists'] as List? ?? [];
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

  /// 用户收藏（别人创建）的歌单：/user/playlist 中 creator.userId != uid 的条目。
  Future<List<Playlist>> subscribedPlaylists(int uid) async {
    final d = await get('/user/playlist', {'uid': uid});
    final list = d['playlist'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().where((p) {
      final creator = p['creator'];
      final creatorId = p['userId'] ??
          (creator is Map<String, dynamic> ? creator['userId'] : null);
      return creatorId is int && creatorId != uid;
    }).map((e) => Playlist.fromJson(e)).toList();
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

  /// 喜欢/取消喜欢歌曲（写入网易云「我喜欢的音乐」，需登录）。
  /// like=true 收藏，like=false 取消；成功返回 code 200。
  Future<void> likeSong(int id, {required bool like}) async {
    await post('/like', {'id': id, 'like': like});
  }

  /// 收藏/取消收藏歌单（需登录）。t=1 收藏，t=2 取消。
  /// 业务码：502=已收藏过（重复收藏），501=未收藏过（重复取消）——幂等场景由调用方容忍。
  Future<void> subscribePlaylist(int id, {required bool subscribe}) async {
    await post('/playlist/subscribe', {'id': id, 't': subscribe ? 1 : 2});
  }

  /// 当前用户喜欢的歌曲 id 列表（需登录）：/likelist 返回 ids[]。
  Future<List<int>> likeList(int uid) async {
    final d = await get('/likelist', {'uid': uid});
    return (d['ids'] as List? ?? []).whereType<int>().toList();
  }

  /// 批量歌曲详情：/song/detail?ids=a,b,c（供喜欢列表还原 Song 模型）。
  /// ids 过长时分批由调用方控制（URL 长度限制）。
  Future<List<Song>> songsDetail(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final d = await get('/song/detail', {'ids': ids.join(',')});
    return (d['songs'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJson)
        .toList();
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
