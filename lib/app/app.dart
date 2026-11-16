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
    // 浮层 Theme 兜底：分散在各页面的 AlertDialog / PopupMenu 也统一用
    // 中性半透明底 + 0.5pt hairline + 极轻投影。BackdropFilter 无法进
    // Theme，真正的背景模糊由 AMGlass 与公共弹层提供。
    dialogTheme: DialogThemeData(
      backgroundColor: AMTokens.glassTint(brightness)
          .withValues(alpha: AMTokens.glassSheetAlpha),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AMTokens.radiusSheet),
        side: BorderSide(
            color: AMTokens.glassBorder(brightness),
            width: AMTokens.glassBorderWidth),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      // 手写 SnackBar 的兜底：半透明中性底保证文字可读。
      // buildAppSnackBar 显式设 transparent，由 AMGlass 提供真模糊。
      backgroundColor: AMTokens.glassTint(brightness)
          .withValues(alpha: AMTokens.glassSheetAlpha),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AMTokens.radiusPanel)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AMTokens.glassTint(brightness)
          .withValues(alpha: AMTokens.glassSheetAlpha),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AMTokens.radiusPanel),
        side: BorderSide(
            color: AMTokens.glassBorder(brightness),
            width: AMTokens.glassBorderWidth),
      ),
    ),
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
