import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

/// Apple Music 视觉改版后的语义令牌（唯一色彩 / 圆角 / 材质 / 动效真源）。
///
/// 所有颜色成对定义（light / dark），组件只经 [kStyles] 或本类取值；
/// 不再有随皮肤漂移的彩色渐变、胶片颗粒、暗角与拟物纹理。
/// 对齐 `docs/apple-music-style-prompts.md` §12。
class AMTokens {
  const AMTokens._();

  // ── 浅色 ──────────────────────────────────────────
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightGrouped = Color(0xFFF5F5F7);
  static const Color lightElevated = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xB8FFFFFF); // 0.72
  static const Color lightText = Color(0xFF1D1D1F);
  static const Color lightTextSecondary = Color(0xFF6E6E73);
  static const Color lightTextTertiary = Color(0xFF8E8E93);
  static const Color lightSeparator = Color(0x2E3C3C43); // 0.18
  static const Color lightHairline = Color(0x143C3C43); // 0.08
  static const Color lightFill = Color(0x14747480); // 0.08
  static const Color lightSelected = Color(0x1AFA243C); // 0.10
  static const Color lightAccent = Color(0xFFFF2D2D);

  // ── 深色 ──────────────────────────────────────────
  static const Color darkBg = Color(0xFF000000);
  static const Color darkGrouped = Color(0xFF1C1C1E);
  static const Color darkElevated = Color(0xFF2C2C2E);
  static const Color darkSurface = Color(0xAD2C2C2E); // 0.68
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0x99EBEBF5); // 0.60
  static const Color darkTextTertiary = Color(0x4DEBEBF5); // 0.30
  static const Color darkSeparator = Color(0x99545458); // 0.60
  static const Color darkHairline = Color(0x1AFFFFFF); // 0.10
  static const Color darkFill = Color(0x3D767680); // 0.24
  static const Color darkSelected = Color(0x29FC3C44); // 0.16
  static const Color darkAccent = Color(0xFFFF2D2D);

  static bool _isDark(Brightness b) => b == Brightness.dark;

  static Color bg(Brightness b) => _isDark(b) ? darkBg : lightBg;
  static Color grouped(Brightness b) => _isDark(b) ? darkGrouped : lightGrouped;
  static Color elevated(Brightness b) =>
      _isDark(b) ? darkElevated : lightElevated;
  // 浅色下用不透明浅灰分组底，面板叠在纯白主底上才有层次。
  static Color surface(Brightness b) => _isDark(b) ? darkSurface : lightGrouped;
  static Color text(Brightness b) => _isDark(b) ? darkText : lightText;
  static Color textSecondary(Brightness b) =>
      _isDark(b) ? darkTextSecondary : lightTextSecondary;
  static Color textTertiary(Brightness b) =>
      _isDark(b) ? darkTextTertiary : lightTextTertiary;
  static Color separator(Brightness b) =>
      _isDark(b) ? darkSeparator : lightSeparator;
  static Color hairline(Brightness b) =>
      _isDark(b) ? darkHairline : lightHairline;
  static Color fill(Brightness b) => _isDark(b) ? darkFill : lightFill;
  static Color selected(Brightness b) =>
      _isDark(b) ? darkSelected : lightSelected;
  static Color accent(Brightness b) => _isDark(b) ? darkAccent : lightAccent;

  // ── 圆角阶梯（固定，不随主题变化）──────────────────
  static const double radiusArt = 8;
  static const double radiusThumb = 4;
  static const double radiusHero = 12;
  static const double radiusPanel = 12;
  static const double radiusSheet = 20;
  static const double radiusPill = 999;
  static const double radiusLine = 2;

  // ── 材质 / 动效 ────────────────────────────────────
  // 毛玻璃令牌（唯一取值真源，见 AGENT.md「毛玻璃材质」）。
  // 模糊半径按浮层职责分档：贴边条 20 / 列表卡片 12 / 弹层 24，
  // 静态封面氛围层 40（ImageFiltered，不参与浮层合成）。
  static const double glassBarBlur = 20;
  static const double glassCardBlur = 12;
  static const double glassSheetBlur = 24;
  static const double glassBackdropBlur = 40;

  /// 半透明底色：叠在模糊后的背景上。浅色用略灰的白，与纯白主底形成
  /// 可辨识的明度差；深色用中性深灰。二者都是中性色，不引入新色相。
  static const Color lightGlassTint = Color(0xFFF5F5F7);
  static const Color darkGlassTint = Color(0xFF2C2C2E);

  /// 静止状态各档 tint 不透明度。取 0.66~0.78 是为保证文字对比度：
  /// 最坏情况下叠在相反纯色背景上，浅色底约 #F9F9FA、深色底约 #5B5B5D，
  /// 主文字 #1D1D1F / #FFFFFF 对比度分别约 16:1 / 6.5:1，均高于 4.5:1。
  static const double glassBarAlpha = 0.72;
  static const double glassCardAlpha = 0.66;
  static const double glassSheetAlpha = 0.78;

  /// 滚动时「材质加厚」、hover 时再抬一档；合计上限 0.94。
  static const double glassScrollAlphaBoost = 0.10;
  static const double glassHoverAlphaBoost = 0.06;
  static const double glassAlphaCeiling = 0.94;

  /// 不支持背景模糊时退化为完全不透明：没有模糊托底，任何透光都会让
  /// 背后的正文杂字穿透浮层（实测 0.96 仍可见），可读性优先于层次感。
  static const double glassFallbackAlpha = 1.0;

  /// 0.5pt hairline；降级时提到 1.0pt 并加一点 alpha 补回边界。
  static const double glassBorderWidth = 0.5;
  static const double glassFallbackBorderWidth = 1.0;
  static const double glassBorderBoost = 0.04;

  /// 极轻投影：只把浮层和背景分开，不用文档禁止的重黑大投影。
  static const double glassShadowBlur = 18;
  static const double glassShadowBlurHover = 24;
  static const double glassShadowOffsetY = 6;
  static const double glassShadowAlpha = 0.08;
  static const double glassShadowAlphaHover = 0.12;

  // 旧别名：保留给已有静态氛围层与调用点，取值与新令牌同源。
  static const double barBlur = glassBarBlur;
  static const double sheetBlur = glassSheetBlur;
  static const double backdropBlur = glassBackdropBlur;

  static const int motionMicro = 200;
  static const int motionState = 300;
  static const int motionLyrics = 350;

  // ── 表现力层（Expressive）：结构红 / 超大字阶 / 编排动效 ────────
  /// 结构红：同一枚纯红矩形在四种尺度上编码「当前 / 正在」——
  /// 侧栏当前行、板块标题竖块、播放条已播段、标签栏指示条。
  /// 不用作渐变、光晕或装饰；明暗主题共用，保证双平面高对比。
  static const Color signal = Color(0xFFFF2D2D);
  static const Color signalOn = Color(0xFFFFFFFF);
  static const double signalBar = 6;
  static const double signalIndicator = 3;

  /// 超大字阶：张力来自系统无衬线的字重与负字距，不引入新字体依赖。
  static const double displayXL = 56;
  static const double displayL = 44;
  static const double sectionL = 28;
  static const double trackingTight = -2.0;
  static const double trackingSection = -0.8;

  static const int motionPage = 380;
  static const int motionReveal = 420;
  static const int motionPop = 180;
  static const int motionStagger = 60;

  /// 尊重系统「减少动态效果」：所有编排动画统一从这里取时长。
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  static Duration pageDuration(BuildContext context) => reduceMotion(context)
      ? Duration.zero
      : const Duration(milliseconds: motionPage);

  static Duration revealDuration(BuildContext context) => reduceMotion(context)
      ? Duration.zero
      : const Duration(milliseconds: motionReveal);

  // ── 毛玻璃派生值 ────────────────────────────────────
  /// 编译期开关：Web HTML renderer / 低端设备构建时用
  /// `--dart-define=AM_GLASS_BLUR=false` 整体降级为不透明材质。
  static const bool glassBlurCompileEnabled =
      bool.fromEnvironment('AM_GLASS_BLUR', defaultValue: true);

  /// 是否启用背景模糊。系统高对比度模式下也降级：文字清晰度优先于层次感。
  /// 降级时 [glassAlpha] 会把底色提到 [glassFallbackAlpha]，文字色不变，
  /// 因此对比度只会更高，不会出现「半透明底 + 无模糊」导致的可读性塌陷。
  static bool glassBlurEnabled(BuildContext context) =>
      glassBlurCompileEnabled && !MediaQuery.of(context).highContrast;

  static Color glassTint(Brightness b) =>
      _isDark(b) ? darkGlassTint : lightGlassTint;

  static double glassBlur(AMGlassKind kind) => switch (kind) {
        AMGlassKind.bar => glassBarBlur,
        AMGlassKind.card => glassCardBlur,
        AMGlassKind.panel => glassCardBlur,
        AMGlassKind.sheet => glassSheetBlur,
      };

  static double glassAlpha(
    AMGlassKind kind, {
    required bool blurEnabled,
    required double intensity,
    required bool hover,
  }) {
    if (!blurEnabled) return glassFallbackAlpha;
    final base = switch (kind) {
      AMGlassKind.bar => glassBarAlpha,
      AMGlassKind.card => glassCardAlpha,
      AMGlassKind.panel => glassCardAlpha,
      AMGlassKind.sheet => glassSheetAlpha,
    };
    return (base +
            glassScrollAlphaBoost * intensity.clamp(0.0, 1.0) +
            (hover ? glassHoverAlphaBoost : 0.0))
        .clamp(0.0, glassAlphaCeiling);
  }

  /// hairline 描边色；[boost] 由滚动 / hover / 降级叠加。
  static Color glassBorder(Brightness b, {double boost = 0}) {
    final alpha = ((_isDark(b) ? 0.10 : 0.08) + boost).clamp(0.0, 1.0);
    return (_isDark(b) ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C43))
        .withValues(alpha: alpha);
  }

  static List<BoxShadow> glassShadows(
    Brightness b, {
    bool hover = false,
    bool flat = false,
  }) {
    if (flat) return const <BoxShadow>[];
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF000000).withValues(
            alpha: hover ? glassShadowAlphaHover : glassShadowAlpha),
        blurRadius: hover ? glassShadowBlurHover : glassShadowBlur,
        offset: const Offset(0, glassShadowOffsetY),
      ),
    ];
  }

  /// hover / 滚动导致底色、描边、阴影变化时的过渡时长。
  static Duration glassDuration(BuildContext context) => reduceMotion(context)
      ? Duration.zero
      : const Duration(milliseconds: motionMicro);

  /// 弹层出现（淡入 + 轻微放大）的时长；reduceMotion 下瞬时。
  static Duration glassAppearDuration(BuildContext context) =>
      reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: motionState);
}

