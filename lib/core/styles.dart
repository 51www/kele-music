import 'package:flutter/material.dart';

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
  /// 同样的内容在不同页面排成同样的列数。
  int gridColumns(double width, {double minCard = 130, int maxColumns = 4}) {
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

  /// 半透明遮罩（Hero 卡压暗图片用）。
  LinearGradient get scrim => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.55)
        ],
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
