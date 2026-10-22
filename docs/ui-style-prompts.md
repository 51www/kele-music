# UI 风格提示词 · 三套可切换方案

> 来源：三张网易云音乐播放页参考图。仅提取**风格层**信息（配色、版式、字体、质感、情绪、组件规则），不含具体歌曲内容。
> 用途：作为可切换主题（`styleId`）的设计规范 / 生成提示词。配套机器可读文件：`docs/ui-styles.json`。

---

## 总览

| ID | 名称 | 主色 | 版式特征 | 情绪关键词 |
|---|---|---|---|---|
| `vinyl-sunset` | 暖调黑胶复古 | 赤陶橙 → 深棕黑 | 居中黑胶唱片 + 唱臂，无卡片 | 怀旧 / 模拟 / 温暖 / 发烧友 |
| `bold-olive` | 极简专辑卡·橄榄绿 | 深橄榄绿 + 亮黄 | 大圆角专辑卡占上半屏，高对比 | 现代 / 潮流 / 编辑感 / 专辑优先 |
| `soft-teal` | 柔焦梦幻青 | 青绿 → 雾蓝 | 封面柔焦融入背景，无硬边界 | 空灵 / 静谧 / 梦幻 / 呼吸感 |

---

## 风格 A · `vinyl-sunset` 暖调黑胶复古

### 中文详细提示词
设计一个音乐播放页，整体为暖调黑胶复古风。背景采用垂直渐变：顶部暖赤陶橙 / 锈橙，向下过渡到深棕近黑，叠加细腻**胶片颗粒**与轻微**暗角**，营造夕阳余晖下的私密氛围。视觉中心是一张正圆形**黑胶唱片**，黑色盘面带细密同心纹路，唱片中央嵌入圆形专辑封面（暖橙黄昏色调），一枚**银色唱臂**从右上方斜向搭在唱片上。顶部为白色细体返回箭头、歌曲名（白色中等字重）、歌手名（半透明白）与下载图标。底部依次为：一排圆形描边操作图标、极细半透明白色进度条与两端时间；播放控制区为白色线性图标（循环、上一首、圆形描边播放/暂停、下一首、播放列表）。整体**无卡片、无多余装饰**，以唱片为唯一主角。情绪：怀旧、模拟、温暖、发烧友、亲密。

### English prompt
Warm analog vinyl music player UI. Vertical gradient from terracotta / rust orange to deep near-black brown, with fine film grain and soft vignette, evoking a sunset afterglow. Centerpiece is a large circular black vinyl record with concentric grooves and circular album art embedded in the middle; a silver tonearm rests diagonally from the upper right onto the record. Top bar: thin white back chevron, white medium-weight song title, translucent white artist name, download icon. Bottom: a row of circular outline action icons, an ultra-thin translucent white progress bar with times, and a control row of white line icons (repeat, previous, circular-outline play/pause, next, playlist). No cards, no decoration — the record is the hero. Mood: nostalgic, analog, warm, audiophile, intimate.

### 设计令牌
| 项 | 值 |
|---|---|
| 背景渐变 | `#C4643A` → `#8A4028` → `#2A1A14`（上→下） |
| 主文字 | `#F5EDE6` |
| 次文字 | `rgba(245,237,230,0.6)` |
| 点缀 / 唱臂 | `#B85C3A` / 银 `#D8D2C8` |
| 字体 | 细体无衬线（标题可用过渡衬线），字距略开 |
| 圆角 | 无卡片；唱片为正圆 |
| 质感 | 胶片颗粒 + 暗角 |
| 进度条 | 极细半透明线 |

### 组件规则
- 封面以「圆形唱片 + 中心圆形封面」呈现，不用矩形卡片。
- 播放键用**圆形描边**包裹，其余控制为线性图标。
- 操作图标带圆形描边底，弱化存在感。

---

## 风格 B · `bold-olive` 极简专辑卡·橄榄绿

