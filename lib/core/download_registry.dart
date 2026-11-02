import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import 'local_store.dart';
import 'raw_http.dart';

/// 一条「已下载」登记：下载去重与播放直读本地文件的依据。
///
/// 两份落点各司其职：
/// - 系统下载目录（用户可见，经平台通道 MediaStore 写入，App 无法直接读取）；
/// - 应用内缓存文件（[localPath]，App 可读，供播放直读本地文件用）。
/// Web 平台只登记不落缓存文件（[localPath] 恒为 null，播放仍走网络）。
class DownloadedSong {
  final int songId;
  final String fileName; // 导出到系统下载目录的文件名
  final String? localPath; // 应用内缓存文件绝对路径（Web / 缓存落盘失败为 null）
  final int sizeBytes;
  final String level; // 下载时的音质档位（换档后允许重新下载覆盖）
  final DateTime downloadedAt;

  /// 下载时的完整歌曲信息（供「下载管理」页播放：重构 Song 进播放队列）。
  /// 旧版本登记记录无此字段（null），仅去重可用、不可直接播放。
  final Song? song;

  const DownloadedSong({
    required this.songId,
    required this.fileName,
    required this.level,
    required this.downloadedAt,
    this.localPath,
    this.sizeBytes = 0,
    this.song,
  });

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'fileName': fileName,
        'localPath': localPath,
        'sizeBytes': sizeBytes,
        'level': level,
        'downloadedAt': downloadedAt.toIso8601String(),
        if (song != null) 'song': song!.toJson(),
      };

  factory DownloadedSong.fromJson(Map<String, dynamic> j) => DownloadedSong(
        songId: (j['songId'] ?? 0) as int,
        fileName: (j['fileName'] ?? '').toString(),
        localPath: j['localPath'] as String?,
        sizeBytes: (j['sizeBytes'] ?? 0) as int,
        level: (j['level'] ?? 'standard').toString(),
        downloadedAt:
            DateTime.tryParse((j['downloadedAt'] ?? '').toString()) ??
                DateTime.now(),
        song: j['song'] is Map<String, dynamic>
            ? Song.fromJson(j['song'] as Map<String, dynamic>)
            : null,
      );
}