/// 毛玻璃浮层类型：决定模糊半径、底色透明度、圆角与阴影尺度。
/// bar = 贴边导航/播放条（直角、单边 hairline、无投影）；
/// card / panel = 列表与内容卡片（12pt 圆角、可 hover）；
/// sheet = 弹层（20pt 圆角、最不透明、轻投影）。
enum AMGlassKind { bar, card, panel, sheet }

/// 全局间距体系：4pt 基准刻度 + 语义角色 + 断点档。
///
/// ## 用法（唯一来源，业务代码禁止裸写数字）
/// 1. **语义层** `section` / `block` / `inline` / `micro` / `gutter`：日常只写
///    这一层，同名即同距，跨页面天然一致（间距走样基本都是因为有人直接写了
///    10 / 14 / 22 这类随手数字）。
/// 2. **刻度层** `xxs`~`xxxl`：只由语义层引用，需要整体调整节奏时改这里，一处生效。
/// 3. **响应式** `AppSpacing.of`：按屏宽断点整体上调一档（见 `AppSpacingMetrics`），
///    窄屏回落基准档。**任何断点下角色之间的比例关系恒定**，因此「相邻板块的间隔」
///    在不同屏幕上永远出自同一套数值体系，而不是各页面各写各的。
///
/// ## 响应式分档（数值均取自刻度层）
/// | 角色 | 含义 | 紧凑 <600 | 中等 600~1024 | 宽松 >=1024 |
/// |---|---|---|---|---|
/// | `gutter` | 页面左右留白 | 16 | 24 | 32 |
/// | `section` | **栏目板块之间的垂直间距** | 20 | 24 | 24 |
/// | `block` | 板块标题↔内容、同层紧密堆叠 | 12 | 16 | 16 |
/// | `inline` | 同一行/同一流相邻元素（卡片之间、图标↔文字、网格间距） | 8 | 12 | 12 |
/// | `micro` | 元素内部微间距（文字行间、角标内边距） | 4 | 4 | 4 |
class AppSpacing {
  const AppSpacing._();