### 中文详细提示词
设计一个现代极简的音乐播放页，采用深橄榄绿单色背景（顶部略亮、底部略暗的微渐变）。顶部居中一个细小拖拽条。上方约 55% 为一张**大尺寸圆角方形专辑封面卡**（圆角约 12px），封面为高饱和人物摄影，叠加**亮黄色手写体**标题。封面下方左对齐：歌曲名（白色粗体大字号）、歌手名（浅灰绿小字号），右侧一个三点更多按钮。再下方为细白色进度条与两端时间，中央一个「Dolby Atmos」小标识。播放控制区为三枚**大号白色实心图标**（上一首、暂停、下一首），间距大、字重粗。底部为极简底部导航（歌词/评论、我的、列表）。整体**高对比、留白克制、无阴影无描边、扁平**。情绪：现代、潮流、编辑感、专辑优先、流媒体。

### English prompt
Modern minimal music player UI. Solid deep olive-green background with a subtle top-to-bottom gradient. A small drag handle centered at top. The upper ~55% is a large rounded-square album art card (≈12px radius) with saturated portrait photography and a bold **yellow script** title overlay. Below, left-aligned bold white song title and muted light-green artist name, with a three-dot more button on the right. Then a thin white progress bar with times, and a small "Dolby Atmos" badge centered. Transport row: three large solid white icons (previous, pause, next) with wide spacing and heavy weight. Minimal bottom tab bar (lyrics/comments, profile, playlist). Flat, high-contrast, restrained whitespace, no shadows or borders. Mood: modern, trendy, editorial, album-forward, streaming app.

### 设计令牌
| 项 | 值 |
|---|---|
| 背景 | `#3A4423` → `#2C341A`（微渐变） |
| 主文字 | `#F2F2EC` |
| 次文字 | `#9AA37E` |
| 强调（字幕/标签） | `#E8D44D`（亮黄） |
| 字体 | 无衬线；标题粗体大字，副标题常规小字 |
| 圆角 | 专辑卡 12px；整体扁平 |
| 质感 | 无纹理、无阴影、无描边 |
| 进度条 | 细实线，白色 |

### 组件规则
- 专辑封面为**硬边界大圆角卡片**，占据视觉主导。
- 播放控制为**实心大图标**，不用圆形底。
- 信息层级靠字号与字重拉开（标题大粗 / 副标题小灰）。
- 底色接近单色，靠跃动的封面图与亮黄字幕制造对比。

---

## 风格 C · `soft-teal` 柔焦梦幻青

### 中文详细提示词
设计一个柔和梦幻的音乐播放页，背景为青绿到雾蓝的柔和渐变（顶部深青绿、中部青、底部雾蓝绿），整体**低饱和、雾面**质感。专辑封面**不做硬边界卡片**，而是以低透明度、**柔焦模糊**的方式融入背景上半部，形成氛围底图。画面上方叠加白色细体大标题与上方小号歌手名，左上角小号歌曲信息、右上角小号标签文字。中部为细进度条与时间、Dolby Atmos 标识。播放控制为三枚白色线性图标（上一首、暂停、下一首）。下方一条**较宽的半透明滑动条**，带圆形滑块。底部为三枚线性导航图标。整体**无边框、无阴影、大量留白与柔光**。情绪：空灵、静谧、梦幻、呼吸感、极简。

### English prompt
Soft dreamy music player UI. Smooth gradient from deep teal to misty blue-green, low saturation and matte-fog finish. The album art has **no hard card edges** — it is blurred and faded at low opacity into the upper background as an atmospheric backdrop. White thin large title overlaid, with a smaller artist name above it, small track info at top-left and a small tag label at top-right. Middle: thin progress bar with times and a Dolby Atmos badge. Transport: three white line icons (previous, pause, next). Below: a wider translucent scrubber with a round thumb. Minimal three-icon bottom nav. Borderless, shadowless, generous whitespace and soft light. Mood: ethereal, calm, dreamy, airy, minimal.

