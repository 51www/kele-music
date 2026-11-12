# Apple Music 整体视觉风格提示词 · 改版设计契约

> **文档用途**：指导 `kele-music` 整体风格与布局方式改版为 Apple Music 视觉语言，供设计产出、设计评审与 Flutter 开发实现共用。
> **适用范围**：全应用（桌面 macOS / Windows / Linux、Web、iOS / Android），含发现、搜索、音乐库、歌单详情、播放器、歌词、队列、设置等全部页面。
> **与现有文档关系**：`docs/ui-style-prompts.md` / `docs/ui-styles.json` 描述三套「深色玻璃拟态」皮肤，改版后降级为历史档案；本文是新的唯一风格真源，风格 ID 为 `apple-music`。
> **唯一口径**：所有提示词共享同一段「风格锚点」（§1.1）。任何章节、任何页面、任何明暗主题下的产出，都必须先加载风格锚点，再叠加该章节的局部约束，避免风格漂移。
> **表现力层（Expressive Layer，后续追加）**：布局骨架与信息架构仍以本文为准，但叠加一层高对比表现力，令牌真源为 `lib/core/styles.dart` 的 `AMTokens.signal / displayXL / motionPage`。此层覆盖本文 §1.2「红色面积 ≤ 2%」与 §4.2 字阶的克制口径：红从点缀升级为**结构色块**（侧栏当前行整块红、板块标题 6pt 红竖块、播放条 6pt 粗红进度、标签栏 3pt 红指示条、当前歌词行红字），页面大标题 56pt w800 / -2 字距、板块标题 28pt w800、Hero 标题 44pt w800。仍保持扁平（纯色块、无渐变/颗粒/拟物）；动效编排统一尊重系统「减少动态效果」。

> **导航变更（后续追加）**：搜索项已从导航菜单移除——桌面侧栏顶部搜索框、移动端标签栏「搜索」项均删除。搜索页 `/search` 与 `SearchScreen` 保留，由发现页顶部的搜索按钮进入；`_items` 索引与 `paths` 的对应关系保持不变。本文 §1、§3、§13、§14 中「侧栏搜索框」「4 项标签栏含搜索」等描述以本条为准。

---

## 0. 如何使用这份文档

| 角色 | 用法 |
|---|---|
| 设计 / 生图 | 复制 §1「主提示词」+ 目标章节的「局部提示词」作为一次投喂；§1.5「负面提示词」必须同时附上 |
| 开发 | 以 §12「设计令牌总表」为唯一取值来源，以 §13「项目落地映射」为改造清单，以 §14「验收清单」为完成标准 |
| 评审 | 逐条勾选 §14；任何与 §1.2 三条铁律冲突的产出直接驳回 |
| 扩展新页面 | 不新增风格描述，只从 §2–§11 中选取适用章节组合，并复用 §12 令牌 |

**统一命名**：所有令牌以 `am.` 为前缀（`am.bg.base`、`am.accent`、`am.radius.art` …）。组件、变量与主题扩展中一律使用该前缀，禁止再出现 `style.accent`、`uiRadius`、`cardRadius` 这类随皮肤漂移的取值。

---

## 1. 主提示词（Master Prompt）

### 1.1 风格锚点（所有提示词的固定前缀，不可删改）

```text
以 Apple Music（macOS 与 iOS 原生客户端）为唯一视觉参照。系统原生感、内容优先、极度克制：UI 外壳不带情绪，专辑封面是全界面唯一的色彩来源；层级只靠字号字重、留白与半透明材质建立，不靠描边、投影、色块或装饰图形。中性底色（浅色近白 / 深色近黑），单一红色强调色，SF Pro / 苹方字体栈，SF Symbols 风格图标，正方形圆角专辑封面，细线进度条，展开式页面转场。无强饱和全屏渐变、无胶片颗粒、无暗角、无拟物唱片、无持续循环装饰动效、无 Material 风格控件。
```

### 1.2 三条铁律

1. **色彩来自内容，不来自界面**：界面只有中性灰阶 + 一处品牌红；封面取色只能作为低饱和、低透明度的氛围层，不能成为主背景色。
2. **层级来自排版与留白，不来自容器**：优先加大字号、拉开间距、使用系统材质；尽量少画卡片边框、少加投影、少加分隔线。
3. **一切动效服务于状态变化**：静止时不动画，只在选中、展开、切换、播放进度上做短促过渡。

### 1.3 中文主提示词（整体一次投喂）

```text
请设计一款跨平台音乐客户端的完整界面（桌面端 + 移动端），严格遵循 Apple Music 视觉语言。

整体：系统原生、内容优先、克制、安静、精致。界面外壳只用中性底色——浅色为近白 #FFFFFF 与浅灰 #F5F5F7，深色为纯黑 #000000 与深灰 #1C1C1E；唯一强调色为 Apple Music 红（浅色 #FA243C / 深色 #FC3C44），只用于选中态、收藏、进度条与文字链接。禁止全屏彩色渐变、胶片颗粒、暗角、拟物黑胶唱片与唱臂、波形与水波纹等循环装饰。

布局：桌面端为「左侧 250pt 半透明侧边栏 + 右侧内容区 + 底部通栏播放条」三段式；内容区左右留白随宽度分档为 16 / 24 / 32pt，宽屏内容列封顶并居中；移动端为「内容区 + 底部标签栏 + 标签栏上方悬浮迷你播放器」。8pt 呼吸节奏、4pt 微调刻度，正方形专辑封面按可用宽度推导列数（手机 2 列、平板 3–4 列、桌面 5–6 列）。

导航：侧栏顶部是圆角搜索框，下面按「Apple Music / 资料库 / 播放列表」分组，分组标题为小号灰色大写标签；选中项是圆角 8pt 的浅灰底 + 红色图标 + 半粗体文字，不用彩色药丸。内容区顶部有返回/前进箭头、大标题与右上角账户头像，滚动时大标题收起为紧凑半透明标题栏。

字体：SF Pro Display / SF Pro Text，中文苹方 PingFang SC；页面大标题 34pt 粗体，板块标题 22pt 粗体，歌曲名 17pt 半粗，正文 15pt，歌手与副标题 13pt 次级灰，时间与标签 11pt 等宽数字。字距收紧、行高宽松、名称单行省略，不使用手写体、装饰衬线或宽字距。

图标与控件：统一 SF Symbols 风格，光学尺寸 24pt、描边 1.5–2pt、权重 medium/semibold，选中态切换为填充版本；无边框圆形按钮，hover 时才出现浅灰圆形底。进度条为 3pt 细线，hover / 拖拽时加粗到 5pt 并出现 10pt 圆形滑块，两端 11pt 等宽时间；播放/暂停为中心 56pt 实心图标，两侧上一首/下一首 32pt，间距 32pt。不使用 Material 三点竖排、实心高饱和按钮、ChoiceChip、环形进度或持续呼吸的播放头。

卡片与列表：专辑封面为 1:1 正方形、圆角 8pt、无描边，仅浅色下带极轻柔和投影；封面下方是 15pt 半粗标题与 13pt 次级副标题，封面本身不压文字、不加播放量角标；hover 时封面右下角淡入 32pt 半透明圆形播放按钮。列表行高 56pt，48pt 方形缩略封面，右侧 12pt 等宽时长，行间仅一条内缩的 0.5pt 细线，无斑马纹。板块标题 22pt 粗体配右侧红色「查看全部」文字链。

播放页：全屏背景为中性底色叠加「由当前封面取色、降饱和、模糊、低透明度」的氛围层，只覆盖上部约 60% 并三段渐隐；中央是一张大尺寸圆角封面，宽屏时左封面右歌词分栏；歌词当前行 30pt 白色粗体、非当前行 24pt 半透明白，随播放逐字填充高亮，无发光阴影。底部为细进度条、时间、传输控件与音量。

动效：微交互 150–200ms，常规状态切换 250–300ms，迷你播放器到全屏播放页用 400–500ms 弹簧展开并让封面做共享元素过渡，歌词滚动 350ms，封面取色切换 600–800ms 交叉淡入；曲线统一 easeOutCubic / spring，禁止弹跳曲线与无限循环动画。

明暗主题：跟随系统自动切换明暗，两套语义色令牌一一对应；浅色材质为半透明白 + 20px 模糊 + 极浅描边，深色材质为半透明深灰 + 20px 模糊 + 极淡描边；正文对比度不低于 4.5:1，深色下不出现纯黑文字。

情绪关键词：克制、编辑感、轻盈、安静、可信、系统原生、专辑优先。
```