  // ── 断点 ─────────────────────────────────────────
  /// 紧凑 -> 中等 的分界（典型为手机 / 小平板）。
  static const double mediumFrom = 600;

  /// 中等 -> 宽松 的分界（典型为平板 / 桌面宽屏）。
  static const double expandedFrom = 1024;

  /// 宽松档的内容列最大宽度：超出的屏宽不再把内容拉成一整行（行长不可读），
  /// 改为居中一列、两侧自然留白。与 `gutter` 一起构成宽屏的间距策略。
  static const double maxContentWidth = 720;

  // ── 刻度层（4 的倍数）────────────────────────────
  /// 2：极小微间距（同一文字块内的行间距）。
  static const double xxs = 2;

  /// 4：元素内部微间距。
  static const double xs = 4;

  /// 8：卡片内元素间距、竖条与标题间距。
  static const double sm = 8;

  /// 12：板块标题与该板块内容之间的间距。
  static const double md = 12;

  /// 16：紧凑档的页面左右留白、卡片内边距。
  static const double lg = 16;

  /// 20：紧凑档的板块与板块之间的间距。
  static const double xl = 20;

  /// 24：中等档的页面留白与板块间距。
  static const double xxl = 24;

  /// 32：宽松档的页面左右留白。
  static const double xxxl = 32;

