# 三方网易云音乐 · 三端统一方案设计

> 技术路线：**Flutter 单一代码库（Android / macOS / Web）+ 自托管 API 网关（neteasecloudmusicapienhanced/api-enhanced）**
> 文档定位：架构设计 + 技术选型对比 + 分阶段实施计划。本次仅出方案，不落地代码。

---

## 0. 结论先行

1. **后端不用自己写加密/解灰**：`api-enhanced` 已把网易的 `weapi/eapi` 加密、登录态（cookie）、歌曲解灰（Unblock，多音源 qq/bodian/kuwo/kugou/migu/pyncmd）、FLAC 无损全部做成服务端。三端客户端只是**调这套 REST 接口的前端壳**。
2. **三端用 Flutter 一套代码**：Dart 单一代码库可同时产出 Android（移动）、macOS（桌面原生）、Web（浏览器/PWA）。复用率最高，且 `just_audio + audio_service` 原生支持**后台播放、锁屏/通知媒体控制、macOS Now Playing**，这是音乐 App 的刚需。
3. **架构主线**：`网易服务端(加密) ←→ API网关(自托管) ←→ Flutter三端`。客户端**绝不直连**网易，所有请求走自己的网关，网关负责加密、登录态与解灰。
4. **合规底线**：第三方非官方客户端属灰色地带，建议**个人学习/自用**，不公开分发、不商用、不营利；cookie 等敏感信息只存本地安全存储，不进前端代码库、不提交 `.env`。

---

## 部署状态（2026-10-19 已实测验证）

- **Base URL**：`https://music.2000321.xyz`（已部署 api-enhanced，HTTPS 正常）
- **接口文档**：`https://music.2000321.xyz/docs/`
- **P1 冒烟结果**：`/banner` `/search` `/check/music` `/personalized` `/song/url/v1` 均返回 200 与正确 JSON；**未登录即可搜索与拿推荐**。
- **CORS**：网关回显请求方 `Origin` 且 `Access-Control-Allow-Credentials: true`，Web 端跨域带 cookie 调用无障碍（生产建议把 `CORS_ALLOW_ORIGIN` 收敛为前端域名白名单）。
- **排行榜正确用法**：`/top/list` 必须用 `id` 参数（先 `/toplist` 取榜单 id），用 `idx` 会返回 500。
- **已知限制**：`fee:1` 等版权歌曲 `/song/url/v1` 返回 `freeTrialInfo`（试听片段），完整播放需登录会员账号；解灰(Unblock)可缓解部分灰歌。
- **登录建议**：`/login/cellphone` 因网易云盾，**优先用短信验证码(`/captcha/sent` + `captcha`)或二维码登录**，密码登录可能失败。

---

## 1. 为什么是 Flutter（三路线对比）

| 路线 | 代码复用率 | 原生体验 | 播放能力 | 你的学习成本 | 产物体积 |
|---|---|---|---|---|---|
| **Flutter 统一码（选）** | ★★★★★ 一套 Dart 出三端 | 移动/桌面原生，Web 接近原生 | `audio_service`+`just_audio` 跨端统一，后台/锁屏/通知齐全 | 需学 Dart（中等，1~2 周上手） | 中（桌面几十 MB） |
| Web 优先 + Tauri / RN | ★★★ Web 复用，壳分裂 | Web 好、Tauri 好、RN 好但三套 UI | 播放逻辑分散（Web Media Session / RN track-player） | 复用 Vue 技能，低 | 小（Tauri 极简） |
| 各端原生 | ★ 三套独立 | 各自最优 | 各平台最佳 | 三套技能栈，最高 | 小 |

**选定 Flutter 的理由**：三端目标是“同一个产品的不同形态”，不是三个不同产品；Flutter 把 UI、播放、状态管理统一在一套代码里，长期维护成本最低。你熟 Web，Dart 语法接近 JS/TS，迁移平滑。

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                      客户端层 (Flutter)                       │
│  Android App │ macOS App (桌面原生) │ Web / PWA               │
│  ─────────────────────────────────────────────────────────  │
│  UI(发现/搜索/歌单/播放/我的)  ← Riverpod 状态管理            │
│  PlayerService (audio_service + just_audio)  ← 队列/锁屏/通知 │
│  ApiClient (Dio)  ← 统一封装 + 错误映射 + cookie 注入         │
│  LocalStore (drift/SQLite + flutter_secure_storage)          │
└───────────────────────────┬─────────────────────────────────┘
                            │  HTTPS / JSON (CORS 限定来源)
┌───────────────────────────▼─────────────────────────────────┐
│               API 网关层 (自托管, api-enhanced)               │
│  Node.js · 端口 3000 · Docker / Vercel / Serverless          │
│   • weapi/eapi 加密   • 登录态/cookie 管理                    │
│   • 歌曲解灰 Unblock（多音源）  • FLAC 无损  • CORS 白名单    │
└───────────────────────────┬─────────────────────────────────┘
                            │  加密请求
