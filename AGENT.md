# AGENT.md

面向 AI 编码助手的项目指南。改动前请先阅读，保持与现有约定一致。

## 轻量提示（Toast）规范

应用内的轻量操作反馈（如「添加到歌单」的加入成功/失败提示）统一遵循以下规则，确保交互一致、不干扰主界面：

- **形式**：使用 `ScaffoldMessenger` 弹出 `SnackBar`，`behavior: SnackBarBehavior.floating`。
  轻量浮层、非阻断式，不弹窗、不阻塞用户操作，可左滑关闭（无需提供手动关闭按钮）。
- **自动隐藏**：成功提示约 `2.6s`、失败提示约 `3.6s` 后自动平滑消失，用户无需手动关闭。
- **视觉样式（求一眼可见）**：
  - 成功：主题强调色实底（`style.accent`）+ 深色文字（`style.bgBottom`）+ 对勾图标，与实心按钮同色系，任何主题下都醒目。
  - 失败：红色警示实底 `Color.alphaBlend(Colors.red.shade700, style.bgBottom)` + 白色文字 + 警示图标。
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

## 其它约定

- 弹窗/弹层底色一律用 `Color.alphaBlend(style.surface, const Color(0x8C000000))`，
  禁止直接使用半透明的 `style.surface` 直接叠在页面内容上（会透出背景、看不清）。
- 登录态相关的歌单/收藏为「云端 + 本机」双轨：已登录走网易云接口，未登录仅存 `LocalStore`。
  写操作（新建/删除/改名/加歌）后的列表重拉要破缓存，否则命中服务端 120s 边缘缓存，
  看到「操作成功但列表没变」（见 `createdPlaylists` 的 `bustCache` 参数）。