  // ── 语义层（= 紧凑档取值）────────────────────────
  /// 页面左右留白。
  static const double gutter = lg;

  /// **栏目板块之间的垂直间距**，全应用唯一来源。
  ///
  /// 由板块自身承担（见 `AppSection`），不要在父级列表里插 SizedBox——
  /// 否则某个板块因游客态 / 空数据缺席时空档会残留，留白就一宽一窄。
  static const double section = xl;

  /// 板块标题与该板块内容的间距；也用于同层紧密堆叠（页面大标题↔首个板块）。
  static const double block = md;

  /// 同一行 / 同一流内相邻元素：横向卡片之间、图标与文字、网格单元格间距。
  static const double inline = sm;

  /// 元素内部微间距：文字行与行、角标内边距。
  static const double micro = xs;

  /// 解析当前断点档的间距。
  static AppSpacingMetrics of(BuildContext context) =>
      AppSpacingMetrics.forWidth(MediaQuery.sizeOf(context).width);
}

/// 断点档。
enum AppBreakpoint { compact, medium, expanded }

/// 某一断点档下的间距取值，以及由它们派生的常用内边距 / 网格度量。
///
/// 宽屏只加宽「页面级」间距（留白 / 板块间距 / 卡内间距），[micro] 这类元素
/// 内部微间距各档保持一致——否则宽屏下整页会被吹散、卡片显得空。
class AppSpacingMetrics {
  final AppBreakpoint breakpoint;

  /// 页面左右留白。
  final double gutter;

  /// 栏目板块之间的垂直间距。
  final double section;

  /// 板块标题↔内容、同层紧密堆叠。
  final double block;

  /// 同一行 / 同一流相邻元素（卡片之间、图标↔文字、网格间距）。
  final double inline;

  /// 元素内部微间距。
  final double micro;

  const AppSpacingMetrics({
    required this.breakpoint,
    required this.gutter,
    required this.section,
    required this.block,
    required this.inline,
    required this.micro,
  });

  /// 紧凑档（手机竖屏）：全部基准值。
  static const AppSpacingMetrics compact = AppSpacingMetrics(
    breakpoint: AppBreakpoint.compact,
    gutter: AppSpacing.lg, // 16
    section: AppSpacing.xl, // 20
    block: AppSpacing.md, // 12
    inline: AppSpacing.sm, // 8
    micro: AppSpacing.xs, // 4
  );

  /// 中等档（>=600）：页面留白与板块间距各上调一档，元素内部间距不变。
  static const AppSpacingMetrics medium = AppSpacingMetrics(
    breakpoint: AppBreakpoint.medium,
    gutter: AppSpacing.xxl, // 24
    section: AppSpacing.xxl, // 24
    block: AppSpacing.lg, // 16
    inline: AppSpacing.md, // 12
    micro: AppSpacing.xs, // 4
  );

