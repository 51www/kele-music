import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app/app.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 最外层加载 API 配置：登录依赖 baseUrl，必须在任何请求（含登录）之前。
  await AppConfig.load();
  final handler = await initAudioService();
  final api = NcmApi();
  // 音源解析交给 handler（队列自动切歌时使用），handler 不直接依赖 HTTP 层。
  handler.urlResolver = api.songUrl;
  final auth = AuthRepository(api, const FlutterSecureStorage());
  runApp(ProviderScope(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      apiProvider.overrideWithValue(api),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: const MyApp(),
  ));
}
