import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      routerConfig: router,
      title: 'kele-music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        // 中文字体栈：优先系统字体，避免回退到需联网下载的 Roboto。
        fontFamily: 'Microsoft YaHei',
        fontFamilyFallback: const [
          'PingFang SC',
          'Hiragino Sans GB',
          'Heiti SC',
          'Noto Sans SC',
          'sans-serif',
        ],
      ),
    );
  }
}
