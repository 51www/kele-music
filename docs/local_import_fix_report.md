# 本地歌单导入修复 / 目录扫描导入 —— 交接记录

记录时间：2026-11-06 18:32（Asia/Shanghai）
工程：`E:\www\kele-music`（Flutter，记录当时的包名 `com.example.kele_music_client`）

> 注：正式包名已统一为 **`com.kelemusic.app`**（Android `applicationId`/`namespace`、iOS/macOS
> `PRODUCT_BUNDLE_IDENTIFIER`），后续不再变更。本文中的旧包名与旧 Kotlin 路径仅作历史记录。

## 1. 装机与当前状态

| 项 | 值 |
| --- | --- |
| 版本 | `1.4.2+2007`，versionCode **2007**（覆盖安装在装包 2006，未卸载、未清数据） |
| 构建 | `flutter build apk --release` 成功（约 57.9 MB），`adb install -r` 覆盖安装成功 |
| 设备 | OPPO PKC110（1080×2376），`adb devices -l` 状态 device |
| 当前 App 状态 | 正常可用。最后一个画面：本地歌单 **TEST2** 详情页（35 首 · 本地音频），可滚动、可播放入口正常 |
| 数据 | 未清空，原有歌单与云端播放记录保留 |

## 2. 问题一：iOS 导入时看不到音频文件

### 真实根因
1. **主因**：`file_picker` 在 iOS 上把 `FileType.audio` 映射为 `MPMediaPickerController`（Apple Music 媒体库）。它只列音乐 App / iTunes 同步的条目，**根本不展示「文件」App、iCloud Drive、「我的 iPhone」**，所以用户看不到任何 mp3。
2. 次要：`ios/Runner/Info.plist` 缺少 `LSSupportsOpeningDocumentsInPlace` / `UIFileSharingEnabled`，导致「文件」App 里看不到本 App 的文档目录，也无法原地打开文档。
3. 选目录场景还需要 security-scoped 访问（`startAccessingSecurityScopedResource()`），否则拿到 URL 也读不到。

### 修法
- iOS 改为 `FileType.custom` + 扩展名白名单（`mp3 / m4a / aac / wav / flac / ogg / opus / aif / aiff`）走 `UIDocumentPickerViewController`，导入模式会把文件复制进 App 沙盒，选中即可读。
- `Info.plist` 补 `LSSupportsOpeningDocumentsInPlace = true`、`UIFileSharingEnabled = true`。
- iOS 目录场景：`UTType.folder` 选择器返回后，Dart 侧 `beginFolderAccess` → 递归遍历 → `endFolderAccess`，访问期间持有 security scope。

