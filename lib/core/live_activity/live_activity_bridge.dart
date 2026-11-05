// iOS 灵动岛 / 锁屏实时活动（ActivityKit）的 Dart 桥接层。
//
// 设计原则：
// - 仅 iOS 生效，其它平台（Android / macOS / Windows / Linux / Web）一律静默
//   no-op，绝不因 MissingPluginException 影响播放；
// - 原生侧只有在系统支持（iOS 16.1+）且用户允许实时活动时才返回 true，
//   其余情况由调用方直接放弃，实现「不支持时优雅降级」。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次实时活动快照。字段全部为纯数据，经 StandardMethodCodec 传递。
class LiveActivityPayload {
  final int songId;
  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String lyric;
  final String translation;

  /// 封面原始字节（仅换歌时非空）。原生侧落盘到 App Group 共享容器，
  /// Widget Extension 渲染时从共享目录读取。
  final Uint8List? artworkBytes;

  const LiveActivityPayload({
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.lyric,
    required this.translation,
    this.artworkBytes,
  });

  Map<String, Object?> toMap() => {
        'songId': songId,
        'title': title,
        'artist': artist,
        'album': album,
        'isPlaying': isPlaying,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'lyric': lyric,
        'translation': translation,
        if (artworkBytes != null) 'artworkBytes': artworkBytes,
      };
}

/// 原生实时活动通道。所有异常在边界处吞掉：实时活动属于「锦上添花」，
/// 任何失败都不得影响正常播放。
class LiveActivityBridge {
  LiveActivityBridge._();

  static final LiveActivityBridge instance = LiveActivityBridge._();

  static const MethodChannel _channel =
      MethodChannel('kele_music/live_activity');

  /// 是否运行在 iOS 上。用 defaultTargetPlatform 而不是 dart:io Platform，
  /// 保证 Web 编译不受影响。
  static bool get isPlatformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _supported = false;
  bool get supported => _supported;

  /// 查询系统能力：iOS 16.1+ 且实时活动开关打开时返回 true。
  /// [running] 表示进程重启后仍存在同类型活动（用于接续更新）。
  Future<bool> checkSupported() async {
    if (!isPlatformSupported) return false;
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('isSupported');
      _supported = res?['supported'] == true;
      _hadRunning = res?['running'] == true;
      return _supported;
    } catch (e) {
      debugPrint('[LiveActivity] isSupported failed: $e');
      _supported = false;
      return false;
    }
  }

  bool _hadRunning = false;
  bool get hadRunning => _hadRunning;

  /// 开始或更新实时活动。返回是否成功（失败静默，不影响播放）。
  Future<bool> update(LiveActivityPayload payload) async {
    if (!_supported) return false;
    try {
      await _channel.invokeMethod<void>('update', payload.toMap());
      return true;
    } catch (e) {
      debugPrint('[LiveActivity] update failed: $e');
      return false;
    }
  }

  /// 结束当前实时活动（队列清空 / 没有歌曲时调用）。
  Future<void> end() async {
    if (!isPlatformSupported) return;
    try {
      await _channel.invokeMethod<void>('end');
    } catch (e) {
      debugPrint('[LiveActivity] end failed: $e');
    }
  }
}
