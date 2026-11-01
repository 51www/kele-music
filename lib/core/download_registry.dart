import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import 'local_store.dart';

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

  DownloadRegistryNotifier() : super(_load());

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
