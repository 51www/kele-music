import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update_verify.dart';

/// GitHub Releases 检查更新 + Android 应用内下载安装。
///
/// 发布链路：推送 `v*` tag → `.github/workflows/release.yml` 构建各平台产物并
/// 上传到 GitHub Release（产物命名 `kele-music-<tag>-android-universal.apk` 等）。
/// 本模块只读取 `releases/latest`（GitHub 已排除草稿与预发布），比对版本号后
/// 选取 Android APK 产物下载。更新永不强制：是否下载由用户在设置页点击决定。
const String kUpdateRepo = '51www/kele-music';
const String kUpdateApiLatest =
    'https://api.github.com/repos/$kUpdateRepo/releases/latest';
const String kUpdateReleasesPage = 'https://github.com/$kUpdateRepo/releases';

/// 国内镜像加速：直连 GitHub 资源 CDN（objects.githubusercontent.com）常超时，
/// 下载与检查接口按「国内镜像 → GitHub 官方」逐级回退，镜像全挂仍能官方直连。
/// 每个镜像用法为 `<镜像前缀>/<完整 GitHub URL>`。
/// 可用 `--dart-define=UPDATE_MIRROR=https://your.mirror/` 追加自有镜像
/// （逗号分隔，排在默认镜像之前，优先尝试）。
const List<String> kUpdateMirrorBases = [
  'https://gh-proxy.com/',
  'https://gh.ddlc.top/',
  'https://ghfast.top/',
];

const String _extraMirrors = String.fromEnvironment('UPDATE_MIRROR');

/// 归一化后的镜像前缀列表（保证以 `/` 结尾）。
List<String> get _mirrorBases {
  final extra = <String>[];
  for (final raw in _extraMirrors.split(',')) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    extra.add(s.endsWith('/') ? s : '$s/');
  }
  return [...extra, ...kUpdateMirrorBases];
}

/// APK 等资源的下载候选地址：镜像在前，官方地址兜底。
List<String> downloadUrlCandidates(String url) =>
    [...[for (final m in _mirrorBases) '$m$url'], url];

/// 检查更新接口的候选地址：官方 api.github.com 优先（直连通常可用、且数据最权威），
/// 失败再逐个尝试镜像（`<镜像>/https://api.github.com/...`）。
List<String> apiUrlCandidates() =>
    [kUpdateApiLatest, ...[for (final m in _mirrorBases) '$m$kUpdateApiLatest']];

/// 平台通道：与 MainActivity 的 `kele_music/updater` 对应。
/// 职责：拉起系统安装器 / 查询与跳转「安装未知应用」授权。
const MethodChannel _updaterChannel = MethodChannel('kele_music/updater');

/// 是否支持应用内「下载 APK + 拉起安装」：仅 Android（Web / 桌面 / iOS 不可用）。
bool get supportsInAppInstall =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Release 中的一个产物文件。
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size; // 字节，0 表示未知。
  final String? sha256; // GitHub 提供的 digest（`sha256:<hex>`），用于校验下载完整性。
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });
}

/// `releases/latest` 的关键字段（只解析本功能用到的部分）。
class ReleaseInfo {
  final String tagName; // 形如 v1.0.2
  final String name; // 发布标题
  final String body; // 更新说明（Markdown 原文）
  final String htmlUrl; // Release 页面
  final String publishedAt; // ISO8601
  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  /// 去掉前缀 v 后的展示版本号，如 `1.0.2`。
  String get version => normalizeVersion(tagName);
}

Dio _client() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {
        // GitHub API 强制要求 User-Agent，缺失会直接 403。
        'User-Agent': 'kele-music-client',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ));

