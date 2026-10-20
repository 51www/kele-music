import 'package:flutter/material.dart';

/// 封面呈现方式，决定 NowPlaying 的版式（对应 ui-styles.json 的 layout.albumPresentation）。
enum AlbumPresentation { vinyl, card, blurred }

/// 一套可切换的主题风格（设计 tokens）。
/// 除原有字段外，新增玻璃面板体系：surface / surfaceBorder / uiRadius，
/// 供列表卡、板块容器、迷你播放条等统一使用，保证三套风格下视觉一致。
class AppStyle {
  final String id;
  final String name;
  final Color bgTop;
  final Color bgBottom;
  final Color textPrimary;
  final Color textSecondary;

  /// 强调色：进度条 / 激活态 / 收藏红心 / 主按钮。
  final Color accent;

  /// 玻璃面板底色（半透明黑/白），叠加在背景渐变上形成层次。
  final Color surface;

  /// 玻璃面板描边（1px hairline），增强边缘可辨识度。
  final Color surfaceBorder;

  /// UI 卡片圆角（区别于专辑封面的 cardRadius）。
  final double uiRadius;
  final Color metal;
  final double titleSize;
  final FontWeight titleWeight;
  final double letterSpacing;
  final double cardRadius;
  final AlbumPresentation albumPresentation;
  final bool grain;
  final bool vignette;
  final bool blur;

  const AppStyle({
    required this.id,
    required this.name,
    required this.bgTop,
    required this.bgBottom,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.surface,
    required this.surfaceBorder,
    required this.uiRadius,
    required this.metal,
    required this.titleSize,
    required this.titleWeight,
    required this.letterSpacing,
    required this.cardRadius,
    required this.albumPresentation,
    required this.grain,
    required this.vignette,
    required this.blur,
  });

  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgTop, bgBottom],
      );

  /// 半透明遮罩（Hero 卡压暗图片用）。
  LinearGradient get scrim => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.55)],
      );
}

/// 三套风格，与 docs/ui-styles.json 保持一致（id 相同，便于后续从 JSON 动态加载）。
const List<AppStyle> kStyles = <AppStyle>[
  AppStyle(
    id: 'vinyl-sunset',
    name: '暖调黑胶复古',
    bgTop: Color(0xFFC4643A),
    bgBottom: Color(0xFF2A1A14),
    textPrimary: Color(0xFFF5EDE6),
    textSecondary: Color(0x99F5EDE6),
    // 原强调色 B85C3A 与橙棕背景几乎同色（激活态不可辨），调整为琥珀金。
    accent: Color(0xFFFFC873),
    surface: Color(0x2E000000),
    surfaceBorder: Color(0x1FFFFFFF),
    uiRadius: 14,
    metal: Color(0xFFD8D2C8),
    titleSize: 20,
    titleWeight: FontWeight.w500,
    letterSpacing: 0.4,
    cardRadius: 0,
    albumPresentation: AlbumPresentation.vinyl,
    grain: true,
    vignette: true,
    blur: false,
  ),
  AppStyle(
    id: 'bold-olive',
    name: '极简专辑卡·橄榄绿',
    bgTop: Color(0xFF3A4423),
    bgBottom: Color(0xFF2C341A),
    textPrimary: Color(0xFFF2F2EC),
    textSecondary: Color(0xFF9AA37E),
    accent: Color(0xFFE8D44D),
    surface: Color(0x24FFFFFF),
    surfaceBorder: Color(0x2EFFFFFF),
    uiRadius: 12,
    metal: Color(0xFF9AA37E),
    titleSize: 22,
    titleWeight: FontWeight.w600,
    letterSpacing: 0,
    cardRadius: 12,
    albumPresentation: AlbumPresentation.card,
    grain: false,
    vignette: false,
    blur: false,
  ),
  AppStyle(
    id: 'soft-teal',
    name: '柔焦梦幻青',
    bgTop: Color(0xFF2E6E6A),
    bgBottom: Color(0xFF6FA8A0),
    textPrimary: Color(0xFFEAF4F2),
    textSecondary: Color(0xB3EAF4F2),
    accent: Color(0xFFFFFFFF),
    surface: Color(0x2BFFFFFF),
    surfaceBorder: Color(0x3DFFFFFF),
    uiRadius: 18,
    metal: Color(0xFFEAF4F2),
    titleSize: 26,
    titleWeight: FontWeight.w400,
    letterSpacing: 0.6,
    cardRadius: 0,
    albumPresentation: AlbumPresentation.blurred,
    grain: false,
    vignette: false,
    blur: true,
  ),
];