改动位置：
- `lib/features/local/local_import_flow.dart`（iOS 分支选择器类型与白名单）
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`（`LocalAudioFolderPlugin`，通道 `kele_music/local_audio_ios`）

## 3. 问题二：Android 选 20 多个只导入 10 个

### 真实根因
`lib/data/models.dart` 的旧 `nextLocalMediaId()` 生成 `-(毫秒时间戳*10 + 自增%10)`，**同一毫秒内最多只有 10 个唯一 id**。批量导入时快速连续生成的 11 个及以后的歌曲 id 与前面撞车，`LocalPlaylistsNotifier.addSongs` 按 id 去重，于是被**静默丢弃**，表现正是「选 20 多个只进 10 个」。不是 `take(10)`，没有硬上限。

### 修法
```dart
int _lastLocalId = 0;
int nextLocalMediaId() {
  final now = -DateTime.now().microsecondsSinceEpoch;
  _lastLocalId = now < _lastLocalId ? now : _lastLocalId - 1;
  return _lastLocalId;
}
```
- 改为微秒级 + 单调递减兜底，任意批量都不会撞 id。
- `addSongs` 返回 `AddSongsResult{added, skippedDuplicate}`，重复项不再静默丢弃，toast 明确写「已跳过 N 个重复」。
- 批量 ≥20 个时先逐个校验（扩展名白名单 + 文件存在 + 非空），期间显示可取消的进度弹窗。

改动位置：`lib/data/models.dart`、`lib/providers.dart`、`lib/features/local/local_import_flow.dart`

## 4. 新功能：扫描目录导入

### 入口（在现有导入入口旁边，未新增一级菜单）
`lib/features/local/local_playlist_detail_screen.dart`：
- 详情页操作条新增文件夹图标按钮（`Icons.create_new_folder_outlined`，tooltip「扫描文件夹导入」），与「播放全部 / 随机 / 批量管理」同排；
- 右上溢出菜单增加「扫描文件夹」弱入口；
- 空歌单空态增加「扫描文件夹」按钮。

### 交互
1. Android 走 SAF `ACTION_OPEN_DOCUMENT_TREE` 选目录；选中后 `takePersistableUriPermission(READ)` 持久化授权。
2. 之后再点同一入口，若已记住目录，弹「从上次的目录导入？」，可选「继续使用（增量导入）/ 重新选择 / 取消」。
3. 导入弹窗：扫描阶段不确定进度（「正在扫描目录… 已发现 N 个音频」），复制阶段确定进度（「已处理 x/y」+ 成功 / 失败计数），底部「取消」。
4. 结果 toast：`已导入 X 首，已跳过 N 个重复，M 个失败`（有取消时前缀改为「已取消，导入 X 首」）。
5. 单文件失败不影响其它；0 字节 / 损坏文件在入库前再校验一次并计入失败。

### 实现要点
- `android/.../MainActivity.kt`：递归 DFS（`DocumentsContract.buildChildDocumentsUriUsingTree`），只收扩展名白名单；在**后台线程**复制到 `filesDir/local_audio/<md5(相对路径|大小)>.<扩展名>`（稳定命名，保证二次导入命中已有文件 → 增量去重）；进度经 `Handler(mainLooper)` 回传；`importRunning` 与 `importCancelled` 控制取消。
- `lib/core/local_audio_folder.dart` + `local_audio_folder_io.dart` + `local_audio_folder_stub.dart`：条件导入隔离 `dart:io`，Web 构建不受影响；iOS/桌面用 `dart:io` 递归遍历。
- `lib/core/constants.dart`：新增 `ncm_local_folder_uri` / `ncm_local_folder_name` 记住上次目录。

## 5. 改动文件清单
- `lib/data/models.dart`
- `lib/providers.dart`
- `lib/core/constants.dart`
- `lib/core/local_audio_folder.dart`（新增）
- `lib/core/local_audio_folder_io.dart`（新增）
- `lib/core/local_audio_folder_stub.dart`（新增）
- `lib/features/local/local_import_flow.dart`（新增）
- `lib/features/local/local_playlist_detail_screen.dart`
- `android/app/src/main/kotlin/com/example/kele_music_client/MainActivity.kt`
- `ios/Runner/Info.plist`、`ios/Runner/AppDelegate.swift`
- `pubspec.yaml`（versionCode 2007）

## 6. 真机验证结果（如实）

| # | 验证项 | 结论 | 证据 / 说明 |
| --- | --- | --- | --- |
| 1 | 多选 20+ 全部入库 | **通过** | 一次选中 25 个文件，TEST2 由 0 → `25 首 · 本地音频`；修复前会被截到 10。截图 `19_test2_25songs.png`（另 `16_after_swipe.png` 为选择器内 25/25 勾选态） |
| 2 | 逐个校验 / 重复计数提示 | **部分通过** | 代码已返回 `skippedDuplicate` 并 toast 提示；本次新增场景无重复，未观察到「已跳过 N 个重复」的真实 toast |
| 3 | 目录扫描：递归 + 只导受支持格式 + 单文件失败计数 | **通过** | 目录含根 2 mp3、`sub1/` 5 mp3、`sub1/nested/` 1 m4a + 1 flac + 1 wav（共 10 有效），另 `broken.mp3`(0B)、`说明.txt`、`cover.jpg`（不支持）。结果 toast「**已导入 10 首，1 个失败**」，列表 25 → `35 首`。证明递归、白名单、0 字节计失败均生效。截图 `21_folder_import_10ok_1fail.png` |
| 4 | 目录扫描进度弹窗 | **未捕获** | 测试目录仅 10 个小文件，导入在 <1 秒内完成，连续截图只抓到完成态 toast。进度弹窗代码存在但**未在真机上被看到** |
| 5 | 导入过程中取消 | **未做** | 同上，导入过快，未构造大目录压测 |
| 6 | 同一目录二次增量导入 → 识别重复 | **未做** | 未执行（设备已收回） |
| 7 | 导入后实际播放 2-3 首 | **未做** | 未来得及点播验证，不能确认「入库即可播放」 |
| 8 | 回归：原单文件导入入口 | **通过（间接）** | 多选入口即原「选择音频文件」入口，本次 25 首即由该入口完成；单选取 1 个未单独测 |
| 9 | 回归：歌单列表结构 / 封面标题 | **未见异常** | 详情页、列表、封面与标题显示正常（`02_library.png`、`19_test2_25songs.png`） |
| 10 | 后台播放恢复（暂停→后台→回前台继续） | **未做** | 未执行，未抓 `_autoHeal` / `_rebuildPlayer` / `reactivateForForeground` 日志 |
| 11 | iOS 端全部行为 | **未验证** | Windows 无法构建/运行 iOS，仅代码级修改与静态检查 |

其他已知事实：
- 全项目 `flutter analyze` 通过（改动后）。
- `17_import_25_success.png` **内容无效**：文件名指向「25 首」，实际截到的是桌面（连续两次返回误退出 App），请以 `19_test2_25songs.png` 为准。
- 构建期间曾有一个后台 Gradle 任务与前台并发导致 `jni ... 拒绝访问` 失败，前台构建成功；最终 APK 已在无并发时重新构建并校验 versionCode=2007。

## 7. 截图（绝对路径）
- `E:\www\kele-music\docs\shortscreen\19_test2_25songs.png` —— 多选 25 个全部入库
- `E:\www\kele-music\docs\shortscreen\21_folder_import_10ok_1fail.png` —— 目录扫描结果「已导入 10 首，1 个失败」，列表 35 首
- `E:\www\kele-music\docs\shortscreen\20_folder_picker.png` —— SAF「选择文件夹」入口
- `E:\www\kele-music\docs\shortscreen\16_after_swipe.png` —— 选择器内 25/25 勾选
- 其余编号截图（01–15、18）为零散过程记录，命名不完全对应内容

## 8. 未完成 / 未验证项
1. 目录扫描的进度弹窗与「取消」未真机验证（需大目录，例如 300+ 文件）。
2. 同目录二次增量导入的重复识别未验证（预期「已导入 0 首，已跳过 10 个重复，1 个失败」）。
3. 新导入的本地歌曲未实际播放验证。
4. 后台播放暂停恢复未验证，无 logcat 佐证。
5. iOS 单文件 / 目录导入、`UTType.folder` 行为未验证。
6. iOS 目录扫描限制：`UIDocumentPicker` 选目录在 iOS 上可拿到 URL，但跨 App 目录只能 security-scoped 访问；本实现为「访问期间递归读取 + 复制进 ApplicationSupport」，不做后台常驻监听。若用户选择 iCloud 上未下载的目录，读取会按需下载并可能较慢；极端情况下受系统授权范围限制（无法访问目录外文件）。

## 9. 设备上的遗留测试数据（仅为测试素材，非 App 数据）
- `/sdcard/Download/kele_multi_test/`（25 个 1 秒 mp3）
- `/sdcard/Download/kele_folder_test/`（10 个有效音频 + broken.mp3 + 说明.txt + cover.jpg）
- `/sdcard/akele_folder_test/`（上一目录的副本，选择器里更容易定位；本次实测用的就是这个）
- App 内歌单 `TEST2` 已含 35 首本地音频，属于验证数据，用户可自行删除歌单。