### 1.4 English master prompt

```text
Design a complete cross-platform music client (desktop + mobile) in the exact visual language of Apple Music (macOS / iOS native apps).

System-native, content-first, extremely restrained. The UI chrome is emotionally neutral: light mode uses near-white #FFFFFF and light gray #F5F5F7, dark mode uses pure black #000000 and dark gray #1C1C1E; the only accent is Apple Music red (#FA243C light / #FC3C44 dark), reserved for selection, favorites, progress and text links. No full-screen saturated gradients, no film grain, no vignette, no skeuomorphic vinyl records or tonearms, no looping waveform or ripple decorations.

Layout: desktop = 250pt translucent sidebar + content pane + full-width bottom playback bar; content gutters scale 16 / 24 / 32pt by breakpoint, with a capped centered content column on wide screens. Mobile = content + bottom tab bar with a floating mini player directly above it. 8pt rhythm with a 4pt micro grid; square album art in responsive grids (2 phone / 3–4 tablet / 5–6 desktop columns).

Navigation: sidebar starts with a rounded search field, then grouped sections (Apple Music / Library / Playlists) with small gray uppercase headers; selected row = 8pt-radius subtle gray fill, red icon, semibold label — never a colored pill. Content header has back/forward chevrons, a large title and a top-right account avatar; the large title collapses into a compact translucent bar on scroll.

Typography: SF Pro Display / SF Pro Text with PingFang SC for Chinese. Large title 34pt bold, section title 22pt bold, track name 17pt semibold, body 15pt, artist/subtitle 13pt secondary, timestamps 11pt tabular numerals. Tight tracking, generous line height, single-line truncation; no script, decorative serif or wide letter-spacing.

Icons & controls: SF Symbols styling, 24pt optical size, 1.5–2pt stroke, medium/semibold weight, filled variants for active states; borderless circular buttons with a subtle gray hover disc. Progress is a 3pt hairline that grows to 5pt with a 10pt thumb only on hover/drag, flanked by 11pt tabular timestamps. 56pt solid play/pause at center, 32pt previous/next with 32pt spacing. No Material vertical three-dots, no saturated filled buttons, no chips, no ring progress, no permanently pulsing thumb.

Cards & lists: 1:1 square album art, 8pt radius, no border, only a very soft shadow in light mode; 15pt semibold title and 13pt secondary subtitle below the art — never text overprinted on cover art and no play-count badges. A 32pt translucent circular play button fades in at the lower-right on hover. List rows are 56pt tall with 48pt thumbnails, 12pt tabular duration on the right and one inset 0.5pt hairline separator; no zebra striping. Section headers are 22pt bold with a red "See All" text link.

Now Playing: neutral backdrop plus a desaturated, blurred, low-opacity tint sampled from the current cover art, covering only the upper ~60% with a three-stop fade; a large rounded cover is centered, with cover-left / lyrics-right split on wide screens. Active lyric line 30pt white bold, inactive 24pt white at 45% opacity, word-by-word fill synced to playback, no glow.

Motion: 150–200ms micro-interactions, 250–300ms state changes, 400–500ms spring expansion from mini player to full-screen Now Playing with a shared-element cover transition, 350ms lyric scrolling, 600–800ms crossfade on cover-tint changes; easeOutCubic / spring only, no bouncy curves, no infinite decorative loops.

Theming: follow system light/dark with paired semantic color tokens; light materials are translucent white + 20px blur + hairline, dark materials are translucent dark gray + 20px blur + hairline; body text contrast ≥ 4.5:1 and never pure black on dark.

Mood: restrained, editorial, airy, calm, trustworthy, system-native, album-forward.
```

### 1.5 负面提示词（Negative prompt，必须随主提示词附上）

```text
不要：赤陶橙 / 橄榄绿 / 青绿等彩色全屏渐变背景；胶片颗粒、噪点、暗角；黑胶唱片同心纹、唱臂、水波纹、涟漪、均衡器柱等拟物或无限循环装饰；彩色大药丸选中态；1px 高对比描边卡片；重黑色压暗弹层；封面上的强压暗 scrim 与叠字；播放量胶囊角标；实心高饱和大按钮、ChoiceChip、Material 水波纹、竖向三点菜单、圆形描边播放键；环形进度与持续呼吸的播放头；手写体、装饰衬线、宽字距、全大写中文；发光歌词、弹跳动画、旋转唱片；浅色主题里用深色玻璃，深色主题里用纯黑文字。
```

---

## 2. 布局结构与栅格体系

### 2.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下设计整体布局骨架。桌面端为三段式：左侧固定 250pt 半透明材质侧边栏，右侧为可滚动内容区，底部为横跨整个窗口宽度、高 72pt 的通栏播放条（播放条位于侧栏与内容区之下，不用悬浮卡片）。内容区左右留白按屏宽分 16 / 24 / 32pt，宽屏内容列封顶 1180pt 并居中；顶部保留 30pt 交通灯安全区。内容区顶部是大标题 + 返回/前进箭头 + 右上角账户头像，向下是横向卡片货架、网格与列表；滚动时大标题收起为 44pt 紧凑材质标题栏。移动端改为单列内容 + 底部标签栏 + 标签栏上方 56pt 悬浮迷你播放器。所有分区靠留白与细线划分，不靠色块或边框。正方形专辑封面按可用宽度推导列数，卡片正好铺满列宽，右侧不留残余空档。
```

### 2.2 骨架与分区（桌面）

```
┌──────────────────────────────────────────────────────────────┐
│ 30pt 交通灯安全区（仅 macOS 隐藏标题栏时）                    │
├──────────────┬───────────────────────────────────────────────┤
│              │ ← → │ 大标题 34pt            账户头像        │
│  侧边栏      ├───────────────────────────────────────────────┤
│  250pt       │  板块标题 22pt              查看全部 ›       │
│  vibrancy    │  □ □ □ □ □ □  横向货架 / 网格               │
│  材质        │  板块标题 22pt                               │
│              │  ≡ 列表行 56pt …                             │
│  搜索框      │                                               │
│  分组导航    │  （内容列居中，宽屏封顶 1180pt）              │
│  播放列表    │                                               │
├──────────────┴───────────────────────────────────────────────┤
│ 封面48 曲名 │      ‹‹  ▶  ››   ─────●────  0:42  -3:18   │ 72pt 通栏
└──────────────────────────────────────────────────────────────┘
```

### 2.3 响应式断点（沿用项目现有断点，不新增数值）

| 断点 | 条件 | 布局 |
|---|---|---|
| `compact` | 宽度 < 600 | 单列内容；底部标签栏 + 迷你播放器；网格 2 列；`gutter 16` |
| `medium` | 600 ≤ 宽度 < 1024 | 单列内容 + 更宽留白；网格 3–4 列；`gutter 24` |
| `expanded` | 宽度 ≥ 1024 | 内容列封顶 1180 居中；网格 5–6 列；`gutter 32` |
| 侧边栏启用 | 宽度 ≥ 820 | 桌面三段式骨架生效（现有 `useSidebar` 判定，保留） |
| 播放页分栏 | 宽度 ≥ 960 | 左封面 / 右歌词，保留现有 `flex 5 : 6` 与 1px 分隔改为 hairline |
| 交通灯 inset | macOS 非 Web | 顶部固定 30pt（现有 `macInset`，保留） |

### 2.4 栅格规则

- **基准**：8pt 呼吸节奏 + 4pt 微调刻度，与项目 `AppSpacing` 完全一致，不新增刻度值。
- **列数推导**：`gridColumns(width, minCard: 150, maxColumns: 6)`，封面边长由 `gridCardSize(width, columns)` 反推，保证铺满列宽、右侧无残余空档；列间距取 `inline`（8 / 12 / 12）。
- **内容列**：`AppContentColumn` 在宽松档封顶 1180 并居中；正文行宽不超过该值，避免宽屏下一行文字过长。
- **对齐**：侧栏外沿、内容区标题左沿、卡片网格左沿、播放条左封面左沿共用同一 `gutter`，形成一条垂直对齐线。
- **底部播放条三分区**：左 30% 封面 + 曲名 / 中 40% 传输控件 + 进度 / 右 30% 音量、歌词、队列、输出；三区在同一水平轴上，高 72pt，顶部一条 0.5pt hairline。
- **禁止**：正文居中通栏拉满；悬浮玻璃导航坞；把播放条做成带大圆角与投影的悬浮卡；给每个板块套一层可见容器。

### 2.5 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| `AppShell` 宽屏 `Row(_Sidebar 250, Expanded(child))`，全页铺 `style.backgroundGradient` | 保留骨架；渐变改为中性纯色 `am.bg.base`；补底部通栏播放条 | `lib/features/player/app_shell.dart` |
| 窄屏 `bottomNavigationBar` 内 `Column(NowPlayingBar, _NavDock)` | 改为底部标签栏 + 悬浮迷你播放器，两者间距 `inline` | 同上 |
| `_CoverBackdrop` 三段渐隐（stops 0.45/0.78/1.0，sigma 30/40） | 保留实现，仅换成低饱和取色 + 中性底，见 §5 | `lib/features/player/now_playing.dart` |
| `AppSpacing` / `AppSpacingMetrics` / `AppContentColumn` 断点与语义间距 | **整体保留，不改数值**；仅把 `gridColumns` 的 `minCard` 由 130 调到 150；`AppSpacing.maxContentWidth` 720 保持不动，`AppContentColumn.maxWidthFor` 的三档 720 / 900 / 1180 全部沿用 | `lib/core/styles.dart`、`lib/core/widgets.dart` |

---

## 3. 导航与侧边栏组织

### 3.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下设计导航。桌面左侧栏宽 250pt，使用半透明系统材质（浅色半透白 / 深色半透深灰，20px 模糊，右沿 0.5pt 细线），从上到下依次是：圆角 10pt 的搜索框（灰底、16pt 放大镜、13pt 占位文字）、「Apple Music」分组（现在听 / 浏览 / 电台）、「资料库」分组（最近添加 / 艺人 / 专辑 / 歌曲 / 已下载）、「播放列表」分组（用户歌单，可滚动、按首字母排序）。分组标题为 11pt 次级灰、字距 0.2、上下各留 12pt。每行高 32pt、图标 18pt、文字 13pt；选中行为圆角 8pt 的浅灰底 + 品牌红填充图标 + 半粗体文字，未选中行为线性图标 + 主色文字；hover 才出现更浅的圆形底，不使用彩色药丸、外发光或左侧色条。侧栏底部固定「正在播放」小卡（32pt 封面 + 两行文字）与账户头像。内容区顶部为 44pt 工具栏：返回/前进 chevron、右侧账户头像；大标题在工具栏下方，滚动时收起。移动端底部为 4 项标签栏（现在听 / 浏览 / 资料库 / 搜索），图标 24pt、文字 11pt，选中项品牌红填充图标。
```

