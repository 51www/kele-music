// 全局常量：后端地址与本地存储键。
// 默认走公共实例（iwenwiki，Binaryify NeteaseCloudMusicApi 部署），
// 实测延迟 0.13~0.25s，约为自建 Vercel（music.2000321.xyz，1.4~2s）的 1/8；
// CORS 全放开、QR 登录 GET/POST 均支持。注意它只有 HTTP（https 不通），
// Android 需 usesCleartextTraffic=true（已配置），web 本地调试 http 无影响。
// 自建后端可作为备选：在登录页/设置页把 API 地址改回 https://music.2000321.xyz 即可。
const String kBaseUrl = 'http://iwenwiki.com:3000';
// 备选：自建 Vercel 部署（较慢但自主可控）。
const String kFallbackBaseUrl = 'https://music.2000321.xyz';
const String kCookieKey = 'ncm_cookie';
const String kStyleIndexKey = 'ncm_style_index';
const String kFavoritesKey = 'ncm_favorites';
const String kFavPlaylistsKey = 'ncm_favorite_playlists';
const String kPlayModeKey = 'ncm_play_mode';
const String kSearchHistoryKey = 'ncm_search_history';
// 播放历史（本地持久化）：最新在前、按歌曲去重、最多保留 kHistoryMax 条。
const String kHistoryKey = 'ncm_history';
const int kHistoryMax = 100;
// 登录页设置面板保存的 API 地址覆盖（AppConfig.load 时作为最高优先级读回）。
const String kApiBaseUrlKey = 'ncm_api_base_url';

// 歌曲音质等级（传给 /song/url/v1 的 level 参数）。
const List<String> kQualityLevels = ['standard', 'higher', 'exhigh', 'lossless', 'hires'];

/// 二维码本地有效时长（毫秒）。网易云 qr/key 默认 TTL 约 180s，
/// 客户端再叠加一道本地超时兜底：到点无论服务端是否返回 800 都强制失效。
const int kQrValidityMs = 180000; // 3 分钟
