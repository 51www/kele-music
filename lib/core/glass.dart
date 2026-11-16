import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'styles.dart';

/// 贴边浮层只画哪几条 hairline。传了 [AMGlassEdge] 就自动用直角圆角，
/// 避免 `BoxDecoration` 在非均匀 Border 上配 borderRadius 触发断言。
enum AMGlassEdge { top, bottom, left, right }

/// 全应用毛玻璃浮层的唯一实现。
///
/// 组件只声明「类型 + 状态」，所有取值来自 [AMTokens]：
/// sigma 20/12/24、tint alpha 0.66~0.78（滚动 +0.10、hover +0.06）、
/// 0.5pt hairline、极轻投影。这样 60 多处浮层不会各写一套数值。
///
/// 三种状态过渡：
/// - **滚动**：外部把 [intensity]（0..1）传进来，底色 / 描边 / 阴影由
///   [AnimatedContainer] 平滑「加厚」，正文滑过浮层下方时仍清晰；
/// - **hover**：桌面指针进入时再抬一档（[hoverEnabled]），触屏不触发；
/// - **出现**：[animateAppearance] 让弹层淡入 + 0.97→1 轻微放大。
/// 三者都走 `AMTokens.glassDuration / glassAppearDuration`，
/// 系统「减少动态效果」时统一退化为瞬时。
///
/// **降级**：[AMTokens.glassBlurEnabled] 为 false（编译开关或系统高对比度）
/// 时不创建 [BackdropFilter]，底色改为完全不透明、描边提到 1pt 并略加强，
/// 文字色不变 —— 对比度只会更高，不会出现「半透明底 + 无模糊」的塌陷。
class AMGlass extends StatefulWidget {
  final AMGlassKind kind;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// 与 Container.constraints 同义：限制整个面板的宽高（弹层常用 maxHeight）。
  final BoxConstraints? constraints;
  final BorderRadius? borderRadius;
  final Set<AMGlassEdge>? edges;
  final Color? tint;

  /// 滚动强度 0..1，由 AppShell 的滚动监听提供。
  final double intensity;

  /// 桌面卡片 / 侧栏行开启；触屏或贴边条保持 false。
  final bool hoverEnabled;

  /// 弹层出现动效；贴边导航条不用，避免每帧重绘模糊层。
  final bool animateAppearance;

  final bool showShadow;

  const AMGlass({
    super.key,
    required this.kind,
    required this.child,
    this.padding,
    this.margin,
    this.constraints,
    this.borderRadius,
    this.edges,
    this.tint,
    this.intensity = 0,
    this.hoverEnabled = false,
    this.animateAppearance = false,
    this.showShadow = true,
  });

  @override
  State<AMGlass> createState() => _AMGlassState();
}

class _AMGlassState extends State<AMGlass> {
  bool _hover = false;

  BorderRadius get _radius {
    if (widget.borderRadius != null) return widget.borderRadius!;
    // 非均匀 Border 只能配直角，否则 BoxDecoration 会断言。
    if (widget.edges != null && widget.edges!.isNotEmpty) {
      return BorderRadius.zero;
    }
    return switch (widget.kind) {
      AMGlassKind.bar => BorderRadius.zero,
      AMGlassKind.sheet =>
        const BorderRadius.all(Radius.circular(AMTokens.radiusSheet)),
      _ => const BorderRadius.all(Radius.circular(AMTokens.radiusPanel)),
    };
  }

  Border _border(Brightness b, double boost, double width) {
    final side =
        BorderSide(color: AMTokens.glassBorder(b, boost: boost), width: width);
    final edges = widget.edges;
    if (edges == null || edges.isEmpty) {
      return Border.all(color: side.color, width: side.width);
    }
    return Border(
      top: edges.contains(AMGlassEdge.top) ? side : BorderSide.none,
      bottom: edges.contains(AMGlassEdge.bottom) ? side : BorderSide.none,
      left: edges.contains(AMGlassEdge.left) ? side : BorderSide.none,
      right: edges.contains(AMGlassEdge.right) ? side : BorderSide.none,
    );
  }

  /// constraints 包在 padding 外层，与 Container 的语义一致。
  Widget _inner() {
    Widget inner = widget.child;
    if (widget.padding != null) {
      inner = Padding(padding: widget.padding!, child: inner);
    }
    if (widget.constraints != null) {
      inner = ConstrainedBox(constraints: widget.constraints!, child: inner);
    }
    return inner;
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final blurEnabled = AMTokens.glassBlurEnabled(context);
    final hovering = _hover && widget.hoverEnabled;
    final intensity = widget.intensity.clamp(0.0, 1.0);

    final alpha = AMTokens.glassAlpha(
      widget.kind,
      blurEnabled: blurEnabled,
      intensity: intensity,
      hover: hovering,
    );
    final boost = intensity * AMTokens.glassBorderBoost +
        (hovering ? AMTokens.glassBorderBoost : 0) +
        (blurEnabled ? 0 : AMTokens.glassBorderBoost);
    final borderWidth = blurEnabled
        ? AMTokens.glassBorderWidth
        : AMTokens.glassFallbackBorderWidth;
    // 贴边条不投影：它和窗口边缘齐平，投影只会变成脏边。
    final shadows = widget.showShadow && widget.kind != AMGlassKind.bar
        ? AMTokens.glassShadows(b, hover: hovering)
        : const <BoxShadow>[];

    Widget panel = AnimatedContainer(
      duration: AMTokens.glassDuration(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: (widget.tint ?? AMTokens.glassTint(b)).withValues(alpha: alpha),
        borderRadius: _radius,
        border: _border(b, boost, borderWidth),
        boxShadow: shadows,
      ),
      child: _inner(),
    );

    panel = ClipRRect(
      borderRadius: _radius,
      child: blurEnabled
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: AMTokens.glassBlur(widget.kind),
                sigmaY: AMTokens.glassBlur(widget.kind),
              ),
              child: panel,
            )
          : panel,
    );

    if (widget.animateAppearance) {
      panel = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AMTokens.glassAppearDuration(context),
        curve: Curves.easeOutCubic,
        builder: (c, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
        ),
        child: panel,
      );
    }

    if (widget.margin != null) {
      panel = Padding(padding: widget.margin!, child: panel);
    }

    if (!widget.hoverEnabled) return panel;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: panel,
    );
  }
}