### 3.2 侧边栏信息架构

| 区块 | 条目 | 交互与状态 |
|---|---|---|
| 搜索 | 输入框 | 圆角 10、`am.fill.quaternary` 底、聚焦时 hairline + 品牌红光标；输入即进入搜索页 |
| Apple Music | 现在听、浏览、电台 | `现在听` 为默认落地页；对应项目现有 `发现` |
| 资料库 | 最近添加、艺人、专辑、歌曲、已下载 | 对应项目 `音乐库` 页内页签，不新增导航位；`本地` 仍作为资料库内页签 |
| 播放列表 | 用户歌单列表 | 32pt 方形封面 + 13pt 名称，超出区域滚动，不挤压上部分组 |
| 底部 | 正在播放、账户 | 点击「正在播放」展开全屏播放页（共享元素转场，见 §9） |
| 我的 | 设置、历史、收听统计、下载管理 | 收进账户头像菜单，不再占独立导航位 |

### 3.3 状态规格

| 状态 | 表现 |
|---|---|
| 选中 | 圆角 8pt `am.fill.selected`（浅色 `rgba(250,36,60,0.10)` / 深色 `rgba(252,60,68,0.16)`）+ 品牌红填充图标 + 13pt w600 文字 |
| hover | `am.fill.quaternary` 圆形底，150ms 淡入，不改变文字色 |
| pressed | 底色透明度 +0.06，100ms |
| 分组标题 | 11pt w500、`am.label.tertiary`、字距 0.2，不与行同色 |
| 紧凑标题栏 | 滚动超过大标题后淡入，44pt 高、半透明材质 + 底部 hairline，标题 17pt w600 |
| 标签栏（移动端） | 高 49pt + SafeArea，材质模糊，选中图标为填充变体，文字 11pt w500 |

### 3.4 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| `_Sidebar` 品牌区 `Icons.graphic_eq_rounded` + `可乐音乐` | 改为搜索框置顶 + 三个分组标题；品牌标识只保留在账户菜单 | `app_shell.dart` |
| 4 项平铺 `发现 / 搜索 / 音乐库 / 我的` | 按 §3.2 重组；`搜索` 从导航项变为侧栏输入框 | 同上 |
| 选中态 `accent.withValues(alpha: 0.16)` 彩色药丸 + 实心图标 | 换为 §3.3 选中规格 | 同上 |
| `_indexFor` 高亮归属映射、`paths = ['/', '/search', '/library', '/profile']` | 保留映射逻辑，仅按新分组调整路由归属 | 同上 |
| `_NavDock` 悬浮玻璃坞（sigma 20、黑色压底、投影） | 改为贴底系统标签栏，材质用 `am.material.bar`，取消投影 | 同上 |
| `_SidebarMiniPlayer` 环形进度 | 改为 32pt 封面 + 两行文字，点击展开全屏播放页 | 同上 |

---

## 4. 字体层级与排版规范

### 4.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下制定排版。西文使用 SF Pro Display（34pt 以上）/ SF Pro Text（其余），中文使用苹方 PingFang SC，系统缺失时回退到 Hiragino Sans GB → Noto Sans SC → sans-serif；全应用只有一套字号阶梯，页面大标题 34pt 粗体、板块标题 22pt 粗体、歌曲名 17pt 半粗、正文 15pt、副标题 13pt 次级灰、标签与时间 11pt 等宽数字。西文与数字字距略收紧（-0.4 到 0），中文不额外加字距；行高约为字号的 1.3 倍；曲名、歌手与歌单名单行截断显示省略号，最多两行时行高固定，不允许文字撑开卡片导致错位。数字（时长、序号、播放进度）统一启用等宽数字特性。层级只靠字号、字重与颜色，不靠全大写、彩色底、装饰线或手写字体。
```

### 4.2 字号阶梯（唯一 type scale）

| 令牌 | 字号 / 行高 | 字重 | 字距 | 用途 |
|---|---|---|---|---|
| `am.type.largeTitle` | 34 / 41 | w700 | -0.4 | 页面大标题（浏览、资料库、歌单详情） |
| `am.type.title1` | 28 / 34 | w700 | -0.3 | 编辑推荐 Hero 标题、播放页曲名 |
| `am.type.title2` | 22 / 28 | w700 | -0.2 | 板块标题、`SectionHeader` |
| `am.type.title3` | 20 / 25 | w600 | -0.2 | 详情页次级标题、弹层标题 |
| `am.type.headline` | 17 / 22 | w600 | -0.2 | 歌曲名、列表主文、紧凑栏标题、侧栏选中项 |
| `am.type.body` | 15 / 20 | w400（卡片标题 w600） | -0.1 | 正文、专辑卡标题、按钮文字 |
| `am.type.subhead` | 13 / 18 | w400 | 0 | 歌手、副标题、说明文字 |
| `am.type.footnote` | 12 / 16 | w400 | 0 | 时长、次要说明 |
| `am.type.caption` | 11 / 13 | w500 | 0.2 | 标签、分组标题、标签栏文字（等宽数字） |

### 4.3 专项排版

| 场景 | 规则 |
|---|---|
| 中文映射 | `w400` Regular / `w500` Medium / `w600` Semibold / `w700` Bold；中文标题不用 `w800/w900`，中文不加负字距 |
| 数字 | 时长、序号、进度时间、统计数字启用 `FontFeature.tabularFigures()`，右对齐 |
| 截断 | 曲名 / 歌手 / 歌名单行 `TextOverflow.ellipsis`；专辑卡副标题最多 2 行且容器高度固定 |
| 颜色 | 主文 `am.label.primary`、副文 `am.label.secondary`、辅助 `am.label.tertiary`；强调仅用于可点击文字链与选中态，不用于大段文字 |
| 歌词 | 当前行 30 / 36 w700 主文色；非当前行 24 / 30 w600 主文色 45% 透明；行间 12pt；逐字填充用不透明主文色从字左到右覆盖，禁止文字发光、渐变描边与缩放弹跳 |
| 禁止 | 手写体、装饰衬线、宽字距、中文全大写、亮黄色字幕、文字投影、随主题变化的标题字号 |

### 4.4 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| `fontFamily: 'Microsoft YaHei'` + 中文 fallback | 改为 `SF Pro Display` / `SF Pro Text` 优先 + `PingFang SC` 等中文回退；建立 `TextTheme`，业务代码不再散写 `TextStyle` | `lib/app/app.dart`、`lib/core/styles.dart` |
| `titleSize 20/22/26`、`titleWeight w500/w600/w400`、`letterSpacing` 随皮肤变化 | 删除，统一为 §4.2 阶梯 | `lib/core/styles.dart` |
| 散落字号 9 / 10.5 / 11.5 / 12.5 / 14.5 / 15.5 / 27 / 28 / 21 | 全部收敛到 §4.2 九个令牌 | `lib/core/widgets.dart`、各 `*_screen.dart` |
| 歌词当前行 21pt w700 + `Shadow(blurRadius: 18)` 发光 | 改为 30pt w700、无发光、逐字填充 | `lib/features/player/lyrics_view.dart` |
| `SectionHeader` 固定 24pt 高、17pt w700 | 改为 22pt w700、高度 28pt | `lib/core/widgets.dart` |

---

## 5. 色彩系统（含渐变与背景处理）

### 5.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下制定色彩。界面只用中性底色：浅色主内容 #FFFFFF、分组/侧栏 #F5F5F7、深色主内容 #000000、次级面 #1C1C1E；文字为近黑 #1D1D1F / 纯白 #FFFFFF，次级文字 60% 透明；唯一强调色 Apple Music 红，浅色 #FA243C、深色 #FC3C44。绝对不要全屏彩色渐变：主背景必须是恒定中性色。允许的唯一渐变是「封面取色氛围层」——从当前专辑封面提取主色，把饱和度降到 35% 以下，模糊 40–60px，浅色下透明度 0.10–0.16、深色下 0.18–0.28，只覆盖页面上部约 60% 高度，并用 0.45 / 0.78 / 1.0 三段渐隐融回底色；换歌时两层取色以 600–800ms 交叉淡入。半透明材质一律中性：浅色为半透明白 + 20px 模糊 + 极浅描边，深色为半透明深灰 + 20px 模糊 + 极淡描边，不要用黑色压暗弹层。红只出现在选中态、收藏、进度条已播段、文字链接与显式破坏性操作上，一屏内红色面积不超过 2%。
```

