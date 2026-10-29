// 全局常量：后端地址与本地存储键。
// 默认走自建 Vercel 部署（api-enhanced，HTTPS 正常）：https://music.2000321.xyz
// 地址不带末尾斜杠（约定见 docs/api-config.md），AppConfig 载入时会自动归一。
// 需要切到公共实例（iwenwiki，延迟更低但只有 HTTP）时，在登录页/设置页把

const String kBaseUrl = 'https://music.2000321.xyz';
const String kCookieKey = 'ncm_cookie';
const String kStyleIndexKey = 'ncm_style_index';
// 收藏（歌曲喜欢/歌单收藏）已迁移到云端接口（/like、/playlist/subscribe），
// 不再使用本地 KV 存储（原 ncm_favorites / ncm_favorite_playlists 键已废弃）。
const String kPlayModeKey = 'ncm_play_mode';
const String kSearchHistoryKey = 'ncm_search_history';
// 播放历史（本地持久化）：最新在前、按歌曲去重、最多保留 kHistoryMax 条。
const String kHistoryKey = 'ncm_history';
const int kHistoryMax = 100;
// 断点续听：播放队列快照 {songs, index, positionMs}，App 启动时恢复为暂停态。
const String kQueueSnapshotKey = 'ncm_queue_snapshot';
// 登录页设置面板保存的 API 地址覆盖（AppConfig.load 时作为最高优先级读回）。
const String kApiBaseUrlKey = 'ncm_api_base_url';

// 离线 Mock 开发模式：--dart-define=USE_MOCK=true 时所有请求不出网（含登录 QR），
// 日常开发用这个模式，避免高频调用官方接口触发风控（见 data/mock_interceptor.dart）。
// 注意：bool.fromEnvironment 只认字面 "true"，传 1 不生效！
const bool kUseMock = bool.fromEnvironment('USE_MOCK');

// 歌曲音质等级（传给 /song/url/v1 的 level 参数）。
const List<String> kQualityLevels = ['standard', 'higher', 'exhigh', 'lossless', 'hires'];
// 音质档位展示文案与码率说明（与 kQualityLevels 一一对应）。
const List<(String, String)> kQualityLabels = [
  ('标准', '128K'),
  ('较高', '192K'),
  ('极高', '320K'),
  ('无损', 'FLAC'),
  ('Hi-Res', '192K/24bit'),
];
// 播放设置持久化键：在线播放音质 / 下载音质。
const String kPlayQualityKey = 'ncm_play_quality';
const String kDownloadQualityKey = 'ncm_download_quality';

// 播放页视觉模式：vinylWave=黑胶唱片+波形线动效（默认）；
// classic=经典静态唱片封面+水波纹扩散。设置页可切换，本地持久化。
const String kNowPlayingVisualKey = 'ncm_now_playing_visual';
const String kVisualVinylWave = 'vinylWave';
const String kVisualClassic = 'classic';
const List<String> kNowPlayingVisuals = [kVisualVinylWave, kVisualClassic];
// 与 kNowPlayingVisuals 一一对应的展示文案（名称, 描述）。
const List<(String, String)> kNowPlayingVisualLabels = [
  ('黑胶动效', '唱片旋转 + 波形律动'),
  ('经典静态', '静态唱片 + 水波纹'),
];

/// 二维码本地有效时长（毫秒）。平台 qr/key 默认 TTL 约 180s，
/// 客户端再叠加一道本地超时兜底：到点无论服务端是否返回 800 都强制失效。
const int kQrValidityMs = 180000; // 3 分钟

/// 合成「每日推荐」歌单 id（「个人专属」板块首卡，点击直接起播每日推荐歌曲）。
/// 用负 id 避免与真实歌单 id 冲突；/recommend/resource 需登录，
/// 接口拉不到时由 discovery 用此 id 合成一个始终可见的入口（封面借首张真实歌单）。
const int kDailyRecommendId = -1001;
