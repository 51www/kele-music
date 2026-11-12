import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/styles.dart';
import '../providers.dart';
import 'router.dart';

/// 系统字体栈：SF Pro（西文）+ 苹方（中文），缺失时逐级回退。
const List<String> _kFontFallback = <String>[
  'SF Pro Display',
  'PingFang SC',
  'Hiragino Sans GB',
  'Heiti SC',
  'Noto Sans SC',
  'sans-serif',
];

ThemeData _amTheme(Brightness brightness) {
  final bg = AMTokens.bg(brightness);
  final text = AMTokens.text(brightness);
  final accent = AMTokens.accent(brightness);
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: bg,
    useMaterial3: true,
    fontFamily: 'SF Pro Text',
    fontFamilyFallback: _kFontFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      surface: bg,
      onSurface: text,
    ),
    iconTheme: IconThemeData(color: text, size: 24),
    dividerColor: AMTokens.separator(brightness),
    hintColor: AMTokens.textTertiary(brightness),
    // 按压反馈改为极淡中性底，去掉 Material 高饱和水波纹。
    highlightColor: Colors.transparent,
    splashColor: AMTokens.fill(brightness),
    canvasColor: bg,
    cardColor: AMTokens.elevated(brightness),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // 沿用原 styleIndexProvider 的 0/1/2 索引与持久化值，仅把「三套皮肤」
    // 映射为 Apple Music 的「跟随系统 / 浅色 / 深色」三档明暗。
    final styleIdx = ref.watch(styleIndexProvider);
    final themeMode = switch (styleIdx) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      routerConfig: router,
      title: 'kele-music',
      debugShowCheckedModeBanner: false,
      theme: _amTheme(Brightness.light),
      darkTheme: _amTheme(Brightness.dark),
      themeMode: themeMode,
    );
  }
}