/// 已下载歌曲登记表：LocalStore 持久化（同步落盘，进程被杀不丢）。
///
/// - 下载前去重：[isDownloaded] 命中即跳过，避免重复下载；
/// - 播放优化：[resolveLocalPath] 命中且缓存文件存在 → 返回本地路径，
///   由 urlResolver 直接返回 file:// 地址，不再请求网络音源接口；
/// - 自愈：登记存在但缓存文件被系统清理/用户删除时，自动撤销登记，
///   回退网络播放（下次下载也会重新落缓存）。
class DownloadRegistryNotifier
    extends StateNotifier<Map<int, DownloadedSong>> {
  static const _storeKey = 'downloaded_songs_v1';
  static const _cacheDirName = 'song_cache';

  DownloadRegistryNotifier() : super(_load()) {
    _backfillSizes();
  }

  /// 旧版本登记记录没有 sizeBytes（当时下载链路未回传字节），从应用内
  /// 缓存文件补 stat 真实大小并持久化；无缓存路径（Web / 落盘失败）的
  /// 记录保持 0，页面显示「—」。
  void _backfillSizes() {
    if (kIsWeb) return;
    var changed = false;
    final next = Map<int, DownloadedSong>.from(state);
    next.forEach((id, r) {
      if (r.sizeBytes > 0) return;
      final path = r.localPath;
      if (path == null || path.isEmpty) return;
      try {
        final f = File(path);
        if (!f.existsSync()) return;
        next[id] = DownloadedSong(
          songId: r.songId,
          fileName: r.fileName,
          localPath: r.localPath,
          sizeBytes: f.lengthSync(),
          level: r.level,
          downloadedAt: r.downloadedAt,
          song: r.song,
        );
        changed = true;
      } catch (_) {
        // 探测异常（权限等）保持原样。
      }
    });
    if (changed) {
      state = next;
      _persist();
    }
  }

  /// 启动时从 LocalStore 读回；缺损坏记录逐条忽略，不阻断启动。
  static Map<int, DownloadedSong> _load() {
    try {
      final raw = LocalStore.instance.getStringList(_storeKey);
      if (raw == null) return const {};
      final map = <int, DownloadedSong>{};
      for (final item in raw) {
        try {
          final s = DownloadedSong.fromJson(
              jsonDecode(item) as Map<String, dynamic>);
          if (s.songId > 0) map[s.songId] = s;
        } catch (_) {
          // 单条损坏忽略。
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  /// 是否已下载。带 [level] 时要求音质档位一致——换档（如 standard→higher）
  /// 允许重新下载并覆盖登记，保证「下载到的就是当前想要的音质」。
  bool isDownloaded(int songId, {String? level}) {
    final hit = state[songId];
    if (hit == null) return false;
    return level == null || hit.level == level;
  }

  /// 可播放的已下载歌曲（登记序 = 下载先后；旧记录缺歌曲信息的不含）。
  List<Song> get playableSongs => [
        for (final r in state.values)
          if (r.song != null) r.song!,
      ];

  /// 返回可用于播放的本地文件路径；登记缺失 / Web / 缓存文件不存在 → null。
  /// 文件丢失时自动撤销登记（自愈），下次下载会重建。
  String? resolveLocalPath(int songId) {
    if (kIsWeb) return null;
    final hit = state[songId];
    final path = hit?.localPath;
    if (path == null || path.isEmpty) return null;
    try {
      if (File(path).existsSync()) return path;
    } catch (_) {
      // 探测异常（权限等）按不存在处理。
    }
    forget(songId);
    return null;
  }

  /// 把下载得到的完整音频字节落一份应用内缓存，返回文件路径（失败返回 null，
  /// 不影响下载结果——系统下载目录照常导出，只是播放暂不走本地）。
  Future<String?> saveCacheFile(
      int songId, String fileName, Uint8List? bytes) async {
    if (kIsWeb || bytes == null || bytes.isEmpty) return null;
    try {
      final dir =
          await getApplicationSupportDirectory();
      final cache = Directory('${dir.path}/$_cacheDirName');
      if (!await cache.exists()) await cache.create(recursive: true);
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '.mp3';
      final file = File('${cache.path}/$songId$ext');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 登记/覆盖一条已下载记录并立即落盘。
  void register(DownloadedSong song) {
    final next = Map<int, DownloadedSong>.from(state);
    next[song.songId] = song;
    state = next;
    _persist();
  }

  /// 撤销登记（缓存文件丢失自愈；不主动删除任何磁盘文件）。
  void forget(int songId) {
    if (!state.containsKey(songId)) return;
    final next = Map<int, DownloadedSong>.from(state)..remove(songId);
    state = next;
    _persist();
  }

  /// 批量撤销登记并删除应用内缓存文件（localPath，播放直读的那份）。
  /// 系统下载目录的文件经 MediaStore 写入、App 无权删除，不在能力范围；
  /// Web / 无缓存路径的记录仅移除登记。单条删除失败不阻断其余条目。
  void forgetAndDeleteCache(List<int> songIds) {
    if (songIds.isEmpty) return;
    final next = Map<int, DownloadedSong>.from(state);
    for (final id in songIds) {
      final hit = next.remove(id);
      if (hit == null) continue;
      _deleteCacheFile(hit.localPath);
    }
    state = next;
    _persist();
  }

  void _deleteCacheFile(String? path) {
    if (kIsWeb || path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 删除失败（权限/占用）忽略，登记已移除即可。
    }
  }

  void _persist() {
    try {
      LocalStore.instance.setStringList(_storeKey, [
        for (final s in state.values) jsonEncode(s.toJson()),
      ]);
    } catch (_) {
      // 持久化失败不影响本次会话的内存态。
    }
  }
}

final downloadRegistryProvider =
    StateNotifierProvider<DownloadRegistryNotifier, Map<int, DownloadedSong>>(
        (ref) => DownloadRegistryNotifier());

/// 一条「播放缓存」登记：透明落盘的音频文件路径与体积/时间（LRU/配额淘汰用）。
/// 与 DownloadedSong 不同——不存 Song 全量信息、不进下载管理页，仅供
/// 冷启动断点续播直读本地文件、跳过缓冲与直链过期。
class PlaybackCacheEntry {
  final int songId;
  final String localPath;
  final int sizeBytes;
  final DateTime cachedAt;

  const PlaybackCacheEntry({
    required this.songId,
    required this.localPath,
    required this.sizeBytes,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'localPath': localPath,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory PlaybackCacheEntry.fromJson(Map<String, dynamic> j) => PlaybackCacheEntry(
        songId: (j['songId'] ?? 0) as int,
        localPath: (j['localPath'] ?? '').toString(),
        sizeBytes: (j['sizeBytes'] ?? 0) as int,
        cachedAt: DateTime.tryParse((j['cachedAt'] ?? '').toString()) ??
            DateTime.now(),
      );
}

/// 透明播放缓存登记表：与「下载管理」完全独立的播放缓存。
///
/// 只在歌曲音源真正加载成功（正常起播 / 断点恢复装载）后，于后台把音频
/// 字节落一份应用内缓存文件，使下次冷启动断点续播能直接 file:// 本地加载、
/// 跳过缓冲等待与网易直链（≈20 分钟）过期。受两道边界约束：
/// - LRU 数量上限（[kMaxEntries]）：只保留最近播放的若干首，更早的自动淘汰；
/// - 硬性磁盘配额（[kMaxBytes]）：总体积超阈值时按最旧优先删除，封顶不膨胀。
/// 落盘目录与下载缓存同策略（应用私有、进程被杀不丢），但独立子目录与 key，
/// 不进下载管理页；并主动跳过已被显式下载的歌曲（复用其缓存，避免重复落盘）。
class PlaybackCacheNotifier
    extends StateNotifier<Map<int, PlaybackCacheEntry>> {
  static const _storeKey = 'playback_cache_v1';
  static const _subDir = 'playback_cache';
  static const int kMaxEntries = 20; // LRU 数量上限
  static const int kMaxBytes = 256 * 1024 * 1024; // 硬性磁盘配额 256MB

  final Ref _ref;
  PlaybackCacheNotifier(this._ref) : super(_load());

  /// 启动时从 LocalStore 读回；缺损坏记录逐条忽略，不阻断启动。
  static Map<int, PlaybackCacheEntry> _load() {
    try {
      final raw = LocalStore.instance.getStringList(_storeKey);
      if (raw == null) return const {};
      final map = <int, PlaybackCacheEntry>{};
      for (final item in raw) {
        try {
          final e = PlaybackCacheEntry.fromJson(
              jsonDecode(item) as Map<String, dynamic>);
          if (e.songId > 0 && e.localPath.isNotEmpty) map[e.songId] = e;
        } catch (_) {
          // 单条损坏忽略。
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  /// 返回可播放的本地缓存路径；文件丢失（被系统清理）时自愈撤销并返回 null。
  String? resolvePlaybackPath(int songId) {
    if (kIsWeb) return null;
    final hit = state[songId];
    if (hit == null) return null;
    try {
      if (File(hit.localPath).existsSync()) return hit.localPath;
    } catch (_) {
      // 探测异常（权限等）按不存在处理。
    }
    forget(songId);
    return null;
  }

  /// 透明缓存一首歌的音频字节（fire-and-forget，失败静默）。
  /// 已缓存 / 已被显式下载 / Web 直接跳过，不重复落盘、不写系统下载目录。
  void cacheSong(Song song, String url) {
    if (kIsWeb) return;
    // 与显式下载去重：下载登记表命中即复用其缓存文件，不另存一份。
    if (_ref.read(downloadRegistryProvider).containsKey(song.id)) return;
    if (state.containsKey(song.id)) return; // 已缓存，跳过
    unawaited(_fetchAndStore(song, url));
  }

  Future<void> _fetchAndStore(Song song, String url) async {
    // 仅对真实网络音源落盘：已走本地文件的（下载/播放缓存命中）url 为 file://，
    // rawHttpGet 会直接返回 null，天然跳过——与上面的去重双保险。
    final bytes = await rawHttpGet(url);
    if (bytes == null || bytes.isEmpty) return;
    final path = await _saveFile(song.id, bytes);
    if (path == null) return;
    final next = Map<int, PlaybackCacheEntry>.from(state);
    next[song.id] = PlaybackCacheEntry(
      songId: song.id,
      localPath: path,
      sizeBytes: bytes.length,
      cachedAt: DateTime.now(),
    );
    state = next;
    _trim();
    _persist();
  }

  Future<String?> _saveFile(int songId, Uint8List bytes) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cache = Directory('${dir.path}/$_subDir');
      if (!await cache.exists()) await cache.create(recursive: true);
      // 与下载缓存同文件名约定（<id>.mp3），但位于独立子目录，互不干扰。
      final file = File('${cache.path}/$songId.mp3');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 同时受数量与配额约束：按 cachedAt 从最旧开始淘汰，直到
  /// 数量 ≤ [kMaxEntries] 且总体积 ≤ [kMaxBytes]。两项各自独立触发。
  void _trim() {
    final next = Map<int, PlaybackCacheEntry>.from(state);
    final byAge = next.values.toList()
      ..sort((a, b) => a.cachedAt.compareTo(b.cachedAt));
    var total = byAge.fold(0, (int s, e) => s + e.sizeBytes);
    for (final e in byAge) {
      if (next.length <= kMaxEntries && total <= kMaxBytes) break;
      _deleteFile(e.localPath);
      next.remove(e.songId);
      total -= e.sizeBytes;
    }
    state = next;
  }

  /// 撤销登记（缓存文件丢失自愈；不主动删除任何磁盘文件）。
  void forget(int songId) {
    if (!state.containsKey(songId)) return;
    final next = Map<int, PlaybackCacheEntry>.from(state)..remove(songId);
    state = next;
    _persist();
  }

  void _deleteFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 删除失败（权限/占用）忽略，登记已移除即可。
    }
  }

  void _persist() {
    try {
      LocalStore.instance.setStringList(_storeKey, [
        for (final e in state.values) jsonEncode(e.toJson()),
      ]);
    } catch (_) {
      // 持久化失败不影响本次会话的内存态。
    }
  }
}

final playbackCacheProvider =
    StateNotifierProvider<PlaybackCacheNotifier, Map<int, PlaybackCacheEntry>>(
        (ref) => PlaybackCacheNotifier(ref));
