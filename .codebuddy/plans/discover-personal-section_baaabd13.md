---
name: discover-personal-section
overview: 在发现页新增「个人专属」歌单板块（仅已登录展示），并将现有 Hero 大卡与推荐歌单区从「每日推荐」置顶逻辑中解耦。
design:
  styleKeywords:
    - Material Design
    - 卡片化
    - 横向滚动
    - 与现有一致
  fontSystem:
    fontFamily: PingFang-SC
    heading:
      size: 18px
      weight: 700
    subheading:
      size: 13px
      weight: 500
    body:
      size: 12px
      weight: 400
  colorSystem:
    primary:
      - "#FF3A3A"
    background:
      - "#121212"
    text:
      - "#FFFFFF"
      - "#B3B3B3"
    functional:
      - "#1DB954"
todos:
  - id: refactor-load-state
    content: 重构 _load 拆分 _recommendPlaylists 字段并解耦 Hero/推荐歌单区置顶逻辑
    status: completed
  - id: add-personal-section
    content: 实现「个人专属」板块：登录可见、横向滑动、每日推荐卡加推荐歌单
    status: completed
    dependencies:
      - refactor-load-state
  - id: play-daily-recommend
    content: 实现每日推荐卡点击调 /recommend/songs 直接起播并进入播放页
    status: completed
    dependencies:
      - add-personal-section
  - id: adjust-hero-playlists
    content: Hero 徽章改「编辑精选」并移除推荐歌单区跳过首张逻辑
    status: completed
    dependencies:
      - refactor-load-state
  - id: handle-auth-refresh
    content: 用 authStateProvider 监听登录态变化并触发发现页重新加载
    status: completed
    dependencies:
      - add-personal-section
---

## 用户需求

在发现页「推荐歌单」区域上方新增一个名为「个人专属」的歌单类型板块，仅对已登录用户展示；未登录用户不显示该板块。

## 产品概述

在发现页的快捷入口与推荐歌单之间，插入一个横向滑动的「个人专属」板块，作为登录用户专属的每日推荐与个性化歌单入口。板块视觉与现有「推荐歌单」区保持一致（同款 SectionHeader + 横向 PlaylistCard 卡片），保证整体协调。

## 核心功能

- 仅 `AuthStatus.authenticated` 时渲染「个人专属」板块；游客态整块隐藏。
- 板块内歌单横向排列，支持左右滑动浏览（复用现有 ScrollConfiguration + 横向 ListView 结构）。
- 第一张卡片固定为「每日推荐」：封面借用 /recommend/resource 返回的第一张真实歌单封面，名字固定「每日推荐」；点击后调用 /recommend/songs 拉取每日推荐歌曲并直接起播、进入播放页。
- 其余卡片来自 /recommend/resource（/recommend/resource 接口，封装为 recommendPlaylists()），点击跳转歌单详情页 /playlist/{id}。
- 已登录但 /recommend/resource 返回空/失败时，板块仍只展示「每日推荐」单卡（点击可起播），其余不展示。
- 同步调整：Hero 大卡不再承载每日推荐入口，改为展示 /personalized 首张歌单、徽章显示「编辑精选」；推荐歌单区去掉「跳过第一张」逻辑，展示全部 /personalized 歌单。

## 技术栈

- 框架：Flutter（Dart），状态管理 flutter_riverpod
- 路由：go_router
- 现有封装：`api.recommendPlaylists()`（/recommend/resource）、`api.recommendSongs()`（/recommend/songs）、`api.personalizedPlaylists()`（/personalized）、`play.playQueue()`（起播）；常量 `kDailyRecommendId`
- 登录态：`authStateProvider` / `AuthStatus.authenticated`

## 实现方案

核心策略：把发现页 `_load()` 中原本"为 Hero/推荐歌单区置顶每日推荐"的逻辑彻底解耦——Hero 只展示个性化首张歌单，/recommend/resource 的数据独立成字段 `_recommendPlaylists` 专供新「个人专属」板块使用。板块组件完全复用现有 `_buildPlaylistsSection` 的横向滑动结构（PlaylistCard size=130 + ScrollConfiguration + ListView.separated），保证视觉与交互一致，不引入新 UI 模式。

关键决策与权衡：