### 5.2 语义色令牌（浅色 / 深色一一对应）

| 令牌 | Light | Dark | 用途 |
|---|---|---|---|
| `am.bg.base` | `#FFFFFF` | `#000000` | 内容区主底 |
| `am.bg.grouped` | `#F5F5F7` | `#1C1C1E` | 侧栏底、分组列表底、播放页底 |
| `am.bg.elevated` | `#FFFFFF` | `#2C2C2E` | 弹层、浮层 |
| `am.surface.panel` | `rgba(255,255,255,0.72)` | `rgba(44,44,46,0.68)` | 卡片 / 面板材质底色 |
| `am.label.primary` | `#1D1D1F` | `#FFFFFF` | 标题、曲名 |
| `am.label.secondary` | `#6E6E73` | `rgba(235,235,245,0.60)` | 歌手、副标题 |
| `am.label.tertiary` | `#8E8E93` | `rgba(235,235,245,0.30)` | 分组标题、占位符、禁用 |
| `am.separator` | `rgba(60,60,67,0.18)` | `rgba(84,84,88,0.60)` | 0.5pt hairline |
| `am.fill.quaternary` | `rgba(116,116,128,0.08)` | `rgba(118,118,128,0.24)` | hover / pressed 底 |
| `am.fill.selected` | `rgba(250,36,60,0.10)` | `rgba(252,60,68,0.16)` | 侧栏选中行 |
| `am.accent` | `#FA243C` | `#FC3C44` | 品牌红（唯一强调色） |
| `am.accent.on` | `#FFFFFF` | `#FFFFFF` | 红底上的文字 / 图标 |
| `am.scrim` | `rgba(0,0,0,0.35)` | `rgba(0,0,0,0.45)` | 仅 Hero 大图底部压暗 |

### 5.3 背景与渐变处理

| 场景 | 处理 | 禁止 |
|---|---|---|
| 全应用主背景 | 恒定 `am.bg.base` 纯色；侧栏用 `am.bg.grouped` + 材质 | 全屏 `LinearGradient(bgTop→bgBottom)`、彩色主题皮肤 |
| 播放页 / 歌单详情 | 中性底 + 封面取色氛围层（§5.1 参数），上部约 60%，三段渐隐 `stops [0.45, 0.78, 1.0]`，衔接色由底色与取色 `lerp(0.62)` 得到 | 高饱和取色直接铺底、把封面模糊图当整页背景 |
| Hero / 编辑推荐位 | 仅在图片底部 40% 加 `transparent → am.scrim` 线性压暗，保证白色标题可读 | 全图 0.55 黑压暗、封面上叠大段文字 |
| 弹层 / 浮层 | `am.bg.elevated` 半透中性色 + 20–24px 模糊 + hairline | `Color.alphaBlend(surface, 0x8C000000)` 重黑压底 |
| 侧栏 / 顶栏 / 播放条 | 系统材质：`am.surface.panel` + `sigma 20` + 0.5pt hairline | 黑色半透明叠加 + 20px 大投影 |
| 封面占位图 | 中性浅灰 `am.fill.quaternary` + 12pt 音符图标 | 彩色占位图、品牌色大图 |

### 5.4 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| `AppStyle.backgroundGradient`（`bgTop/bgBottom`）全页渐变，`kStyles` 三套彩色皮肤 | 删除渐变作为主背景；新增 `AMTheme` 语义色令牌，默认皮肤 `apple-music` | `lib/core/styles.dart` |
| `accent` 随皮肤变（琥珀金 / 亮黄 / 白） | 固定为 `am.accent` 明暗两值 | 同上 |
| `grain` / `vignette` / `blur` 开关 | 全部移除（颗粒与暗角禁止；blur 归入材质常量） | 同上 |
| `_CoverBackdrop` 模糊封面 + 三段渐隐 | 保留技术路径，仅替换为「降饱和取色 + 中性底 + 更低 alpha」 | `lib/features/player/now_playing.dart` |
| 弹层统一 `0x8C000000` 压黑约定 | 改为中性材质；同步修订约定文档 | `AGENT.md`、`lib/features/player/*_sheet.dart` |
| `docs/ui-styles.json` 三套 token 与代码已不同步 | 新增 `apple-music` 单套 token，三套旧风格归档 | `docs/ui-styles.json`、`docs/ui-style-prompts.md` |

---

## 6. 图标与控件样式