/// 拉取最新正式 Release：官方 api.github.com 优先，失败按 [apiUrlCandidates] 走镜像回退。
/// 404（仓库确无 Release）不换源直接抛出；网络异常抛 [DioException]，最终统一经
/// [friendlyUpdateError] 翻译成中文提示。
Future<ReleaseInfo> fetchLatestRelease() async {
  Object? last;
  final urls = apiUrlCandidates();
  for (var i = 0; i < urls.length; i++) {
    try {
      final resp = await _client().get<dynamic>(urls[i]);
      final data = resp.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('GitHub 返回格式异常');
      }
      return parseRelease(data);
    } on DioException catch (e) {
      last = e;
      // 第一个候选是官方地址：404 = 仓库真的没有 Release，换镜像也是同样结果。
      if (i == 0 && e.response?.statusCode == 404) rethrow;
    } on StateError catch (e) {
      last = e; // 返回格式异常（多为镜像错误页），换下一个源重试。
    }
  }
  throw last ?? StateError('检查更新失败');
}

/// 解析 Release JSON（`releases/latest` 响应体）；公开便于单测与本地缓存复用。
ReleaseInfo parseRelease(Map<String, dynamic> json) {
  final assets = <ReleaseAsset>[];
  final rawAssets = json['assets'];
  if (rawAssets is List) {
    for (final a in rawAssets) {
      if (a is! Map<String, dynamic>) continue;
      assets.add(ReleaseAsset(
        name: (a['name'] ?? '').toString(),
        downloadUrl: (a['browser_download_url'] ?? '').toString(),
        size: (a['size'] as num?)?.toInt() ?? 0,
        sha256: _sha256OfDigest((a['digest'] ?? '').toString()),
      ));
    }
  }
  return ReleaseInfo(
    tagName: (json['tag_name'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    body: (json['body'] ?? '').toString(),
    htmlUrl: (json['html_url'] ?? kUpdateReleasesPage).toString(),
    publishedAt: (json['published_at'] ?? '').toString(),
    assets: assets,
  );
}

/// GitHub asset 的 `digest` 形如 `sha256:efe6bc…`；非 sha256 或缺失返回 null（跳过校验）。
String? _sha256OfDigest(String digest) {
  final d = digest.trim().toLowerCase();
  return d.startsWith('sha256:') && d.length > 7 ? d.substring(7) : null;
}

/// 版本号归一化：去掉前缀 `v`、预发布/构建后缀（`-beta.1+2`），返回 `1.2.3` 核心段。
String normalizeVersion(String raw) {
  var s = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final cut = s.indexOf(RegExp(r'[-+]'));
  if (cut > 0) s = s.substring(0, cut);
  return s;
}

/// 按数字段比较版本：`1.10.0 > 1.9.9`；位数不足补 0。
/// 返回负数 = a 较旧，0 = 相同，正数 = a 较新。
int compareVersions(String a, String b) {
  final pa = normalizeVersion(a).split('.');
  final pb = normalizeVersion(b).split('.');
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final na = i < pa.length ? (int.tryParse(pa[i]) ?? 0) : 0;
    final nb = i < pb.length ? (int.tryParse(pb[i]) ?? 0) : 0;
    if (na != nb) return na - nb;
  }
  return 0;
}

/// 最新版是否比当前版本新（同版本或更旧都返回 false —— 永不降级提示）。
bool isNewerVersion(String latestTag, String currentVersion) =>
    compareVersions(latestTag, currentVersion) > 0;

/// 为当前设备挑 APK 产物：优先 universal（全 ABI 通用、无需探测设备架构），
/// 其次任意 `-android-*.apk`。明确排除 `.aab`（无法直接安装）。
ReleaseAsset? pickAndroidApk(ReleaseInfo release) {
  final apks = release.assets
      .where((a) => a.name.toLowerCase().endsWith('.apk'))
      .toList();
  if (apks.isEmpty) return null;
  for (final a in apks) {
    if (a.name.contains('-android-universal')) return a;
  }
  final android = apks.where((a) => a.name.contains('-android')).toList();
  return (android.isNotEmpty ? android : apks).first;
}

/// 下载 APK 到应用私有外部存储（`Android/data/<pkg>/files`，无需任何存储权限）。
///
/// 按 [downloadUrlCandidates] 逐级尝试：国内镜像在前、GitHub 官方直连兜底；
/// 用户取消（[cancelToken]）立即终止不换源。[expectedSha256] 非空且能算出哈希时
/// 校验完整性，不匹配视为该来源不可信 → 换下一个来源重下（防镜像篡改 / 截断）。
/// 返回：落盘路径、实际下载来源（用于 UI 展示）、是否完成完整性校验。
Future<({String path, String source, bool verified})> downloadApk(
  String url, {
  String? expectedSha256,
  void Function(int received, int total)? onProgress,
  void Function(String source)? onSource,
  CancelToken? cancelToken,
}) async {
  final dir = await getExternalStorageDirectory() ??
      await getTemporaryDirectory();
  final path = '${dir.path}/kele-music-update.apk';
  Object? last;
  final candidates = downloadUrlCandidates(url);
  for (var i = 0; i < candidates.length; i++) {
    final official = i == candidates.length - 1;
    final source = official ? 'GitHub 官方直连' : Uri.parse(candidates[i]).host;
    onSource?.call(source);
    try {
      await _client().download(
        candidates[i],
        path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
      );
      if (expectedSha256 != null) {
        final actual = await fileSha256(path);
        if (actual != null && actual != expectedSha256.toLowerCase()) {
          last = StateError('SHA-256 校验不匹配（$source）');
          continue; // 内容被改写或被截断：换下一个来源，新下载会覆盖本文件。
        }
        return (path: path, source: source, verified: actual != null);
      }
      return (path: path, source: source, verified: false);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow; // 用户取消：不再换源。
      last = e;
    }
  }
  throw StateError('所有下载源均失败：${friendlyUpdateError(last ?? StateError('网络错误'))}');
}

/// Android 8+ 需要用户单独授予「安装未知应用」；低版本或已授权返回 true。
Future<bool> canRequestInstall() async {
  if (!supportsInAppInstall) return false;
  return await _updaterChannel.invokeMethod<bool>('canRequestInstall') ?? false;
}

/// 跳转系统「安装未知应用」授权页（返回应用后可继续安装）。
Future<void> openInstallPermissionSettings() =>
    _updaterChannel.invokeMethod<void>('openInstallPermission');

/// 拉起系统安装器安装已下载的 APK。
Future<void> installApk(String path) =>
    _updaterChannel.invokeMethod<void>('installApk', {'path': path});

/// 为当前平台挑选最匹配的产物（仅用于弹窗展示与跳转；
/// 应用内自动下载安装只在 Android 上走 [pickAndroidApk]）。
ReleaseAsset? pickPlatformAsset(ReleaseInfo release) {
  if (kIsWeb) {
    for (final a in release.assets) {
      if (a.name.contains('-web.')) return a;
    }
    return null;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return pickAndroidApk(release);
    case TargetPlatform.windows:
      return _firstMatching(release, '-windows-');
    case TargetPlatform.linux:
      return _firstMatching(release, '-linux-');
    case TargetPlatform.macOS:
      return _firstMatching(release, '-macos-');
    default:
      return null;
  }
}

ReleaseAsset? _firstMatching(ReleaseInfo release, String key) {
  for (final a in release.assets) {
    if (a.name.contains(key)) return a;
  }
  return null;
}

/// 把检查更新的异常翻译成用户可读的中文提示。
String friendlyUpdateError(Object e) {
  if (e is StateError) return e.message;
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return '无法连接 GitHub（超时或网络被拦截）';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return '仓库暂未发布任何版本';
        if (code == 403) return 'GitHub 接口触发限流，请稍后再试';
        return 'GitHub 返回异常（$code）';
      default:
        return '网络请求失败';
    }
  }
  if (e is PlatformException) return e.message ?? '系统通道调用失败';
  return '未知错误';
}

/// 供 UI 展示：把 ISO8601 时间转成 `2026-10-30`。
String publishedDate(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 供 UI 展示：字节数转 `12.3 MB`。
String formatSize(int bytes) {
  if (bytes <= 0) return '大小未知';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
