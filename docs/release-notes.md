# 可乐音乐 kele-music · v0.1.0

三方网易云音乐客户端（Flutter），一套代码构建 **Android / iOS / macOS / Windows / Linux / Web**。
后端基于开源 [api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)，默认接口 `https://music.2000321.xyz`。

## 产物清单

| 平台 | 文件 | 说明 |
|---|---|---|
| Android | `kele-music-<tag>-android-universal.apk` | 通用包（arm64-v8a / armeabi-v7a / x86_64），手机直接装 |
| Android | `kele-music-<tag>-android-arm64-v8a.apk` | 分 ABI 包，体积更小，按机型选 |
| Android | `kele-music-<tag>-android.aab` | 上架 Google Play 用 |
| Windows | `kele-music-<tag>-windows-x64.zip` | 免安装，解压即用 |
| macOS | `kele-music-<tag>-macos-arm64.zip` | Apple Silicon（M 系列） |
| macOS | `kele-music-<tag>-macos-x64.zip` | Intel Mac |
| Linux | `kele-music-<tag>-linux-x64.tar.gz` | 桌面 tar 包 |
| iOS | `kele-music-<tag>-ios-unsigned.app.zip` | **未签名**，需自行签名或侧载 |
| Web | `kele-music-<tag>-web.zip` | 静态站点，解压后用任意静态服务器打开 |

## 安装说明

**Android**
1. 下载 `*-android-universal.apk`（不确定机型就用这个）。
2. 手机「设置 → 允许安装未知来源应用」授权给浏览器/文件管理器。
3. 点击 APK 安装。首次启动可先「游客浏览」，需要同步歌单再登录。

**Windows**
1. 解压 `*-windows-x64.zip` 到任意目录。
2. 双击 `kele-music.exe` 运行（需 Microsoft Visual C++ 2015-2022 x64 运行库，缺失时会提示缺 DLL）。

**macOS**
1. 解压对应架构的 zip，得到 `kele-music.app`。
2. 拖入「应用程序」；首次打开若被拦，右键 → 打开（未做 Apple 公证）。

**Linux**
1. 解压 tar 包后运行 `kele-music`。
2. 依赖：`libsecret-1-0`、`libmpv2`（`sudo apt install libsecret-1-0 libmpv2`），Ubuntu 22.04+ 可直接用。

**Web**
1. 解压 zip，用任意静态服务器托管（如 `npx serve`、Nginx、GitHub Pages）。
2. 打开首页即可游客浏览；建议用 Chrome / Edge。

**iOS**
- 产物是**未签名**的 `.app`，无法直接装到真机。需自行用 Apple 开发者证书签名（如 Xcode 重签、AltStore/Sideloadly 侧载），或等待后续提供 TestFlight / Ad Hoc 包。

## 已知限制

- Android APK 目前使用**调试签名**（未配置发布密钥）：可正常安装、覆盖升级，但不能直接上架应用市场。
- iOS 未签名：见上。
- Windows / macOS 未做代码签名，Gatekeeper 可能提示「未知开发者」。
- 应用为第三方客户端，账号安全与接口稳定性由后端与官方接口决定，请勿用于重要账号。
