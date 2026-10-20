// 全局常量：后端地址与本地存储键。
const String kBaseUrl = 'https://music.2000321.xyz';
const String kCookieKey = 'ncm_cookie';
const String kStyleIndexKey = 'ncm_style_index';
const String kFavoritesKey = 'ncm_favorites';
const String kFavPlaylistsKey = 'ncm_favorite_playlists';
const String kPlayModeKey = 'ncm_play_mode';
const String kSearchHistoryKey = 'ncm_search_history';
// 登录页设置面板保存的 API 地址覆盖（AppConfig.load 时作为最高优先级读回）。
const String kApiBaseUrlKey = 'ncm_api_base_url';

// 歌曲音质等级（传给 /song/url/v1 的 level 参数）。
const List<String> kQualityLevels = ['standard', 'higher', 'exhigh', 'lossless', 'hires'];

/// 二维码本地有效时长（毫秒）。网易云 qr/key 默认 TTL 约 180s，
/// 客户端再叠加一道本地超时兜底：到点无论服务端是否返回 800 都强制失效。
const int kQrValidityMs = 180000; // 3 分钟