### 6.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下设计图标与控件。全应用统一 SF Symbols 风格：光学尺寸 24pt、描边 1.5–2pt、权重 medium/semibold、圆润端点与统一几何网格；未选中用线性版本，选中/激活用同一图形的填充版本并变品牌红，绝不混用第三方线性图标与 Material 图标。所有按钮都是无边框、无底色的圆形图标按钮，只有 hover / pressed 时才浮出一层浅灰圆形底，激活态靠填充与颜色表达而非药丸。播放控制区：中心 56pt 实心播放/暂停，左右各 32pt 上一首/下一首，两侧 24pt shuffle / repeat，间距 32pt。进度条为 3pt 细线 + 圆头，已播段品牌红、未播段 `am.fill.quaternary`，hover 或拖拽时轨道加粗到 5pt 并淡入 10pt 圆形滑块，两端 11pt 等宽时间；音量同样为 3pt 细线滑块。收藏、更多、歌词、队列均为 24pt 无边框图标，更多用横向三点或圆形省略号而非竖向三点。不要圆形描边播放键、实心高饱和大按钮、ChoiceChip、Material 水波纹、环形进度以及静止时仍持续呼吸的播放头。
```

### 6.2 图标规范

| 项 | 规格 |
|---|---|
| 风格 | SF Symbols（Flutter 端用 `CupertinoIcons` 或内置 SF Symbols 风格资源；禁止 `Icons.*` Material 语义） |
| 光学尺寸 | 导航 18pt / 常规工具 24pt / 传输控件 32pt / 中心播放 56pt |
| 描边与权重 | 1.5–2pt 等效描边、medium / semibold，端点圆润、视觉重心对齐 |
| 状态 | 未选中线性 + `am.label.primary`；选中填充 + `am.accent`；禁用 `am.label.tertiary` |
| 语义映射 | 竖三点 `more_vert` → 横向三点 / `ellipsis.circle`；`play_circle_fill` → 实心三角 + 无边框圆底；`timer_outlined` → 睡眠计时月牙；`graphic_eq_rounded` → 音符波形（仅品牌） |
| 禁止 | 混用描边粗细、给图标加彩色圆底、给图标加投影、把线性与填充图标同时放在同一组 |

### 6.3 控件规格

| 控件 | 规格 |
|---|---|
| 播放 / 暂停 | 中心 56pt 实心三角 / 双竖条，无圆形底、无描边 |
| 上一首 / 下一首 | 32pt 实心图标，与中心间距 32pt |
| 循环 / 随机 | 24pt 线性；激活时填充 + 品牌红；不使用彩色徽标 |
| 进度条 | 轨道 3pt（hover / drag 5pt）、圆角 2pt；已播 `am.accent`，缓冲 `am.fill.quaternary`，未播透明；滑块 10pt 圆形，仅交互时显示；命中区高 ≥ 26pt |
| 时间标签 | 11pt w500 等宽数字、`am.label.secondary`，左右两端对齐 |
| 音量 | 3pt 细线滑块 + 16pt 喇叭图标，无刻度、无气泡 |
| 收藏 / 更多 / 歌词 / 队列 | 24pt 无边框 `IconButton`；收藏激活为品牌红实心心形；hover 圆形底 150ms 淡入 |
| 搜索框 | 高 32pt、圆角 10pt、`am.fill.quaternary` 底、16pt 放大镜、13pt 占位文字、聚焦时品牌红光标 |
| 文字按钮 / CTA | 高 32pt、圆角 16pt、13pt w600；主操作用品牌红实底白字，次操作用品牌红文字链（无边框） |
| 反馈 | 沿用项目 `buildAppSnackBar` 浮动提示（成功 2.6s / 失败 3.6s），底色改 `am.bg.elevated`，文字 `am.label.primary`，成功态左侧品牌红对勾 |
| 禁止 | `FilledButton.icon` 大实心按钮、`ChoiceChip`、Material ripple / 高亮水波、`Slider` 默认样式、环形进度、持续脉动圆点 |

### 6.4 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| 全库 `Icons.*`；`cupertino_icons` 已声明但未使用；无 svg | 建立 `AMIcons` 映射层，统一替换为 Cupertino / SF Symbols 风格资源 | `pubspec.yaml`、`lib/core/widgets.dart`、`lib/features/player/now_playing.dart` |
| `_ProgressBar` 自绘 4pt 轨 + 12pt 持续呼吸播放头（900ms repeat reverse） | 保留自绘结构，改 3/5pt 轨、10pt 仅 hover 滑块，删除呼吸动画 | `lib/features/player/now_playing.dart` |
| `NowPlayingBar` 环形 `CircularProgressIndicator` | 移除，改为细线进度或仅静态信息 | `lib/features/player/app_shell.dart` |
| `ChoiceChip` 主题切换、`FilledButton.icon` Hero CTA | 换为分段控件（Follow System / Light / Dark）与 §6.3 文字按钮 | `lib/features/settings/settings_screen.dart`、`lib/features/discover/discover_screen.dart` |

---

## 7. 卡片与列表的呈现方式

### 7.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下设计卡片与列表。专辑封面永远是 1:1 正方形、圆角 8pt、无描边，浅色下仅带极轻柔和投影（blur 16 / y 4 / alpha 0.10），深色下不带投影；封面本身保持原图，不叠标题、不加强压暗、不加播放量角标。封面下方是 15pt 半粗主标题（单行省略）与 13pt 次级灰副标题（最多两行、容器高度固定）。hover 时封面右下角淡入一枚 32pt 半透明深色圆形播放按钮（150ms），列表行则浮出右侧更多按钮。板块标题 22pt 粗体，右侧是 13pt 品牌红「查看全部 ›」文字链；横向货架的高度恰好等于封面边长 + 文字块高度，不多留 1px。列表行高 56pt：左侧 48pt 圆角 4pt 缩略封面或 11pt 等宽序号，中间 17pt 半粗曲名 + 13pt 次级歌手，右侧 12pt 等宽时长；行间只有一条从文字左沿起、右侧内缩 gutter 的 0.5pt 细线，无斑马纹、无卡片包裹、无左侧彩色竖条。歌单详情页顶部为大封面 + 右侧信息，背景取封面低饱和氛围色，下方紧接曲目列表。
```

### 7.2 卡片规格

| 项 | 值 |
|---|---|
| 封面比例 | 严格 1:1（`CoverImage` 保持 width = height） |
| 封面圆角 | 网格 / 货架 8pt；列表缩略 4pt；播放页大封面 12pt |
| 封面描边 | 无 |
| 封面阴影 | 仅浅色：`blur 16, offset(0,4), alpha 0.10`；深色：无 |
| 文字块 | 标题 15 / 20 w600 单行省略；副标题 13 / 18 w400 最多 2 行；标题上间距 8pt（`inline`） |
| 卡片总高 | `gridCardSize(width, columns) + inline + 38`（固定文字块，不允许文字撑开） |
| 角标 | 禁止播放量胶囊、VIP 标、版权角标压在封面上 |
| hover | 右下 32pt 圆形播放按钮（`rgba(0,0,0,0.55)` 底 + 白色实心三角，距边 8pt），150ms 淡入 |
| Hero 大图 | 底部 40% `transparent → am.scrim`；标题 28pt w700 白字；CTA 为 §6.3 文字按钮，禁止实心大按钮与全图 0.55 压暗 |

### 7.3 列表规格

| 项 | 值 |
|---|---|
| 行高 | 56pt（紧凑档 52pt），不允许内容撑高 |
| 缩略封面 | 48pt（紧凑 44pt），圆角 4pt |
| 主文 / 副文 | 17 / 22 w600 + 13 / 18 w400 `am.label.secondary` |
| 右侧 | 12pt w400 等宽时长 + hover 出现的 24pt 更多按钮 |
| 分隔线 | 0.5pt `am.separator`，左缩进 = `gutter + 48 + inline`，右缩进 = `gutter` |
| 状态 | hover / pressed 用 `am.fill.quaternary`，200ms 淡入；选中行用 `am.fill.selected` |
| 序号榜 | 11pt w500 等宽数字、`am.label.tertiary`，与封面位对齐 |
| 板块头 | 22 / 28 w700 + 右侧 13pt 品牌红「查看全部 ›」；头与内容间距 `block` |
| 货架 | `AppHorizontalStrip` 高度 = 卡片真实高度；卡片间距 `inline`；两端留 `gutter` |
| 网格 | `gridColumns` 推导列数，单元格间距 `inline`，卡片边长由 `gridCardSize` 推导 |

### 7.4 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| `GlassPanel` = 半透明色块 + 1px 描边 + 无模糊 | 改为 `AMSurface`：中性材质 + 20px 模糊 + hairline，且尽量少用（多数板块不加容器） | `lib/core/widgets.dart` |
| `PlaylistCard` 封面右上播放量胶囊（10.5pt）、标题 12.5pt / 2 行 | 删除胶囊；标题 15pt 单行、副标题 13pt；卡片总高按 §7.2 | 同上 |
| `SongTile` 44pt 封面 + 4pt 垂直内边距 ≈ 52–56pt 行 | 改为固定 56pt 行、48pt 缩略、hairline 内缩分隔线 | 同上 |
| `uiRadius / cardRadius` 随皮肤变化（14/12/18、0/12/0） | 改为固定圆角阶梯，见 §8.2 | `lib/core/styles.dart` |
| Hero `scrim` 0.05 → 0.55 全图压暗 + `FilledButton.icon` | 改底部 40% 0 → 0.35 压暗 + 文字按钮 | `lib/features/discover/discover_screen.dart` |

---

## 8. 间距与圆角等细节规范