### 设计令牌
| 项 | 值 |
|---|---|
| 背景渐变 | `#2E6E6A` → `#4E8C8A` → `#6FA8A0`（上→下） |
| 主文字 | `#EAF4F2` / `#FFFFFF` |
| 次文字 | `rgba(234,244,242,0.7)` |
| 封面处理 | 低透明度 + 高斯模糊，融入背景 |
| 字体 | 细体无衬线，标题大而轻 |
| 圆角 | 无硬边界；滑块为正圆 |
| 质感 | 雾面、柔光、无纹理 |
| 进度条 | 宽半透明滑动条 + 圆形滑块 |

### 组件规则
- 封面**弱化为氛围层**，不加卡片、不加边框。
- 标题直接压在模糊封面上，靠文字而非容器分区。
- 主进度条改为可拖拽的宽滑块，强化交互感。

---

## 在项目中如何切换

- **数据层**：读取 `docs/ui-styles.json`，按 `styleId`（`vinyl-sunset` / `bold-olive` / `soft-teal`）取 `tokens`。
- **Flutter 层**：把 `tokens.color / typography / layout / texture` 映射为 `ThemeExtension`，切换时只换主题扩展 + 切换「封面呈现组件」（圆形唱片 / 圆角卡片 / 柔焦背景）三选一。
- **提示词复用**：`promptZh` / `promptEn` 可直接喂给设计或图像生成工具，产出同风格新皮肤；新增风格时按同结构追加即可。

---

## 间距体系（跨风格通用，与 `lib/core/styles.dart` 的 `AppSpacing` 一一对应）

三套风格共用同一套间距刻度——**间距属于布局，不属于风格**，因此只维护一份。

### 4pt 刻度层

`2 / 4 / 8 / 12 / 16 / 20 / 24 / 32`（`AppSpacing.xxs … xxxl`）。业务代码只写语义层，刻度层仅供语义层引用。

### 五个语义角色

| 角色 | 含义 | 用在哪 |
|---|---|---|
| `gutter` | 页面左右留白 | 所有页面的横向内边距；底部导航坞 / 迷你播放条也取它，保证边缘对齐 |
| `section` | **栏目板块之间的垂直间距** | 每个板块自己承担（全应用唯一来源） |
| `block` | 板块标题 ↔ 该板块内容；同层紧密堆叠 | `SectionHeader` 默认下边距 |
| `inline` | 同一行 / 同一流相邻元素 | 横向卡片间距、图标↔文字、网格单元格间距 |
| `micro` | 元素内部微间距 | 文字行与行、角标内边距 |

### 响应式分档

| 角色 | 紧凑 <600 | 中等 600–1024 | 宽松 ≥1024 |
|---|---|---|---|
| `gutter` | 16 | 24 | 32 |
| `section` | 20 | 24 | 24 |
| `block` | 12 | 16 | 16 |
| `inline` | 8 | 12 | 12 |
| `micro` | 4 | 4 | 4 |

断点只上调「页面级」间距；`micro` 各档不变，否则宽屏下整页会被吹散。宽松档额外把内容列封顶在 720 并居中（`AppContentColumn`），避免行长过长。

### 落地约定

- 板块上边距由**板块自身**承担（`AppSection` / 各页 `_xxxBlock`），**不要**在父级 ListView 里插 `SizedBox`。否则板块因游客态 / 空数据缺席时空档会残留，相邻两处留白就会一宽一窄。
- 横向滚动条一律用 `AppHorizontalStrip`，高度必须等于子项真实高度——多留 2px 就是「这一处的间距比别处宽」。
- 网格列数与卡片边长由 `AppSpacingMetrics.gridColumns / gridCardSize` 一起推导，卡片正好铺满列宽，右侧不留残余空档。
- 业务代码里不再出现裸写的 `10 / 14 / 18 / 22` 这类随手数字。
