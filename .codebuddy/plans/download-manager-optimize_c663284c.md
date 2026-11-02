---
name: download-manager-optimize
overview: 优化下载管理页：去掉已下载列表卡片背景、隐藏 VIP 标记并把时长改为文件大小显示、新增多选模式与批量删除（连文件一起删除）。
todos:
  - id: songtile-params
    content: widgets.dart：SongTile 新增 showVip（默认 true）与 onLongPress 可选参数并接入 InkWell，不影响既有调用方
    status: completed
  - id: registry-batch-delete
    content: download_registry.dart：DownloadRegistryNotifier 新增 forgetAndDeleteCache，删 localPath 缓存文件（Web/null 跳过、失败容错）后撤销登记并落盘
    status: completed
  - id: screen-visual
    content: download_manager_screen.dart：去掉列表 GlassPanel 卡片背景；已下载行隐藏 VIP、durationMs 置空并在 trailing 显示文件大小（无数据显示—）+ 保留删除按钮
    status: completed
    dependencies:
      - songtile-params
  - id: screen-multiselect
    content: download_manager_screen.dart：播放栏加「管理」按钮、长按进多选、多选扩展到已下载歌曲（复合 key/歌曲选择行/全选）、批量删除接 forgetAndDeleteCache 并更新确认弹窗文案
    status: completed
    dependencies:
      - screen-visual
      - registry-batch-delete
  - id: verify
    content: 运行 flutter analyze 验证无新增告警，确认多选/批量删除/大小显示逻辑自洽
    status: completed
    dependencies:
      - screen-multiselect
---

## 需求概述

优化「下载管理」页（e:/www/kele-music，Flutter 音乐客户端）的三个点：

## Product Overview

下载管理页承载下载任务与已下载歌曲的查看、播放、删除。本次优化视觉与批量操作能力。

## Core Features

1. **去掉已下载列表卡片背景**：移除列表外层的 GlassPanel 卡片容器，列表直接融入页面渐变背景；保留「已下载 N」小节标题与「序号+封面+歌名+歌手」行布局（用户已确认）。
2. **行内容调整**：已下载歌曲行不显示 VIP 角标；原时长位置改为显示文件大小（如 3.2MB，sizeBytes<=0 或缺失时显示「—」），行尾删除按钮保留（用户已确认）。
3. **多选与批量删除**：

- 入口：长按已下载歌曲行进入多选 + 播放栏旁新增「管理」按钮（用户已确认两种都做）。
- 多选态：勾选框行、全选/取消全选（覆盖任务+歌曲）、底部「删除（N）」红色操作条。
- 批量删除语义：**真正删除文件**——连同应用内缓存文件（localPath）一起删除后撤销登记（用户已确认）；确认弹窗文案相应提示「将同时删除已下载的文件」。

## 约束与边界

- 单条删除（行尾删除按钮）保持现有「仅移除记录」语义不变（用户仅确认批量删除为真删文件）。
- 平台限制：系统下载目录文件经 MediaStore 写入，App 无法直接读取/删除（download_registry.dart 注释明确）；「真删文件」实际可删除的是应用内缓存文件（localPath，播放直读的那份），需在弹窗文案与实现注释中如实说明。
- Web 端 localPath 恒为 null，批量删除仅移除登记，需跳过文件删除。
- 现有多选模式（_selectMode）目前只覆盖下载任务，本次需扩展到已下载歌曲。

## 技术方案

**技术栈**：Flutter + flutter_riverpod + 自研样式系统（styles.dart/widgets.dart），无第三方 UI 库；全部改动复用现有模式。

### 实现策略

1. **去卡片背景**：`_buildList`（download_manager_screen.dart L246）去掉 GlassPanel 包裹，改为带水平 padding 的裸 ListView；分区标题、Divider、行结构不动。多选态与非多选态共用此列表。
2. **VIP 角标隐藏**：SongTile（widgets.dart L513）内部在 `song.isVip` 时硬编码渲染 VIP 角标（L606-620）。新增可选参数 `showVip`（默认 true），下载管理页传 false。向后兼容，不影响其他页面。
3. **文件大小显示**：`_songTile` 传 `durationMs: null`（关闭时长显示），trailing 改为 `Row`：大小文本 + 原删除 IconButton。大小格式化新增页内私有帮助函数（>=1MB 显示 `x.x MB`，否则 KB；<=0 显示「—」）；项目内已有同类实现（updater.dart L333-334）可参考但不跨层复用。
4. **多选扩展到歌曲**：

- 选择集 `Set<String> _selectedIds` 改用带前缀的复合 key（`task:<id>` / `song:<songId>`），任务与歌曲统一进全选/计数。
- SongTile 新增 `onLongPress` 参数接入 InkWell（默认 null，零影响）；长按歌曲行 → 进入多选并预选该行。
- 播放栏 `_buildPlayAllBar` 改为 Row：Expanded(全部播放) + 「管理」按钮（OutlinedButton.icon + checklist 图标）。
- 新增 `_songSelectTile`（勾选框 + 封面 + 歌名/歌手），复用现有 `_checkBox`；多选态列表同时渲染任务选择行与歌曲选择行。
- 底部操作条 `_buildSelectActions` 不变，`_confirmBatchDelete` 拆分：task 前缀 → `downloadManagerProvider.removeMany`（会话内记录，无文件）；song 前缀 → 新增 `forgetAndDeleteCache(ids)`。

5. **真删文件**：DownloadRegistryNotifier 新增 `forgetAndDeleteCache(List<int> songIds)`——逐条取 localPath，仿照 PlaybackCacheNotifier._deleteFile（download_registry.dart L337-345）的存在性检查 + try/catch 删除，随后撤销登记并 _persist；删除失败不阻断其余条目（登记照常移除，与现有容错口径一致）。

### 性能与可靠性

- 批量删除为 O(n) 文件 IO + 一次 _persist 落盘，n 为用户勾选数（个位数~几十），无性能瓶颈；同步 existsSync/deleteSync 与 PlaybackCacheNotifier 现有口径一致（数据量小，可接受）。
- 选择集为内存 Set，setState 局部刷新，无额外重建开销。
- 爆炸半径控制：SongTile 仅新增两个可选参数（默认值不变）；registry 仅新增方法不改旧方法；单条删除、播放全部、任务区逻辑不动。

## 目录结构（改动文件）

```
e:/www/kele-music/
├── lib/core/widgets.dart                          # [MODIFY] SongTile 新增 showVip（默认 true）、onLongPress 可选参数并接入 InkWell；其余不动
├── lib/core/download_registry.dart                # [MODIFY] DownloadRegistryNotifier 新增 forgetAndDeleteCache：删缓存文件 + 撤销登记 + 落盘；复用 PlaybackCache 的删文件容错模式
└── lib/features/profile/download_manager_screen.dart  # [MODIFY] 主改动：去 GlassPanel 卡片、行尾大小显示、隐藏 VIP、长按+管理按钮进多选、多选扩展到歌曲、批量删除走 forgetAndDeleteCache、弹窗文案更新
```