// 目录扫描导入的平台实现（IO 平台：Android / iOS / Windows / macOS / Linux）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'local_audio_folder.dart';

LocalFolderImporter createLocalFolderImporter() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _AndroidFolderImporter();
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return _DartFolderImporter(ios: true);
  }
  return _DartFolderImporter(ios: false);
}

Future<LocalAudioFileInfo?> inspectLocalAudioFile(String path) async {
  if (!isSupportedLocalAudio(path)) return null;
  try {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
    return LocalAudioFileInfo(path);
  } catch (_) {
    return null;
  }
}

int _intOf(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

String _lastSegment(String path) {
  final parts =
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

String _relativePath(String path, String root) {
  var rel = path;
  if (path.length > root.length) rel = path.substring(root.length);
  return rel.replaceFirst(RegExp(r'^[\\/]+'), '');
}

Future<Directory> _localAudioDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}local_audio');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Android：SAF 授权目录的递归扫描与复制全部在原生后台线程完成。
/// content:// 树无法用 dart:io 读取，因此这里只做通道编排。
class _AndroidFolderImporter implements LocalFolderImporter {
  static const MethodChannel _channel = MethodChannel('kele_music/local_audio');

  @override
  bool get supported => true;

  @override
  Future<FolderHandle?> pickFolder() async {
    try {
      final map =
          await _channel.invokeMapMethod<String, dynamic>('pickDirectory');
      if (map == null) return null;
      final uri = map['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      final rawName = map['name'] as String?;
      return FolderHandle(
        id: uri,
        name: (rawName != null && rawName.isNotEmpty) ? rawName : '所选文件夹',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw LocalFolderImportException(e.message ?? '无法打开目录选择器');
    }
  }

  @override
  Future<FolderImportOutcome> importFolder(
    FolderHandle handle, {
    required void Function(FolderImportProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    // 原生通道在后台线程回传进度事件；注意通道只有一个 handler，
    // 导入结束后必须清空，否则会影响其它调用方。
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = call.arguments;
      if (args is! Map) return;
      onProgress(FolderImportProgress(
        phase: (args['phase'] as String?) ?? 'importing',
        processed: _intOf(args['processed']),
        total: _intOf(args['total'], fallback: -1),
        success: _intOf(args['success']),
        failed: _intOf(args['failed']),
      ));
    });
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'importDirectory',
        {
          'treeUri': handle.id,
          'extensions': kLocalAudioExtensions,
        },
      );
      if (map == null) {
        throw const LocalFolderImportException('目录读取失败');
      }
      final rawFiles = (map['files'] as List?) ?? const [];
      final files = <LocalAudioEntry>[];
      for (final item in rawFiles) {
        if (item is! Map) continue;
        final path = item['path'] as String?;
        if (path == null || path.isEmpty) continue;
        final name = (item['name'] as String?) ?? _lastSegment(path);
        files.add(LocalAudioEntry(
          path: path,
          displayName: name,
          relativePath: (item['relativePath'] as String?) ?? name,
        ));
      }
      return FolderImportOutcome(
        files: files,
        total: _intOf(map['total'], fallback: files.length),
        failed: _intOf(map['failed']),
        cancelled: (map['cancelled'] as bool?) ?? false,
      );
    } on PlatformException catch (e) {
      throw LocalFolderImportException(e.message ?? '目录读取失败');
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  @override
  void cancel() {
    unawaited(
      _channel.invokeMethod<void>('cancelImport').catchError((Object _) {}),
    );
  }
}

/// iOS / 桌面：系统目录选择器拿到真实路径后，用 dart:io 遍历。
/// iOS 的 security-scoped 访问由原生侧开启，复制进沙盒后路径才长期可播放；
/// 桌面直接引用原文件路径，不额外占磁盘。
class _DartFolderImporter implements LocalFolderImporter {
  _DartFolderImporter({required this.ios});

  final bool ios;
  static const MethodChannel _iosChannel =
      MethodChannel('kele_music/local_audio_ios');

  bool _cancelled = false;

  @override
  bool get supported => true;

  @override
  Future<FolderHandle?> pickFolder() async {
    _cancelled = false;
    if (ios) {
      try {
        final map =
            await _iosChannel.invokeMapMethod<String, dynamic>('pickFolder');
        if (map == null) return null;
        final path = map['path'] as String?;
        if (path == null || path.isEmpty) return null;
        final name = map['name'] as String?;
        return FolderHandle(
          id: path,
          name: (name != null && name.isNotEmpty) ? name : _lastSegment(path),
        );
      } on MissingPluginException {
        // 原生通道缺失时回退：目录选择器 + security-scoped 授权。
        final path = await FilePicker.platform.getDirectoryPath();
        if (path == null || path.isEmpty) return null;
        await _iosChannel
            .invokeMethod<void>('beginFolderAccess', {'path': path});
        return FolderHandle(id: path, name: _lastSegment(path));
      } on PlatformException catch (e) {
        throw LocalFolderImportException(e.message ?? '无法打开目录选择器');
      }
    }
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return null;
    return FolderHandle(id: path, name: _lastSegment(path));
  }

  @override
  Future<FolderImportOutcome> importFolder(
    FolderHandle handle, {
    required void Function(FolderImportProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    _cancelled = false;
    if (ios) {
      final ok = await _iosChannel.invokeMethod<bool>(
            'beginFolderAccess',
            {'path': handle.id},
          ) ??
          false;
      if (!ok) {
        throw const LocalFolderImportException('目录访问权限已失效，请重新选择目录');
      }
    }
    try {
      final root = Directory(handle.id);
      if (!await root.exists()) {
        throw const LocalFolderImportException('目录不存在或不可访问');
      }
      // 1) 先扫描出全部候选：扫描阶段被取消时不会有文件被复制。
      final candidates = <_Candidate>[];
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (_cancelled) break;
        if (entity is! File) continue;
        if (!isSupportedLocalAudio(entity.path)) continue;
        candidates.add(_Candidate(
          path: entity.path,
          displayName: entity.path.split(RegExp(r'[\\/]')).last,
          relativePath: _relativePath(entity.path, handle.id),
        ));
        if (candidates.length % 50 == 0) {
          onProgress(FolderImportProgress(
            phase: 'scanning',
            processed: candidates.length,
            total: -1,
            success: 0,
            failed: 0,
          ));
        }
      }
      if (_cancelled) {
        return const FolderImportOutcome(
            files: [], total: 0, failed: 0, cancelled: true);
      }
      // 2) 逐个复制（iOS）/ 登记（桌面），单个失败不影响其它。
      final destDir = ios ? await _localAudioDir() : null;
      final files = <LocalAudioEntry>[];
      var failed = 0;
      for (var i = 0; i < candidates.length; i++) {
        if (_cancelled) break;
        final c = candidates[i];
        try {
          var playablePath = c.path;
          final ext = localAudioExtension(c.path);
          if (destDir != null) {
            final size = await File(c.path).length();
            // 稳定命名：同一「相对路径 + 大小」永远落到同一个文件，
            // 重复扫描同一目录时按 url 去重即可命中，实现增量导入。
            final name =
                '${md5.convert(utf8.encode('${c.relativePath}|$size'))}.$ext';
            final dest = File('${destDir.path}${Platform.pathSeparator}$name');
            if (!await dest.exists() || await dest.length() != size) {
              await File(c.path).copy(dest.path);
            }
            playablePath = dest.path;
          }
          files.add(LocalAudioEntry(
            path: playablePath,
            displayName: c.displayName,
            relativePath: c.relativePath,
          ));
        } catch (_) {
          failed++;
        }
        onProgress(FolderImportProgress(
          phase: 'importing',
          processed: i + 1,
          total: candidates.length,
          success: files.length,
          failed: failed,
        ));
      }
      return FolderImportOutcome(
        files: files,
        total: candidates.length,
        failed: failed,
        cancelled: _cancelled,
      );
    } finally {
      if (ios) {
        unawaited(_iosChannel
            .invokeMethod<void>('endFolderAccess')
            .catchError((Object _) {}));
      }
    }
  }

  @override
  void cancel() => _cancelled = true;
}

class _Candidate {
  final String path;
  final String displayName;
  final String relativePath;
  const _Candidate({
    required this.path,
    required this.displayName,
    required this.relativePath,
  });
}
