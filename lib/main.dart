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
        androidNotificationChannelId: 'com.example.kele.client',
        androidNotificationChannelName: 'kele-music',
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
  final auth = AuthRepository(api, const FlutterSecureStorage());
  // 自管 ProviderContainer（配合 UncontrolledProviderScope）：
  // - overrides 只放长生命周期对象（handler/api/auth 单例）；
  // - playbackSettings 不 override——urlResolver 每次解析音源时经 container
  //   现读 provider，天然拿到「当前」实例。此前直接持有 notifier 实例，而
  //   设置页 ref.invalidate(playbackSettingsProvider)（保存/恢复 API 地址的
  //   刷新页面 hack）与热重载都会 dispose 并重建该实例，导致共享实例被
  //   dispose 后继续使用，抛 Bad state 并让后续播放全部静默失败。
  final container = ProviderContainer(overrides: [
    audioHandlerProvider.overrideWithValue(handler),
    apiProvider.overrideWithValue(api),
    authRepositoryProvider.overrideWithValue(auth),
  ]);
  // 音源解析交给 handler（队列自动切歌时使用），handler 不直接依赖 HTTP 层。
  // 档位在闭包内现读 playbackSettings：设置页改音质后下一次解析立即生效。
  // 注意 StateNotifierProvider.read 返回 state，取 notifier 需再 .notifier。
  handler.urlResolver = (id) => api.songUrl(
      id,
      level: container.read(playbackSettingsProvider.notifier).currentPlayLevel());
  // 断点续听：先把 cookie 恢复到 api（否则恢复装载 VIP 曲会因无登录态失败），
  // 再读 queueSnapshotProvider 触发「上次播放队列 → 暂停态」的启动恢复。
  // AuthNotifier._init 后续会再 init 一次（幂等），此处仅为恢复时序提前就绪。
  await auth.init();
  container.read(queueSnapshotProvider);
  // 收听统计：启动即常驻（每秒累计 + 定时落盘），不依赖用户是否进过统计页。
  container.read(listenStatsProvider);
  runApp(UncontrolledProviderScope(
    container: container,
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