### 8.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下统一细节。间距沿用 4pt 刻度（2/4/8/12/16/20/24/32）与五个语义角色：gutter 页面左右留白、section 板块之间、block 标题到内容、inline 同行元素、micro 元素内部；只上调页面级间距，元素内部 micro 在各断点恒为 4pt。圆角使用固定阶梯：专辑封面 8pt、列表缩略 4pt、播放页大封面 12pt、容器与面板 12pt、弹层 20pt、搜索框 10pt、侧栏选中行 8pt、胶囊 999pt、进度条轨道 2pt、拖拽把手 2pt；圆角不随主题或皮肤变化。分隔线一律 0.5pt hairline 并内缩对齐文字，不用 1px 高对比描边。阴影极轻且只在浅色出现（blur 16 / y 4 / alpha 0.10），弹层可到 blur 32 / y 12 / alpha 0.18，深色模式基本不用阴影而靠材质明度分层。所有可点击区域不小于 44pt，图标按钮视觉尺寸小但命中区补足。板块间距由板块自身承担，缺席时不残留空档。
```

### 8.2 间距语义表（**沿用项目 `AppSpacing`，数值不变**）

| 角色 | 紧凑 <600 | 中等 600–1024 | 宽松 ≥1024 | 用途 |
|---|---|---|---|---|
| `gutter` | 16 | 24 | 32 | 页面左右留白、侧栏/内容/播放条共同对齐线 |
| `section` | 20 | 24 | 24 | 板块之间的垂直间距（由板块自身承担） |
| `block` | 12 | 16 | 16 | 板块标题 ↔ 内容 |
| `inline` | 8 | 12 | 12 | 卡片之间、图标 ↔ 文字、网格单元格间距 |
| `micro` | 4 | 4 | 4 | 元素内部微间距（各档恒定） |

### 8.3 圆角 / 线 / 阴影阶梯

| 名称 | 令牌 | 值 |
|---|---|---|
| 专辑封面 | `am.radius.art` | 8 |
| 列表缩略 | `am.radius.thumb` | 4 |
| 播放页大封面 | `am.radius.hero` | 12 |
| 容器 / 面板 / 侧栏选中 | `am.radius.panel` | 12（选中行 8） |
| 弹层 sheet | `am.radius.sheet` | 20（仅上方两角） |
| 搜索框 | `am.radius.field` | 10 |
| 迷你播放器 | `am.radius.mini` | 10 |
| 药丸 / 胶囊 | `am.radius.pill` | 999 |
| 进度条 / 拖拽把手 | `am.radius.line` | 2 |
| 分隔线 | `am.line.hairline` | 0.5pt，`am.separator` |
| 卡片阴影（浅色） | `am.shadow.card` | `blur 16, offset(0,4), alpha 0.10` |
| 弹层阴影（浅色） | `am.shadow.sheet` | `blur 32, offset(0,12), alpha 0.18` |
| 深色阴影 | — | 不使用，靠 `am.bg.elevated` 与材质明度分层 |

### 8.4 其它细则

- **触控目标**：所有可点击元素命中区 ≥ 44 × 44pt；视觉图标可小于命中区。
- **材质模糊**：侧栏 / 顶栏 / 播放条 `sigma 20`；弹层 `sigma 24`；封面取色氛围底图 `sigma 40–60`。
- **对齐**：文字左沿统一；多行文字基线对齐；数字右对齐且等宽；不允许「正文居中、底栏通栏」两种节奏。
- **空态**：板块缺席时不插入占位 `SizedBox`；空列表用 17pt 主文 + 13pt 次级说明 + 24pt 线性图标，居中，无彩色插画。
- **禁止**：业务代码裸写 `10 / 14 / 18 / 22` 之类随手数字；随皮肤变化的圆角；1px 高对比描边卡片；大面积投影；多套并存的分隔线颜色。

---

## 9. 动效与过渡节奏

### 9.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下设计动效。静止画面完全安静，动效只发生在状态变化上：微交互（hover、pressed、图标淡入）150–200ms，常规状态切换（选中、标题收起、文字样式变化、展开收起）250–300ms，迷你播放器展开为全屏播放页 400–500ms 并用弹簧曲线，让专辑封面做共享元素连续放大、其余内容交叉淡入；歌词跟随滚动 350ms，当前行字号与透明度 300ms 过渡，逐字高亮严格按播放时间轴线性推进；换歌时封面与取色氛围层 600–800ms 交叉淡入。曲线统一 easeOutCubic（进场）/ spring（展开，damping 0.8）/ linear（进度与歌词时间轴）；退场用对应的 easeInCubic 且更短。下滑可关闭全屏播放页，跟手位移带轻微阻尼。绝对不要弹跳曲线、无限循环的呼吸/旋转/波形/涟漪动画，也不要给静止控件加装饰性运动。
```

### 9.2 时长与曲线总表

| 类别 | 时长 | 曲线 | 场景 |
|---|---|---|---|
| 微交互 | 150–200ms | `easeOutCubic` | hover 圆底、hover 播放按钮、进度条加粗、pressed |
| 常规状态 | 250–300ms | `easeOutCubic` | 侧栏选中、Tab 切换交叉淡入、紧凑标题栏淡入、收藏填充 |
| 文字 / 歌词 | 300–350ms | `easeOutCubic` | 歌词当前行字号与透明度、歌词滚动 |
| 展开式转场 | 400–500ms | spring（damping 0.8） | 迷你播放器 → 全屏播放页，封面共享元素 |
| 氛围过渡 | 600–800ms | `easeInOut` 交叉淡入 | 换歌时封面与取色背景切换 |
| 退场 | 上述时长的 60–80% | `easeInCubic` | 弹层关闭、播放页下滑关闭 |
| 进度 / 逐字高亮 | 跟随音频时间 | `linear` | 播放进度、歌词逐字填充 |
| 轻提示 | 2.6s 成功 / 3.6s 失败 | `easeOutCubic` | `buildAppSnackBar`，保留现有约定 |

### 9.3 必须实现的动效

1. **展开式转场**：点迷你播放器 → 封面从缩略位置连续放大到播放页大封面，播放条与标签栏淡出，播放页内容 300ms 后交叉淡入；反向收起对称。
2. **下滑关闭**：全屏播放页向下拖拽跟手位移，超过阈值松手关闭，未达阈值弹回（spring）。
3. **歌词跟随**：当前行居中滚动 350ms，字号 24 → 30pt / 透明度 45% → 100% 用 300ms；逐字填充用音频时间轴线性推进；手动滚动后 4s 恢复跟随（保留现有逻辑）。
4. **取色背景切换**：两帧封面取色氛围层交叉淡入，不闪烁、不跳色。
5. **大标题收起**：滚动越过大标题，紧凑材质标题栏 250ms 淡入，二者不重叠显示。

### 9.4 必须移除的动效

| 现状 | 位置 | 处置 |
|---|---|---|
| 黑胶同心纹 + 唱臂旋转（1200ms 循环） | `now_playing.dart` `_VinylPainter`、`constants.dart` `vinylWave / classic` | 删除，改用静态封面 |
| 三圈水波纹 / 涟漪（3600ms 循环） | `now_playing.dart` `_RipplePainter` / `_WaveLinePainter` | 删除 |
| 播放头持续呼吸（900ms repeat reverse） | `now_playing.dart` `_PulseThumb` | 改为仅 hover 显示 |
| 迷你条三柱均衡器（700ms repeat） | `app_shell.dart` `_StateBadge` | 删除，改为静态状态点或纯文字 |
| `easeOutBack` 弹跳切换 | `app_shell.dart` `AnimatedSwitcher` | 改 `easeOutCubic` |
| 胶片颗粒 / 暗角 | `styles.dart` `grain / vignette` | 删除 |
| 默认 GoRouter 页转场（无共享元素） | `lib/app/router.dart` | 为 `/now-playing`、`/queue` 配共享元素展开转场 |

---

## 10. 明暗主题适配

