# AGENT.md

面向 AI 编码助手的项目指南。改动前请先阅读，保持与现有约定一致。

## 轻量提示（Toast）规范

应用内的轻量操作反馈（如「添加到歌单」的加入成功/失败提示）统一遵循以下规则，确保交互一致、不干扰主界面：

- **形式**：使用 `ScaffoldMessenger` 弹出 `SnackBar`，`behavior: SnackBarBehavior.floating`。
  轻量浮层、非阻断式，不弹窗、不阻塞用户操作，可左滑关闭（无需提供手动关闭按钮）。
- **自动隐藏**：成功提示约 `2.6s`、失败提示约 `3.6s` 后自动平滑消失，用户无需手动关闭。
- **视觉样式（Apple Music 中性浮层）**：
  - 统一走 `buildAppSnackBar`：`AMGlass` 半透明中性底 + 背景模糊 + hairline + 极轻投影，主色文字（`style.textPrimary`）；手写 SnackBar 由 `app/app.dart` 的 Theme 兜底成半透明中性底。
  - 成功：品牌红对勾图标；失败：红色警示图标，仅以图标颜色区分结果。
  - 文字 `fontSize: 13.5`、`fontWeight: w600`，统一经 `buildAppSnackBar`（core/widgets.dart）构建，勿手写 SnackBar 样式。
- **文案**：简洁友好，包含关键实体名（如「歌名」+「歌单名」），例如
  「已把「晴天」加入「我的歌单」」「「晴天」已在「我的歌单」中」。
- **成功 / 失败区分**：成功用常规底色；重复添加（已在歌单中）仍属成功态，仅文案提示；
  网络/接口失败用红色警示底色并展示接口返回的业务文案。

### 关键陷阱：弹层 pop 后 context/ref 失效

上述提示常出现在「添加到歌单」底部弹层中。弹层会先 `Navigator.of(context).pop()`
关闭自身，此后弹层 widget 的 `context` 与 `ref` 均已失效，**不能再** 通过
`ScaffoldMessenger.of(context)` 弹提示，否则会因查找失效祖先而抛错、或流程被中断。

正确做法（`lib/features/player/add_to_playlist_sheet.dart` 即此模式）：

1. 在 `pop` 之前，预先捕获依赖：
   - `final messenger = ScaffoldMessenger.of(context);`
   - `final notifier = ref.read(createdPlaylistsProvider.notifier);`（直接持有 notifier，
     避免 pop 后再 `ref.read` 访问已销毁元素）
   - 需要样式时提前 `final style = kStyles[ref.read(styleIndexProvider)];`
2. 提示方法只接收已捕获的 `ScaffoldMessengerState` 与 `AppStyle`，不接收 `context`。
3. 名称输入等子弹窗，应在 pop 弹层**之前**弹出并取回结果，再关闭弹层后执行写操作。

## 冷启动「继续收听」提示栏

应用退出后重新进入、且上次存在**未播完**歌曲时，不固定显示播放条，改为一条轻量提示栏。真源为 `lib/providers.dart` 的 `resumePromptProvider` / `ResumePromptController` 与 `lib/features/player/app_shell.dart` 的 `_ResumePromptBar`。注意冷启动恢复后 `currentMediaItemProvider` 依然有值，所以播放条的抑制不能只看 mediaItem，要由 `awaitingFirstPlay` 决定。

- **出现条件**：`kQueueSnapshotKey` 中有有效队列快照，且当前曲断点距曲末 ≥ `kResumeTailToleranceMs`（即未播完）。快照缺失 / 损坏 / 已播完一律删除并按全新会话启动；`QueueSnapshotStore._save()` 也不再为已播完曲目落盘，避免下次冷启动重复提示。
- **不再出现**：本次会话正常起播后；用户点「忽略」后；曲目播完后；切歌 / 点播新队列 / 清空队列后；真的已在播（热重启、系统媒体键）时。曲目播完的快照清理统一走 `_save()`，不要在 `processingState == completed` 时直接 `remove` 快照——自动切下一曲时该事件可能晚于队列变化，会误删刚写入的新断点。
- **交互**：点击整条或「继续收听」按钮 → `ctrl.markStarted()` 结束待续播阶段 + `handler.play()`。既有 `restoreQueue(... autoplay: false)` 已 seek 到断点，`play()` 消费冷启动重建标记后从断点起播；恢复装载失败时 `play()` 自动重试解析并补上进度。点「忽略」→ 提示撤下且**不冒出播放条**（本次从未起播），下次冷启动若断点仍在会再提示。
- **展示位置**：只在 `AppShell` 内的主路由出现——宽屏占底部通栏位置（60pt 细栏），窄屏贴在标签栏上沿（54pt）。`/now-playing`、`/queue`、`/login` 等 Shell 外全屏页不叠提示（页面自带播放控制或属独立流程）；从这些页面返回时若仍未续播，提示依然在。不弹窗、不遮挡内容、不自动出声。
- **视觉**：中性细栏 + 唯一一处 `AMTokens.signal` 红（播放圆点与小 CTA），轻微上移淡入，`AMTokens.reduceMotion(context)` 下瞬时呈现。

## 毛玻璃材质（唯一取值）

浮层统一由 `lib/core/glass.dart` 的 `AMGlass` 实现，数值一律取 `AMTokens.glass*`；业务代码只声明 `AMGlassKind`（`bar` / `card` / `panel` / `sheet`）与状态，禁止裸写 sigma / alpha / 阴影。