  /// 宽松档（>=1024）：内容列居中封顶，左右留白继续放宽。
  static const AppSpacingMetrics expanded = AppSpacingMetrics(
    breakpoint: AppBreakpoint.expanded,
    gutter: AppSpacing.xxxl, // 32
    section: AppSpacing.xxl, // 24
    block: AppSpacing.lg, // 16
    inline: AppSpacing.md, // 12
    micro: AppSpacing.xs, // 4
  );

  static AppSpacingMetrics forWidth(double width) {
    if (width >= AppSpacing.expandedFrom) return expanded;
    if (width >= AppSpacing.mediumFrom) return medium;
    return compact;
  }

  bool get isCompact => breakpoint == AppBreakpoint.compact;
  bool get isMedium => breakpoint == AppBreakpoint.medium;
  bool get isExpanded => breakpoint == AppBreakpoint.expanded;

  /// 页面左右留白（给 Column 这类非滚动内容用）。
  EdgeInsets get pagePadding => EdgeInsets.symmetric(horizontal: gutter);

  /// 纵向滚动列表的首尾内边距：顶部 [block] 跟紧上一块，底部 [section] 留呼吸。
  EdgeInsets get listPadding =>
      EdgeInsets.fromLTRB(gutter, block, gutter, section);

  /// 同 [listPadding]，但左右留白已由页面级 [pagePadding] 承担（滚动视图嵌在
  /// 已留白的容器里）——避免左右被加两次。
  EdgeInsets get scrollPadding => EdgeInsets.only(top: block, bottom: section);

  /// 板块自身的上边距。**由板块自己承担**，缺席时不残留空档。
  EdgeInsets get sectionPadding => EdgeInsets.only(top: section);

  /// 网格列数：按可用宽度与最小卡片边长推出，卡片尽量填满列宽——
  /// 既不在右侧留下残余空档，也不会把卡片撑得过大。全应用共用这一套断点，
  /// 同样的内容在不同页面排成同样的列数。桌面（宽松档）放宽到 6 列，
  /// 利用宽屏横向空间。
  int gridColumns(double width, {double minCard = 150, int maxColumns = 6}) {
    var n = 1;
    for (var i = 2; i <= maxColumns; i++) {
      if ((width - inline * (i - 1)) / i >= minCard) n = i;
    }
    return n;
  }

  /// 与 [gridColumns] 配套的方形封面边长（正好填满列宽，右侧不剩空档）。
  double gridCardSize(double width, int columns) =>
      (width - inline * (columns - 1)) / columns;
}

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

  /// Hero 卡底部压暗：仅用于保证白字可读，不做全图重压暗。
  LinearGradient get scrim => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0x59000000)], // 0 → 0.35
      );
}

/// Apple Music 风格的三档明暗选择（与设置页「主题风格」三个选项一一对应）。
///
/// 三项沿用原有 `styleIndexProvider` 的 0/1/2 索引与持久化键，交互完全不变：
/// 0 = 跟随系统亮度，1 = 浅色，2 = 深色。三者共用同一套 Apple Music 令牌，
/// 仅亮度不同，不再存在三套互不相干的彩色皮肤。
List<AppStyle> get kStyles => <AppStyle>[
      _amStyle('apple-music', '跟随系统',
          PlatformDispatcher.instance.platformBrightness),
      _amStyle('apple-music-light', '浅色', Brightness.light),
      _amStyle('apple-music-dark', '深色', Brightness.dark),
    ];

/// 用同一套令牌构造主题：背景为恒定中性纯色（bgTop == bgBottom），
/// 强调色固定为品牌红，圆角与字号全主题一致。
AppStyle _amStyle(String id, String name, Brightness brightness) => AppStyle(
      id: id,
      name: name,
      bgTop: AMTokens.bg(brightness),
      bgBottom: AMTokens.bg(brightness),
      textPrimary: AMTokens.text(brightness),
      textSecondary: AMTokens.textSecondary(brightness),
      accent: AMTokens.accent(brightness),
      surface: AMTokens.surface(brightness),
      surfaceBorder: AMTokens.hairline(brightness),
      uiRadius: AMTokens.radiusPanel,
      metal: AMTokens.textTertiary(brightness),
      titleSize: 22,
      titleWeight: FontWeight.w700,
      letterSpacing: -0.2,
      cardRadius: AMTokens.radiusArt,
      albumPresentation: AlbumPresentation.card,
      grain: false,
      vignette: false,
      blur: false,
    );
