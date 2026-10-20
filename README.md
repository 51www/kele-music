# NetEase Music Client（三方网易云音乐 · 三端）

基于开源 [api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) 的第三方网易云音乐客户端。
**一套 Flutter 代码同时构建 Android / macOS / Web 三端。**

> 阶段：P2 脚手架（登录 + 搜歌 + 风格切换 + 最小播放链路）。P1 后端已部署并实测通过。

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
- 三套可切换风格：定义在 `lib/core/styles.dart`，与 `docs/ui-styles.json` 一一对应；在「设置」页切换并持久化。
- 风格视觉参考与提示词：`docs/ui-style-prompts.md`。

## 功能范围（P2）
- 登录：短信验证码 / 二维码（密码登录受网易云盾限制，未启用）。
- 发现：轮播、推荐歌单、排行榜。
- 搜索：按关键词搜歌并播放。
- 歌单 / 榜单详情：曲目列表点播。
- 播放：迷你播放条 + 全屏播放页（三套版式：黑胶 / 专辑卡 / 柔焦）。
- 我的：每日签到、退出登录。
- 设置：界面风格切换、显示 Base URL。

## 已知限制
- 版权歌曲（`fee:1`）`/song/url/v1` 可能返回试听片段，完整播放需登录会员账号；解灰（Unblock）可缓解灰歌。
- 本项目为个人学习 / 自用目的的非官方客户端；请勿公开分发或商用。

## 目录结构（feature-first）
```
lib/
  main.dart
  app/            # 应用入口、路由
  core/           # 常量、错误、风格 tokens、通用组件
  data/           # API Client、模型、登录、播放仓库
  features/       # auth / discover / search / playlist / player / library / profile / settings
```