### 10.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下实现明暗双主题。默认跟随系统（ThemeMode.system），设置里另提供「浅色 / 深色」手动覆盖并持久化；所有颜色都必须取自成对的语义令牌，禁止在组件中硬编码任何色值。浅色材质是半透明白 + 20px 模糊 + 极浅黑色 hairline，深色材质是半透明深灰 + 20px 模糊 + 极淡白色 hairline；两种模式使用完全相同的布局、字号、圆角、间距与动效，只有颜色与材质不同。品牌红在浅色为 #FA243C、深色为 #FC3C44；正文对比度不低于 4.5:1，大字与图标不低于 3:1，深色下绝不出现纯黑文字。封面取色氛围层在浅色下更淡（alpha 0.10–0.16）且降饱和，深色下略强（0.18–0.28），但都必须保证标题可读；深色下不要额外压暗专辑封面。状态栏、滚动条、文本选择色、弹出菜单与系统控件同步切换。
```

### 10.2 实现契约

| 层 | 约定 |
|---|---|
| 主题入口 | `MaterialApp` 提供 `theme` / `darkTheme` / `themeMode`，`themeMode` 由 `themeModeProvider` 持久化（默认 `system`） |
| 色彩 | 定义 `ColorScheme` + `AMTheme`（`ThemeExtension`）；组件只读 `am.*` 语义令牌 |
| 字体 | 明暗共用 §4.2 type scale，不随主题改变字号字重 |
| 材质 | Light：`am.surface.panel` 半透白 + `sigma 20` + `am.separator`；Dark：半透深灰 + `sigma 20` + `am.separator` |
| 强调色 | 明暗两值；禁用态统一 0.3 alpha；红色面积一屏 ≤ 2% |
| 取色氛围 | Light alpha 0.10–0.16 / Dark 0.18–0.28；饱和度 ≤ 35%；两段主题共用同一模糊与三段渐隐参数 |
| 图片 | 深色下封面不额外压暗；浅色下封面不加白色蒙层；占位图用中性 `am.fill.quaternary` |
| 对比度 | 正文 ≥ 4.5:1、大字与图标 ≥ 3:1；`am.label.secondary` 在两种底色上都需校验 |
| 系统联动 | 状态栏亮度、滚动条、文本选择句柄、右键菜单、Tooltip、SnackBar 同步 |
| 兼容 | 三套旧皮肤（黑胶 / 橄榄绿 / 柔焦青）保留为可选实验项但默认关闭；不再作为主视觉口径 |

### 10.3 项目落地

| 现状 | 目标 | 位置 |
|---|---|---|
| 唯一 `ThemeData(brightness: Brightness.dark)`，无 `darkTheme` / `themeMode` / `ColorScheme` | 建立明暗 `ThemeData` + `ColorScheme` + `AMTheme` ThemeExtension，`ThemeMode.system` 默认 | `lib/app/app.dart` |
| 主题靠 `kStyles[styleIndexProvider]` 全局传参 | 改为 `Theme.of(context).extension<AMTheme>()`，组件不再依赖 `ref.watch(styleIndexProvider)` | `lib/core/styles.dart`、`lib/core/widgets.dart` 等 |
| 设置页 `ChoiceChip` 遍历三套 `kStyles` | 改为「跟随系统 / 浅色 / 深色」分段控件 | `lib/features/settings/settings_screen.dart` |
| `scaffoldBackgroundColor: Colors.transparent` + 全页渐变容器 | `scaffoldBackgroundColor: am.bg.base`，去掉渐变容器 | `lib/app/app.dart`、`app_shell.dart` |
| `AGENT.md` 弹层压黑约定、旧文档三套 token | 同步修订为语义令牌口径 | `AGENT.md`、`docs/ui-styles.json`、`docs/ui-style-prompts.md` |

---

## 11. 整体氛围与设计调性

### 11.1 局部提示词

```text
在 Apple Music 视觉语言（见风格锚点）下把整体调性定为「安静的高级感」：像系统自带应用一样不喧哗、不炫技，把全部注意力让给专辑封面与音乐内容。界面是可信的中性画布，编辑感来自克制的排版、精确的对齐与大块留白，而不是特效；色彩只在封面与一处品牌红上出现；触感轻盈、层次分明、信息密度适中，任何一屏都能在 1 秒内看清「我在哪里、当前播什么、下一步能点什么」。情绪关键词：克制、编辑感、轻盈、安静、可信、系统原生、专辑优先。反义词：炫彩、拟物、赛博、潮牌、街头、颗粒复古、玻璃糖果感、重度发光。
```

### 11.2 分页面调性一句话

| 页面 | 调性要求 |
|---|---|
| 发现 / 浏览 | 编辑排期感：大标题 + 一个 Hero + 若干横向货架，留白比内容多 |
| 搜索 | 安静高效：搜索框置顶，结果按「歌曲 / 艺人 / 专辑 / 歌单」分组，无彩色标签墙 |
| 音乐库 | 秩序感：分组清晰、列表密集但通透，缩略封面是唯一色彩 |
| 歌单详情 | 专辑优先：顶部大封面 + 取色氛围，下方列表直铺，不套卡片 |
| 全屏播放页 | 沉浸但不迷幻：静态大封面、细进度、白字歌词，背景只做轻微取色呼吸 |
| 歌词 / 队列 | 附属层：半透明材质浮层，不与主内容争夺对比度 |
| 设置 / 账户 | 系统设置感：分组列表、开关右置，无装饰插画 |

### 11.3 Do / Don't 一览

| Do | Don't |
|---|---|
| 用字号、字重、留白建立层级 | 用描边、投影、色块、彩色药丸建立层级 |
| 让封面成为唯一色彩来源 | 用彩色渐变给整页定调 |
| 中性材质 + 极细 hairline | 重黑压暗玻璃 + 1px 高对比描边 |
| 固定圆角阶梯与语义间距 | 圆角、字号、强调色随皮肤变化 |
| 短促、状态驱动的过渡 | 无限循环的装饰动画与弹跳 |
| 明暗共用一套布局与节奏 | 浅色模式只是把深色玻璃调亮 |
| 无边框圆形按钮 + 填充态图标 | Material 控件、水波纹、竖向三点 |
| 封面下方放标题 | 在封面上压字、加播放量角标 |

---

## 12. 设计令牌总表（开发唯一取值来源）

### 12.1 令牌速查

| 类别 | 令牌 | Light | Dark |
|---|---|---|---|
| 背景 | `am.bg.base` | `#FFFFFF` | `#000000` |
| 背景 | `am.bg.grouped` | `#F5F5F7` | `#1C1C1E` |
| 背景 | `am.bg.elevated` | `#FFFFFF` | `#2C2C2E` |
| 材质 | `am.surface.panel` | `rgba(255,255,255,0.72)` | `rgba(44,44,46,0.68)` |
| 材质 | `am.material.blur` | `sigma 20`（弹层 24 / 氛围层 40–60） | 同左 |
| 材质 | `am.material.bar` | `am.surface.panel` + `sigma 20` + `am.line.hairline` | 同左（换深灰底） |
| 文字 | `am.label.primary` | `#1D1D1F` | `#FFFFFF` |
| 文字 | `am.label.secondary` | `#6E6E73` | `rgba(235,235,245,0.60)` |
| 文字 | `am.label.tertiary` | `#8E8E93` | `rgba(235,235,245,0.30)` |
| 线 | `am.separator` | `rgba(60,60,67,0.18)` | `rgba(84,84,88,0.60)` |
| 线 | `am.line.hairline` | 0.5pt `am.separator` | 0.5pt `am.separator` |
| 填充 | `am.fill.quaternary` | `rgba(116,116,128,0.08)` | `rgba(118,118,128,0.24)` |
| 填充 | `am.fill.selected` | `rgba(250,36,60,0.10)` | `rgba(252,60,68,0.16)` |
| 强调 | `am.accent` | `#FA243C` | `#FC3C44` |
| 强调 | `am.accent.on` | `#FFFFFF` | `#FFFFFF` |
| 遮罩 | `am.scrim` | `rgba(0,0,0,0.35)` | `rgba(0,0,0,0.45)` |
| 字体 | `am.font.display` | `SF Pro Display` / `PingFang SC` | 同左 |
| 字体 | `am.font.text` | `SF Pro Text` / `PingFang SC` | 同左 |
| 字号 | `am.type.*` | §4.2 九个层级 | 同左 |
| 间距 | `am.space.*` | §8.2 五个语义角色 × 三档断点 | 同左 |
| 圆角 | `am.radius.art / thumb / hero / panel / sheet / field / mini / pill / line` | `8 / 4 / 12 / 12 / 20 / 10 / 10 / 999 / 2` | 同左 |
| 阴影 | `am.shadow.card / sheet` | `blur16 y4 .10` / `blur32 y12 .18` | 不使用 |
| 动效 | `am.motion.micro / state / expand / tint` | `200 / 300 / 500 / 800 ms` | 同左 |
| 布局 | `am.layout.sidebar / breakpoint / contentMax` | `250pt` / `600·820·960·1024` / `1180pt` | 同左 |

### 12.2 机器可读片段（可直接并入 `docs/ui-styles.json`）

