import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app/app.dart';
import 'core/local_store.dart';
import 'data/api_client.dart';
import 'data/app_config.dart';
import 'data/auth_repository.dart';
import 'data/player_repository.dart';
import 'providers.dart';

Future<NcmAudioHandler> initAudioService() => AudioService.init(
      builder: () => NcmAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.netease.client',
        androidNotificationChannelName: 'NetEase Music',
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 同步、即时落盘的本地存储必须在任何读写的 notifier / AppConfig 之前就绪。
  await LocalStore.init();
  // 最外层加载 API 配置：登录依赖 baseUrl，必须在任何请求（含登录）之前。
  await AppConfig.load();
  final handler = await initAudioService();
  final api = NcmApi();
  // 音源解析交给 handler（队列自动切歌时使用），handler 不直接依赖 HTTP 层。
  // 档位读 playbackSettings 的当前 state：设置页改音质后下一次解析立即生效。
  final playbackSettings = PlaybackSettingsNotifier();
  handler.urlResolver = (id) =>
      api.songUrl(id, level: playbackSettings.currentPlayLevel());
  final auth = AuthRepository(api, const FlutterSecureStorage());
  runApp(ProviderScope(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      apiProvider.overrideWithValue(api),
      authRepositoryProvider.overrideWithValue(auth),
      playbackSettingsProvider.overrideWith((ref) => playbackSettings),
    ],
    child: const MyApp(),
  ));
}

void main() {
  // 全局兜底：release 包里任何漏网的未捕获异步异常（插件回调、stream
  // 错误等）不再直接杀死进程，仅记录日志。播放错误已在 audio handler
  // 的 stream onError 与切歌容错层处理，这里是最后一道防线。
  runZonedGuarded(() {
    _bootstrap().catchError((Object e, StackTrace st) {
      debugPrint('bootstrap failed: $e\n$st');
    });
  }, (Object e, StackTrace st) {
    debugPrint('uncaught zone error: $e\n$st');
  });
}