- **数据拆分**：`_load()` 现从 `Future.wait` 的第四项（recommendPlaylists）取出后塞进 `_playlists` 并置顶；改为把该结果单独存 `_recommendPlaylists`，`_playlists` 仅保留 `personalizedPlaylists()` 原始顺序（无置顶）。这样 Hero（`_playlists.first`）自然变成「编辑精选」，推荐歌单区无需 `sublist(1)` 跳过。
- **零额外请求**：「每日推荐」卡封面沿用现有合成入口做法——借 `_recommendPlaylists.first.coverImgUrl`，不额外调用 /recommend/songs，起播时再拉歌曲（与需求"点击后播放"一致）。
- **板块内容拼接**：`items = [每日推荐合成卡] + _recommendPlaylists`；当 `_recommendPlaylists` 为空（接口失败/过期）时 items 仅含每日推荐卡，满足"仅留每日推荐卡"。
- **登录态刷新**：`DiscoverScreen` 当前仅在 `initState` 加载一次。为支持"进入发现页后才登录"的场景，在 `build` 中用 `ref.watch(authStateProvider)` 取登录态，并用 `ref.listen` 监听 `authStateProvider`，状态从非登录变登录时重新调用 `_load()`，使板块在登录后即时出现。该监听需 `onDispose` 取消。
- **起播逻辑**：新增 `_playDailyRecommend()`：复用 `_busyHero` 忙锁，调用 `recommendSongs()` → `playQueue(ref, songs, 0)` → `context.push('/now-playing')`；失败用 SnackBar 提示（与 `_playPlaylist` 错误处理一致）。

## 实现注意

- 保持 `_playPlaylist` 现有 `kDailyRecommendId` 分支兼容（虽不再作为 Hero 首张，但作为个人专属每日卡仍可经其逻辑，建议改为直接调用 `_playDailyRecommend`）。
- Hero 徽章判定（269-286 行的 `_dailyFirst`/`今日推荐`/`每日推荐` 条件）简化为恒显「编辑精选」。
- 仅在 `authStateProvider.status == authenticated` 时渲染个人专属板块；`recommendPlaylists().catchError` 兜底为空数组，避免未登录/失败抛错。
- 不改动 `api_client.dart`、`constants.dart` 的现有接口与常量（仅可将 constants.dart 中 kDailyRecommendId 注释从"点击进入每日推荐页"更新为"点击直接起播"，非必须）。
- 避免新增全局状态；新增字段 `_recommendPlaylists`、`_loggedIn` 仅限本 State 内。

## 架构设计

发现页 `DiscoverScreen` 内部状态拆分：

- `_playlists`：/personalized 原始顺序（Hero + 推荐歌单区数据源）
- `_recommendPlaylists`：/recommend/resource（个人专属板块数据源，含每日推荐合成卡）
- `_loggedIn`：登录态缓存（来自 authStateProvider）
渲染顺序：Hero（编辑精选）→ 快捷入口 → **个人专属**（仅登录）→ 推荐歌单（全部个性化）→ 新歌速递 → 排行榜

## 目录结构

```
lib/features/discover/discover_screen.dart   # [MODIFY] 重构 _load() 拆分每日推荐数据；新增 _recommendPlaylists / _loggedIn 字段；新增 _buildPersonalSection()（仅登录可见、横向滑动、每日推荐卡 + 推荐歌单，复用 PlaylistCard/ScrollConfiguration）；新增 _playDailyRecommend() 起播逻辑；Hero 徽章改为「编辑精选」；_buildPlaylistsSection 去掉 sublist(1)；在 build 中用 ref.watch(authStateProvider) 控制板块可见并用 ref.listen 处理登录后刷新；在 body Column 的 _buildQuickEntries 与 _buildPlaylistsSection 之间插入 _buildPersonalSection
lib/core/constants.dart                      # [MODIFY]（可选）更新 kDailyRecommendId 注释，从"点击进入每日推荐页"改为"点击直接起播每日推荐歌曲"
```

## 设计风格

新增「个人专属」板块严格复用发现页现有视觉体系，不引入新风格：使用与「推荐歌单」区一致的 SectionHeader（标题左对齐、accent 色「更多」按钮，本板块无更多按钮），下接横向滚动的 PlaylistCard（size=130，封面圆角 + 歌名单行省略 + 播放量次播放）。背景沿用页面渐变，卡片间距 12，板块上下间距 20，与相邻板块保持节奏统一。第一张「每日推荐」卡与真实歌单卡外观完全一致，仅名字固定为「每日推荐」、封面借首张真实歌单图，保证视觉无割裂。Hero 大卡徽章由条件判断简化为恒显「编辑精选」，其余压暗渐变、信息层、播放 CTA 布局不变。