┌───────────────────────────▼─────────────────────────────────┐
│            网易云音乐服务端（黑盒，客户端不直连）              │
└─────────────────────────────────────────────────────────────┘
```

**分层职责**
- **网关层**：唯一懂“网易加密”的地方。客户端拿到的是干净 JSON。
- **客户端层**：网络（Dio + 拦截器注入 cookie、错误映射）、播放（audio_service 后台 + 系统媒体控制）、本地（drift 离线歌单/搜索历史/已下载音频；secure_storage 存 cookie）。
- **平台适配**：Android 前台服务+媒体会话+通知；macOS 菜单栏/窗口/Now Playing/签名分发；Web PWA（manifest + Service Worker 离线壳）+ Media Session API + 音频跨域处理。

---

## 3. 后端部署（api-enhanced）

**推荐：Docker 自托管到一台小 VPS / 自有服务器**（解灰与稳定性最可控）。也可 Vercel / 腾讯云 Serverless。

关键环境变量（生产务必收敛，不要留 `*`）：

| 变量 | 建议值 | 说明 |
|---|---|---|
| `CORS_ALLOW_ORIGIN` | `https://你的域名` 或 `http://localhost:3000` | 生产禁用 `*`，只放行 Web 端来源 |
| `ENABLE_GENERAL_UNBLOCK` | `true` | 全局解灰，灰歌也能播 |
| `ENABLE_FLAC` | `true` | 无损音质 |
| `SELECT_MAX_BR` | `false` | 是否强制最高码率 |
| `UNBLOCK_SOURCE` | `pyncmd,qq,migu,kuwo,kugou,bodian` | 音源优先级 |
| `FOLLOW_SOURCE_ORDER` | `true` | 严格按列表顺序匹配 |
| `ENABLE_PROXY` / `PROXY_URL` | 按需 | 解灰需要代理时开启 |
| `PORT` | `3000` | 服务端口 |

**安全加固**：HTTPS 反向代理（Nginx/Caddy）；生产 CORS 白名单；cookie 仅存客户端安全存储；网关层可加轻量限流；`.env` 不提交仓库（加 `.gitignore`）。

---

## 4. 接口契约（客户端需要的端点，基于 api-enhanced/Binaryify 约定，落地前以官方文档核对）

| 能力 | 端点（示例） | 用途 |
|---|---|---|
| 手机登录 | `POST /login/cellphone` | 手机号+密码/验证码，返回 cookie |
| 邮箱登录 | `POST /login/email` | 邮箱登录 |
| 游客登录 | `POST /register/anonimous` 或游客机制 | 免登录试听 |
| 登出 | `POST /logout` | 清除 cookie |
| 用户详情 | `/user/detail` `/user/account` | 资料/等级 |
| 我的歌单 | `/user/playlist` | 收藏与创建歌单 |
| 搜索 | `/search` `/cloudsearch` | 单曲/歌手/专辑/歌单/歌词 |
| 歌曲 URL | `/song/url/v1?id=&level=` | `level`: standard/exhigh/lossless/hires；解灰后返回可播 URL |
| 歌曲详情 | `/song/detail` | 元数据 |
| 歌词 | `/lyric` | 逐字/普通歌词 |
| 评论 | `/comment/music` | 歌曲评论 |
| 歌单详情 | `/playlist/detail` `/playlist/track/all` | 曲目列表 |
| 专辑/歌手 | `/album` `/artist` `/artist/songs` | 详情与曲目 |
| 排行榜 | `/toplist`(榜单列表) → `/top/list?id=<id>`(详情) | 各类榜单（⚠️ top/list 用 id 不用 idx） |
| 推荐/日推 | `/recommend/songs` `/personalized` | 首页推荐 |
| 私人 FM | `/personal_fm` `/fm/trash` | 私人电台/垃圾桶 |
| 签到 | `/daily_signin` | 每日打卡 |
| 轮播 | `/banner` | 发现页 Banner |

> 客户端应封装一层**类型化 Dart API Client**（可基于 OpenAPI 生成或手写），把以上端点映射为 `Future<T>` 方法，并统一错误结构（`code/message`），避免散落硬编码 URL。

---

## 5. 三端适配要点