| 项目 | 取值 | 说明 |
|---|---|---|
| 模糊 sigma | `bar 20` / `card·panel 12` / `sheet 24` / 静态封面氛围 `40` | `ui.ImageFilter.blur(sigmaX: sigmaY)`；氛围层用 `ImageFiltered`（合成器缓存，不逐帧采样） |
| 底色 tint | 浅 `#F5F5F7`、深 `#2C2C2E` | 中性色，叠在模糊后的背景上；浅色用略灰白与纯白主底形成明度差 |
| tint alpha（静止） | `bar 0.72` / `card·panel 0.66` / `sheet 0.78` | 滚动 `+0.10`、hover `+0.06`，上限 `0.94` |
| 边框 | `0.5pt hairline`，浅 `rgba(60,60,67,0.08)`、深 `rgba(255,255,255,0.10)` | 贴边条只画朝向内容的单边（top / bottom / right / left） |
| 阴影 | `rgba(0,0,0,0.08)`、`blur 18`、`offset (0,6)`；hover `0.12 / 24` | 贴边条不投影（会变成脏边）；禁止 `blur32/48` 重黑投影 |
| 圆角 | bar `0` / card·panel `12` / sheet `20` | 贴边条配非均匀 Border 时必须直角，否则 `BoxDecoration` 断言 |
| 过渡时长 | hover·滚动 `200ms`、弹层出现 `300ms`，`easeOutCubic` | `AMTokens.glassDuration / glassAppearDuration`，`reduceMotion` 下归零 |

**文字可读性**：正文始终用 `style.textPrimary`（浅 `#1D1D1F` / 深 `#FFFFFF`），次要用 `textSecondary`。tint alpha 按最坏情况（叠在相反纯色背景上）选定：浅色底约 `#F9F9FA`、深色底约 `#5B5B5D`，主文字对比度分别约 `16:1` / `6.5:1`，均高于 `4.5:1`。降级时底色改为完全不透明，对比度只会更高。

**状态过渡**：
- *滚动*：`AppShell` 用 `NotificationListener<ScrollUpdateNotification>` 把 `pixels / 160` 夹到 `0..1`，经 `ValueNotifier` 只驱动浮层（页面内容由 `ValueListenableBuilder.child` 复用，不重建）；底色 / 描边 / 阴影由 `AnimatedContainer` 平滑「加厚」，正文滑过浮层下方时仍清晰。sigma 保持常量，避免逐帧重建 `BackdropFilter`。
- *hover*：桌面指针进入 `AMGlass` 时 tint、描边、阴影各抬一档，触屏不触发。
- *弹层出现*：`animateAppearance` 淡入 + `0.97→1` 轻微放大；`showModalBottomSheet` 自身的位移动画保留。
- 三者都尊重系统「减少动态效果」。

**降级方案**：`AMTokens.glassBlurEnabled(context)` 为 false 时不创建 `BackdropFilter`，改为 `tint alpha 1.0`（完全不透明）+ `1pt` 描边（alpha 再 `+0.04`）+ 保留轻阴影，文字色不变。触发条件：
1. 编译期开关 `--dart-define=AM_GLASS_BLUR=false`（Web HTML renderer 不支持 backdrop-filter，或低端设备）；
2. 系统高对比度模式 `MediaQuery.of(context).highContrast`。

`Scaffold.extendBody: true` 让页面内容延伸到贴底浮层下方，模糊才真正可见；此前移动端 `bottomNavigationBar` 外层不透明的 `Container(color: style.bgBottom)` 会完全挡住模糊，已移除。分散在业务页的 `AlertDialog` / `PopupMenu` / 手写 `SnackBar` 由 `app/app.dart` 的 Theme 兜底成中性半透明底 + hairline（Theme 无法塞进 `BackdropFilter`，真模糊只在 `AMGlass` 与公共弹层）。

## 其它约定

- **视觉真源（Apple Music 改版后）**：语义色/圆角/材质/动效统一由 `lib/core/styles.dart` 的 `AMTokens` 与 `kStyles` 提供。`kStyles` 三档沿用原 `styleIndexProvider` 的 0/1/2 索引与持久化键，分别表示「跟随系统 / 浅色 / 深色」；`docs/apple-music-style-prompts.md` 是唯一风格契约，旧的三套彩色皮肤提示词已归档。
- **表现力层（结构红）**：`AMTokens.signal` 只用于「当前 / 正在」语义（侧栏选中行、板块标题竖块、播放条已播段、标签栏指示条、当前歌词行、主 CTA），其它位置保持黑白灰纯色；超大字阶与编排动效统一取 `AMTokens.displayXL / motionPage / revealDuration`，并尊重系统「减少动态效果」。
- **浮层材质（毛玻璃）**：侧栏 / 顶栏 / 播放条 / 标签栏 / 弹层 / 卡片统一走 `lib/core/glass.dart` 的 `AMGlass`，数值一律取 `AMTokens.glass*`。禁止再写 `Color.alphaBlend(..., 0x8C000000)` 压黑、硬编码 sigma 或 `blur32/48` 重投影；完整取值与降级见下节。
- 登录态相关的歌单/收藏为「云端 + 本机」双轨：已登录走网易云接口，未登录仅存 `LocalStore`。
  写操作（新建/删除/改名/加歌）后的列表重拉要破缓存，否则命中服务端 120s 边缘缓存，
  看到「操作成功但列表没变」（见 `createdPlaylists` 的 `bustCache` 参数）。
