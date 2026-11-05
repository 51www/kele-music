import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 13+ 通知权限（POST_NOTIFICATIONS）检查与引导。
///
/// audio_service 的后台播放依赖一条可见的媒体通知。通知权限被拒后，
/// ColorOS 等激进后台管控会把「没有可见通知的前台服务」当成普通后台进程
/// 冻结，长时间挂起后回前台就会出现「点播放没反应」。启动时请求一次，
/// 回前台发现被拒时提示用户去系统设置开启（每个进程只提示一次）。
class NotificationPermission {
  NotificationPermission._();

  static const MethodChannel _channel =
      MethodChannel('kele_music/notifications');
  static bool _guidanceShown = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 当前是否已获得通知权限（非 Android 平台恒为 true）。
  static Future<bool> isEnabled() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? true;
    } catch (e) {
      debugPrint('[notify] isEnabled failed: $e');
      return true;
    }
  }

  /// Android 13+ 请求通知权限（系统弹窗）；其余情况为 no-op。
  static Future<void> requestIfNeeded() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('request');
    } catch (e) {
      debugPrint('[notify] request failed: $e');
    }
  }

  /// 回前台检查：权限被拒时通过 [guide] 回传一次引导文案。
  static Future<void> guideIfDisabled(
      void Function(String message) guide) async {
    if (!_isAndroid || _guidanceShown) return;
    if (await isEnabled()) return;
    _guidanceShown = true;
    guide('通知权限未开启，后台播放可能被系统中断；请在系统设置中允许通知');
  }
}