**Android**
- 权限：`INTERNET`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`（播放前台服务）。
- 媒体：配合 `audio_service` 实现通知栏播放控制 + 锁屏媒体控件。
- 产物：APK / AAB，上架非官方客户端不建议走 Google Play 公开分发，建议自有渠道。
- 图标/自适应图标、深色模式。

**macOS（桌面）**
- Flutter desktop 开启 macOS 支持；窗口管理、菜单栏、快捷键（空格播放/暂停）。
- 系统媒体控制：macOS Now Playing Center（audio_service 已支持）。
- 分发：通常走 DMG + Sparkle 自更新（非 App Store，音乐类客户端常见做法）；需开发者签名。
- 注意桌面端音频焦点/后台策略与移动不同。

**Web / PWA**
- `manifest.json` + Service Worker 做离线壳；首屏缓存。
- **音频跨域坑**：部分解灰音源 CDN 不带 CORS 头，浏览器 `<audio>` 会播放失败。缓解：让网关代理/转发音频流，或优先使用带 CORS 的网易官方 CDN 音源。
- `Media Session API` 实现锁屏/系统媒体控制。
- 自动播放策略：首次播放需用户手势触发；处理 `play()` 被拒。
- `CORS_ALLOW_ORIGIN` 必须包含 Web 部署域名。

---

## 6. 数据模型与本地存储

实体：`User` / `Playlist` / `Track` / `Album` / `Artist` / `Lyric` / `SearchHistory` / `DownloadedTrack`。

- **drift（SQLite）**：离线歌单、搜索历史、已下载音频索引、播放进度缓存。
- **flutter_secure_storage**：登录 cookie / token（iOS Keychain、Android Keystore、macOS Keychain、Web 用加密 localStorage）。
- **cached_network_image**：封面懒加载与缓存。

---

## 7. 推荐依赖（pubspec 草案）

```
flutter, flutter_riverpod, go_router,
dio, retrofit(可选), json_serializable,
audio_service, just_audio, just_audio_background(桌面),
drift, drift_flutter, flutter_secure_storage,
cached_network_image, share_plus(分享),
flutter_localizations
```

---

## 8. 目录结构（feature-first）

```
lib/
  main.dart
  app/            # 路由(go_router)、主题、启动引导
  core/           # 通用 widget / utils / 错误模型 / 常量
  data/
    api/          # 类型化 API Client (Dio) + 端点
    models/       # 实体 (json_serializable)
    local/        # drift 数据库 + secure_storage
  features/
    auth/         # 登录/游客/登出
    discover/     # 发现/轮播/排行榜/推荐
    search/       # 搜索
    library/      # 我的歌单/收藏/下载
    player/       # 播放页/队列/歌词/通知控制
    profile/      # 用户/签到/设置
  l10n/           # 多语言(中/英)
```

---

## 9. 分阶段实施计划

| 阶段 | 目标 | 关键动作 | 验收 |
|---|---|---|---|
| **P0 选型** | 锁定方案 | Flutter + api-enhanced，三端目标明确 | 本文档确认 |
| **P1 后端打通** | 网关可用 | Docker 起 api-enhanced；curl 验证 登录→搜索→歌曲URL→解灰；配置 CORS/HTTPS | 关键端点返回正确 JSON |
| **P2 脚手架+网络** | 客户端骨架 | `flutter create`；Dio 封装+cookie 注入+错误映射；类型化 API Client；登录流程（含游客） | Web 端能登录并拿到用户详情 |
| **P3 核心播放** | 能听歌 | `audio_service`+`just_audio`；播放/暂停/上一首下一首/队列/随机循环；锁屏/通知控制 | 三端均可后台播放+媒体控制 |
| **P4 功能模块** | 完整体验 | 发现/搜索/歌单/歌词/排行榜/私人FM/签到；drift 离线缓存 | 主流程走通 |
| **P5 三端适配** | 各自打磨 | Android 通知/前台服务；macOS 菜单/签名/Now Playing；Web PWA+音频跨域+Media Session | 三端独立可装可用 |
| **P6 测试加固** | 上线前 | 编译检查、冒烟、CORS/认证流联调、Web 双标签同步（如用实时）、合规文案、隐私说明 | 通过检查清单 |

---

## 10. 合规与风险（务必读）

- **性质**：非官方第三方客户端，处于灰色地带。api-enhanced 自身 MIT 且声明“遵守相关法律法规、尊重网易服务条款”。
- **版权**：音乐内容版权归各唱片公司/网易；**解灰**调用 qq/migu/kuwo 等第三方音源，可能涉及对方平台 ToS 与版权。强烈建议**仅个人学习/自用**。
- **分发**：不要公开上架应用商店盈利；不商用、不收费、不植入广告获利。
- **敏感信息**：cookie 仅存设备安全存储；网关 `.env` 不提交；生产 CORS 不开放 `*`。
- **网络**：境内访问/解灰/代理涉及合规，以自用研究为前提。
- **免责声明**：客户端内应内置“仅供学习交流，请支持正版”的声明。

---

## 11. 下一步建议

1. 先按 **P1** 把后端用 Docker 跑起来并 curl 验证（成本最低、风险最小，能立刻确认方案可行性）。
2. 确定一台部署机器（自有服务器 / 轻量云），配置域名 + HTTPS + CORS 白名单。
3. 确认是否要我进入 **P2**：搭 Flutter 脚手架并实跑通 Web 端登录→搜歌→播放的最小链路。

> 本方案默认：后端自托管、客户端个人自用、Flutter 3.x + Dart 3.x。落地前以 api-enhanced 最新文档核对端点与 Node 版本要求（仓库标注 Node 14+/18+，建议 18 LTS+）。
