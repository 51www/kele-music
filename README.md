# 在线音乐客户端（kele-music 可乐音乐）

基于开源 [api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)（其上游为 [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)）的第三方在线音乐客户端。
**一套 Flutter 代码同时构建 Android / iOS / macOS / Windows / Linux / Web 六端。**

> 阶段：P2 脚手架（登录 + 搜歌 + 风格切换 + 最小播放链路）。P1 后端已部署并实测通过。

## 下载

预编译安装包统一发布在 GitHub Releases（各平台产物 + 安装说明）：

👉 **[Releases · 51www/kele-music](https://github.com/51www/kele-music/releases)**

| 平台 | 产物 | 备注 |
|---|---|---|
| Android | `*-android-universal.apk` | 通用包，手机直接安装；另有分 ABI 包与 `.aab` |
| Windows | `*-windows-x64.zip` | 免安装，解压即用 |
| macOS | `*-macos-arm64.zip` / `*-macos-x64.zip` | Apple Silicon / Intel |
| Linux | `*-linux-x64.tar.gz` | 需 `libsecret` / `libmpv2` |
| iOS | `*-ios-unsigned.app.zip` | 未签名，需自行签名或侧载 |
| Web | `*-web.zip` | 静态站点（canvaskit 自托管，离线可用） |

安装细则见 [`docs/release-notes.md`](docs/release-notes.md)。

## 致谢 Acknowledgements

本项目站在以下开源项目的肩膀上，在此一并致以谢意 🤝：

- **后端基石 · [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)**（Binaryify，MIT）
  在线音乐服务第三方接口规范的源头项目，逆向并整理了完整的 `weapi/eapi` 接口约定。本项目所用网关正是它的衍生版本，没有这套接口约定就没有这个客户端。
- **项目后端 · [api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)**（NeteaseCloudMusicApiEnhanced，MIT）
  在 Binaryify 原版基础上持续维护与增强（解灰 / 多音源 / 无损 / Docker 一键部署等），本项目自托管网关即基于此。感谢社区志愿者长期无偿维护。
- **UI 设计参考 · 官方播放页**
  三套可切换主题（`vinyl-sunset` / `bold-olive` / `soft-teal`）的配色、版式与质感，提炼自官方播放页参考图，设计推导见 `docs/ui-style-prompts.md`。
- **依赖生态 · Flutter / Dart 开源包**
  应用得以顺畅运转，离不开这些高质量开源依赖的维护者们：`flutter_riverpod`（状态管理）、`go_router`（路由 + 登录守卫）、`dio`（网络层）、`audio_service` + `just_audio`（后台播放 / 锁屏媒体控制）、`flutter_secure_storage`（登录态安全存储）、`shared_preferences`、`cached_network_image`、`path_provider`、`cupertino_icons`。向所有贡献者致敬。

### 同类优秀开源项目（架构 / 设计参考，非直接依赖）

方案设计阶段，以下同类客户端提供了不少灵感与对照（本项目并未直接 fork 其代码）：

- [boyan01/flutter-netease-music](https://github.com/boyan01/flutter-netease-music) — 经典的 Flutter 第三方音乐客户端，交互细节参考很多。
- [xiaoai7904/netease_cloud_music_app](https://github.com/xiaoai7904/netease_cloud_music_app) — 入门级 Flutter 实战，结构清晰易读。
- 以及众多基于 [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) 生态的 Web / 桌面客户端，共同推动了第三方在线音乐客户端生态的繁荣。

## 技术栈
- Flutter 3.x + Dart 3.x
- 状态管理：flutter_riverpod
- 路由：go_router（带登录守卫）
- 网络：dio（封装在 `lib/data/api_client.dart`）
- 播放：audio_service + just_audio（后台播放 / 锁屏媒体控制）
- 本地存储：flutter_secure_storage（cookie）+ shared_preferences（风格偏好）

## 环境准备（已完成项，记录备查）
- Flutter SDK：`E:\download\flutter_windows_3.47.7-stable\flutter`（3.47.7 stable / Dart 3.13.5）。
- 平台目录（android / ios / macos / web / windows / linux）**已生成**，无需再 `flutter create .`。
- ⚠️ Flutter 自带的 `flutter.bat` 在 Git Bash / MSYS 下会静默挂死（批处理加锁逻辑）。已用独立 wrapper 绕过：
  - `E:\download\flutter-bin\flutter`（bash，Git Bash 用）
  - `E:\download\flutter-bin\flutter.cmd`（cmd/PowerShell 用）
  - 该目录已置于 **User PATH 最前**。新开终端直接 `flutter` 即可。

## 快速开始
```bash
# 1) 新开一个终端（让 PATH 生效），确认版本
flutter --version          # 应输出 Flutter 3.47.7 • Dart 3.13.5

# 2) 安装依赖（见下方「排错」：大陆网络需切中国镜像 + 临时关代理）
flutter pub get

# 3) 运行（按需选择目标）
.\run_web.bat              # Web（推荐：已内置本地 canvaskit，避免 gstatic 被墙白屏）
flutter run                # 默认设备（Android / 桌面）
flutter run -d macos       # macOS 桌面（需在一台 Mac 上构建）
```

> 注意：Android 端需先安装 **Android Studio / Android SDK**（当前机器尚未安装，见 `flutter doctor` 的 `[X] Android toolchain`）。Web 端已具备 Chrome，可直接跑。macOS 端只能在 Mac 上编译。

## 排错：pub get 报 `TLS error` / `Failed to update packages`
根因：机器上的本地出口代理（`HTTPS_PROXY`，端口会变）对 HTTPS 做中间人证书拦截；`pub.dev` 在大陆直连被墙（必须走代理），而 Dart 的 pub 客户端不信任该代理证书 → 抓包握手失败。
修法（切中国镜像 + 让 Dart 直连镜像、绕开坏代理）：
```powershell
# 指向中国镜像（pub 源 + Flutter 引擎/SDK 存储）
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
# 临时关闭会拦截证书的本地代理，让 Dart 直连镜像（镜像直连可达，无需代理）
$env:HTTPS_PROXY = ""; $env:HTTP_PROXY = ""
$env:https_proxy = ""; $env:http_proxy = ""
flutter pub get
flutter run -d chrome
```
建议把两个镜像环境变量设为**永久 User 变量**（仅对 Flutter 有益、无害）：
```powershell
[Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://pub.flutter-io.cn", "User")
[Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn", "User")
```
> 代理本身别永久关（它是访问外网的手段）；只在跑 flutter 的会话里临时 unset 即可。镜像直连不需要代理。

## Web 启动失败：`www.gstatic.com` 被墙（canvaskit / 字体）
现象：`flutter run -d chrome` 能编译，但浏览器控制台报
`Failed to load resource: net::ERR_CONNECTION_CLOSED`（指向 `www.gstatic.com/flutter-canvaskit/.../canvaskit.wasm` 与 `fonts.gstatic.com/.../roboto.woff2`），页面白屏。
根因：Flutter Web **默认用 CanvasKit(Skia) 渲染器**，要从 Google CDN `gstatic.com` 下载 `canvaskit.wasm/.js`；国内网络通常被墙 → 引擎拿不到 wasm → 启动失败（**致命**）。字体 Roboto 同理（**仅警告**，不影响运行，会回退系统字体）。

修法（已内置，**直接跑 `run_web.bat` 即可**）：
1. 把对应版本的 canvaskit 自托管到本地：`web/canvaskit/canvaskit.js` 与 `canvaskit.wasm`（已随仓库提供）。
2. 用 `--dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/` 让引擎从本地加载，**不再访问 gstatic**。
   - 注意：必须用 `--dart-define`（写入 Dart 引擎常量），仅设 OS 环境变量 `FLUTTER_WEB_CANVASKIT_URL` 无效。
3. 已在 `lib/app/app.dart` 的 `ThemeData` 设置中文字体栈（Microsoft YaHei 等系统字体），改善中文显示并避免回退到需联网的 Roboto。

```powershell
# 推荐：一键启动（已含本地 canvaskit 参数）
.\run_web.bat
# 或等价手动命令
flutter run -d chrome --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
# 生产构建
flutter build web --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
```

> 备选方案：若不想自托管 canvaskit，可改用 HTML 渲染器（完全不下载 canvaskit，但 `BackdropFilter`/模糊特效在 HTML 渲染器下不生效，影响 soft-teal 柔焦风格）：
> `flutter run -d chrome --web-renderer html`
>
> 字体那条 `roboto.woff2` 警告在两种方案下都可能出现，属**无害提示**，应用已正常启动并使用系统字体。

## 关键配置
- 后端地址：`lib/core/constants.dart` 中的 `kBaseUrl`（当前为 `https://music.2000321.xyz`）。
- 运行时配置：`assets/config/app_config.json`（**不入库**，可能含密钥）。新克隆需先创建，否则构建会因缺资产而失败：
  ```bash
  cp assets/config/app_config.example.json assets/config/app_config.json
  ```
  键位说明见 [`docs/api-config.md`](docs/api-config.md)。
- 三套可切换风格：定义在 `lib/core/styles.dart`，与 `docs/ui-styles.json` 一一对应；在「设置」页切换并持久化。
- 风格视觉参考与提示词：`docs/ui-style-prompts.md`。

## 打包与发布
各平台预编译产物由 GitHub Actions 统一构建并发布到 Releases：
- 工作流：`.github/workflows/release.yml`
- 触发：推送 `v*` tag（如 `git tag v0.1.0 && git push origin v0.1.0`），或手动 `workflow_dispatch`
- 产物：Android（通用 APK / 分 ABI APK / AAB）、Windows x64、macOS arm64+x64、Linux x64、iOS（未签名 .app）、Web（静态包）
- Release 说明取自 `docs/release-notes.md`（发版前更新其中的版本号与产物清单）

本地单平台打包（需对应平台工具链）：
```bash
flutter build apk --release            # Android
flutter build appbundle --release      # Android AAB
flutter build windows --release        # Windows（需 VS C++ 桌面开发）
flutter build macos --release          # macOS（需在 Mac 上）
flutter build linux --release          # Linux（需 GTK3 dev）
flutter build ios --release --no-codesign   # iOS（需在 Mac 上）
# Web 必须带 canvaskit 自托管参数，否则会去访问被墙的 gstatic
flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
```

> 调试登录态可临时注入真实 cookie（敏感信息不入库）：
> `flutter run --dart-define=DEV_COOKIE="<MUSIC_U=...; __csrf=...>"`

## 功能范围（P2）
- 登录：短信验证码 / 二维码（密码登录受平台风控限制，未启用）。
- 发现：轮播、推荐歌单、排行榜。
- 搜索：按关键词搜歌并播放。
- 歌单 / 榜单详情：曲目列表点播。
- 播放：迷你播放条 + 全屏播放页（三套版式：黑胶 / 专辑卡 / 柔焦）。
- 我的：每日签到、退出登录。
- 设置：界面风格切换、显示 Base URL。

## 项目截图

> 以下为 Web / 移动端实机效果，完整截图见仓库 `docs/screenshots/` 目录。

### 登录

| 二维码登录 | 短信验证码登录 |
|---|---|
| ![二维码登录](docs/screenshots/shot_login_qr.png) | ![短信登录](docs/screenshots/shot_login_new.png) |

### 发现 / 搜索

| 首页（发现） | 搜索结果 |
|---|---|
| ![首页](docs/screenshots/shot_home_m.png) | ![搜索](docs/screenshots/shot_search2_m.png) |

### 播放

| 全屏播放页（黑胶版式） | 歌词页 |
|---|---|
| ![播放页](docs/screenshots/shot_playing_m.png) | ![歌词](docs/screenshots/shot_lyrics_big.png) |

### 音乐库 / 我的

| 音乐库 | 我的 |
|---|---|
| ![音乐库](docs/screenshots/shot_library_m.png) | ![我的](docs/screenshots/shot_profile_m.png) |

### 设置 / 风格切换

| 设置面板 | 主题一（柔焦青） | 主题二（黑胶暖调） |
|---|---|---|
| ![设置面板](docs/screenshots/shot_settings_panel.png) | ![主题1](docs/screenshots/shot_settings_theme1.png) | ![主题2](docs/screenshots/shot_settings_theme2.png) |

### 后台播放 / 定时关闭

| 通知栏 / 锁屏控制 | 睡眠定时 |
|---|---|
| ![通知控制](docs/screenshots/shot_np_compact_album.png) | ![定时关闭](docs/screenshots/shot_sleep_m.png) |

## 已知限制
- 版权歌曲（`fee:1`）`/song/url/v1` 可能返回试听片段，完整播放需登录会员账号；解灰（Unblock）可缓解灰歌。
- 本项目为**非官方**客户端，仅供学习交流；接口与曲库版权归相应服务平台所有，账号安全与接口稳定性由后端及官方接口决定，请勿用于重要账号。
- Android APK 使用调试签名（未配置发布密钥），可安装升级但不能上架应用市场；iOS 产物未签名，需自行签名。

## 目录结构（feature-first）
```
lib/
  main.dart
  app/            # 应用入口、路由
  core/           # 常量、错误、风格 tokens、通用组件
  data/           # API Client、模型、登录、播放仓库
  features/       # auth / discover / search / playlist / player / library / profile / settings
```