```json
{
  "id": "apple-music",
  "name": "Apple Music 原生风格",
  "default": true,
  "themeMode": "system",
  "tokens": {
    "color": {
      "light": {
        "bgBase": "#FFFFFF", "bgGrouped": "#F5F5F7", "bgElevated": "#FFFFFF",
        "surfacePanel": "rgba(255,255,255,0.72)",
        "labelPrimary": "#1D1D1F", "labelSecondary": "#6E6E73", "labelTertiary": "#8E8E93",
        "separator": "rgba(60,60,67,0.18)", "fillQuaternary": "rgba(116,116,128,0.08)",
        "fillSelected": "rgba(250,36,60,0.10)", "accent": "#FA243C", "scrim": "rgba(0,0,0,0.35)"
      },
      "dark": {
        "bgBase": "#000000", "bgGrouped": "#1C1C1E", "bgElevated": "#2C2C2E",
        "surfacePanel": "rgba(44,44,46,0.68)",
        "labelPrimary": "#FFFFFF", "labelSecondary": "rgba(235,235,245,0.60)",
        "labelTertiary": "rgba(235,235,245,0.30)",
        "separator": "rgba(84,84,88,0.60)", "fillQuaternary": "rgba(118,118,128,0.24)",
        "fillSelected": "rgba(252,60,68,0.16)", "accent": "#FC3C44", "scrim": "rgba(0,0,0,0.45)"
      }
    },
    "typography": {
      "family": ["SF Pro Display", "SF Pro Text", "PingFang SC"],
      "scale": { "largeTitle": 34, "title1": 28, "title2": 22, "title3": 20, "headline": 17, "body": 15, "subhead": 13, "footnote": 12, "caption": 11 },
      "tabularNumbers": true
    },
    "layout": {
      "sidebarWidth": 250, "bottomBarHeight": 72, "listRowHeight": 56,
      "thumbSize": 48, "gridMinCard": 150, "gridMaxColumns": 6,
      "breakpoints": { "compact": 600, "sidebar": 820, "splitPlayer": 960, "expanded": 1024 },
      "contentMaxWidth": 1180, "macTrafficLightInset": 30
    },
    "radius": { "art": 8, "thumb": 4, "hero": 12, "panel": 12, "sheet": 20, "field": 10, "mini": 10, "pill": 999, "line": 2 },
    "material": { "barBlur": 20, "sheetBlur": 24, "backdropBlur": 40, "hairline": 0.5 },
    "backdrop": { "source": "cover-dominant-color", "maxSaturation": 0.35, "alpha": { "light": 0.16, "dark": 0.28 }, "coverage": 0.6, "fadeStops": [0.45, 0.78, 1.0] },
    "motion": { "micro": 200, "state": 300, "expand": 500, "lyric": 350, "tint": 800, "curve": "easeOutCubic", "expandCurve": "spring" },
    "texture": { "grain": false, "vignette": false, "skeuomorphism": false, "loopingDecorations": false },
    "mood": ["restrained", "editorial", "airy", "calm", "system-native", "album-forward"]
  }
}
```

---

## 13. 项目落地映射（现状 → 目标，改造清单）

| 优先级 | 文件 | 改造动作 |
|---|---|---|
| P0 | `lib/app/app.dart` | 明暗 `ThemeData` + `ColorScheme` + `ThemeMode.system`；字体栈改 SF Pro / 苹方；去掉透明 scaffold + 渐变容器 |
| P0 | `lib/core/styles.dart` | 新增 `AMTheme`（`ThemeExtension`）与 `kAppleMusicTokens`；删除 `backgroundGradient` / `scrim` 原参数 / `grain` / `vignette` / `blur` / `titleSize` / `titleWeight` / `letterSpacing` / `uiRadius` / `cardRadius`；保留 `AppSpacing` 全部数值；`gridColumns.minCard` 130 → 150 |
| P0 | `lib/providers.dart` | `styleIndexProvider` → `themeModeProvider`（system / light / dark），旧皮肤作为可选实验项 |
| P0 | `lib/features/player/app_shell.dart` | 侧栏三段分组 + 搜索框；底部通栏 72pt 播放条；取消悬浮导航坞、环形进度、黑胶状态柱；选中态改浅底红图标；保留 `useSidebar ≥820`、`macInset 30`、`_indexFor` |
| P0 | `lib/features/player/now_playing.dart` | 全屏背景改中性底 + 降饱和取色氛围；删除 `_VinylPainter` / `_RipplePainter` / `_WaveLinePainter` / `_PulseThumb`；进度条 3→5pt；控件换图标；宽屏左右分栏保留 |
| P1 | `lib/core/widgets.dart` | `GlassPanel → AMSurface`；`PlaylistCard` / `SongTile` / `SectionHeader` / `AppHorizontalStrip` 按 §7 规格；新建 `AMIcons`；`buildAppSnackBar` 换中性底 |
| P1 | `lib/features/player/lyrics_view.dart` | 去掉发光阴影；30 / 24pt 层级；逐字填充高亮；玻璃层；保留 4s 恢复跟随 |
| P1 | `lib/features/discover/discover_screen.dart` | Hero 压暗改底部 40% → 0.35；实心 CTA 改文字按钮；卡片按 §7.2；网格取 `minCard 150` |
| P1 | `lib/features/settings/settings_screen.dart` | 主题切换改「跟随系统 / 浅色 / 深色」分段控件 |
| P1 | `lib/app/router.dart` | `/now-playing`、`/queue` 增加共享元素展开转场（Hero / CustomTransitionPage），其余沿用默认转场 |
| P1 | `lib/features/player/*_sheet.dart`、`AGENT.md` | 弹层底色改中性材质，取消 `0x8C000000` 压黑；同步修订 Toast / 弹层约定 |
| P2 | `lib/features/player/comments_sheet.dart`、`queue_screen.dart`、`add_to_playlist_sheet.dart` | 弹层圆角 20、hairline、分组列表样式对齐 §7.3 |
| P2 | `lib/features/library/*`、`playlist/*`、`search/*`、`stats/*`、`auth/*` | 散落 `TextStyle` / `Color(0x…)` 收敛到 `am.*` 令牌 |
| P2 | `pubspec.yaml` | 补齐字体与图标资源（CupertinoIcons 或内置 SF Symbols 风格资源），移除未用依赖 |
| P2 | `docs/ui-styles.json`、`docs/ui-style-prompts.md` | 写入 §12.2 片段；三套旧风格标注为归档 |

---

## 14. 验收清单（逐条勾选）

- [ ] 全应用主背景为恒定中性色，浅色 `#FFFFFF` / 深色 `#000000`，不存在全屏彩色渐变
- [ ] 一屏内唯一非中性色是封面与品牌红；红色面积 ≤ 2%
- [ ] 桌面为 250pt 侧栏 + 内容区 + 72pt 通栏播放条；侧栏有搜索框与三个分组标题
- [ ] 断点、间距语义值、`AppContentColumn` 封顶规则与现有项目一致，无随手数字
- [ ] 全应用只有一套九级字号阶梯；中文用苹方；数字等宽；无宽字距 / 手写体 / 发光歌词
- [ ] 图标为统一 SF Symbols 风格，无 `Icons.more_vert` / `play_circle_fill` 等 Material 语义残留
- [ ] 专辑封面 1:1、圆角 8pt、无描边、封面不压文字、无播放量角标
- [ ] 列表行 56pt、缩略 48pt、0.5pt 内缩分隔线，无斑马纹与卡片包裹
- [ ] 圆角、阴影、材质模糊全部取自 §8 / §12 令牌，不随主题或皮肤变化
- [ ] 进度条 3pt（hover 5pt）、播放头仅交互时出现；无环形进度与持续呼吸
- [ ] 静止画面无任何循环动画；黑胶、波形、涟漪、颗粒、暗角、均衡器柱均已移除
- [ ] 迷你播放器 → 播放页为 400–500ms 弹簧展开 + 封面共享元素过渡
- [ ] `ThemeMode.system` 生效，明暗两套语义令牌一一对应，正文对比度 ≥ 4.5:1
- [ ] 组件中无硬编码色值；`style.accent` / `uiRadius` / `cardRadius` 已全部下线
- [ ] `docs/ui-styles.json` 与 `AGENT.md` 已同步到新口径

---

## 15. 维护约定

- 本文是 `apple-music` 风格的唯一提示词真源；新增页面只需组合 §2–§11 章节，不另写风格描述。
- 任何令牌变更必须同时更新：本文 §12、`lib/core/styles.dart` 的 `AMTheme`、`docs/ui-styles.json` 三处，避免出现项目里已发生过的「文档与代码不同步」。
- 三套旧风格（`vinyl-sunset` / `bold-olive` / `soft-teal`）仅作归档与可选实验皮肤，不得作为改版后的评审参照。





