import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/styles.dart';
import '../../data/lrc_parser.dart';
import '../../providers.dart';

/// 歌词同步视图（大字排版版）：
/// - 歌词占满可用宽度，长句自动换行（按 TextPainter 预测量动态行高）；
/// - 当前行：accent 色 + 更大字号 + 加粗 + 柔光突出，其余行次级色退后；
/// - 随播放进度平滑滚动居中定位；用户手动滚动后暂停跟随，4 秒恢复；
/// - 点击任意行跳转播放进度；无歌词/加载失败有空态与重试。
class LyricsView extends ConsumerStatefulWidget {
  final AppStyle style;
  final int songId;
  const LyricsView({super.key, required this.style, required this.songId});
  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  // 字号 tokens：当前行 21 加粗发光，其余 17；翻译 12。
  static const double _activeSize = 21;
  static const double _idleSize = 17;
  static const double _transSize = 12;
  // 字距 tokens：渲染与测量必须共用同一组值，否则长句换行数会预测失准。
  static const double _activeTracking = 0.5;
  static const double _idleTracking = 0.2;
  // 行内垂直呼吸空间（上下各 10）。
  static const double _lineGap = 20;

  final ScrollController _sc = ScrollController();
  Timer? _resumeTimer;
  bool _follow = true;
  int _lastIndex = -2; // -2 表示尚未定位过（首次直接跳转不动画）。
  int _positionMs = 0; // 最近一帧的播放进度（仅 debug 日志用）。

  // 行高与行偏移缓存（前缀和），仅换歌/宽度/字体缩放变化时重算。
  List<double>? _heights;
  List<double>? _offsets;
  double? _keyWidth;
  TextScaler? _keyScaler;
  int? _keySong;

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _sc.dispose();
    super.dispose();
  }

  void _onUserScroll() {
    _follow = false;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _follow = true);
    });
    if (mounted) setState(() {});
  }

  /// 用 TextPainter 预测量每行高度（主歌词按当前行字号预留空间，避免
  /// 高亮切换时行高抖动；长句自动换行，占满可用宽度）。
  ///
  /// 测量样式必须与渲染样式逐项一致（字号 / 字重 / 行高 / 字距 / textScaler，
  /// 且不限制行数）：此前测量漏掉渲染用的 letterSpacing、也未带 textScaler，
  /// 长句在渲染时比预测多折一行，行高被低估 → 预计算的行偏移与真实布局错位。
  /// 该差异在 iOS 上更明显（iOS 中文回退字体（PingFang SC）的字宽与 Android
  /// 的回退字体不同，恰好跨过换行临界点的歌词更多），表现为「高亮行没跟着
  /// 进度居中」——属于视觉偏移，不是时间轴不同步。
  void _measure(LyricData data, double contentWidth, TextScaler textScaler) {
    double mainH(String text) => _textHeight(
        text,
        const TextStyle(
            fontSize: _activeSize,
            height: 1.4,
            fontWeight: FontWeight.w700,
            letterSpacing: _activeTracking),
        contentWidth,
        textScaler);
    double transH(String text) => _textHeight(
        text,
        const TextStyle(fontSize: _transSize, height: 1.35),
        contentWidth,
        textScaler);

    final hs = <double>[];
    final offs = <double>[];
    double acc = 0;
    for (final line in data.lines) {
      offs.add(acc);
      final trans = data.transFor(line.time);
      final h = mainH(line.text) + (trans != null ? transH(trans) + 5 : 0) + _lineGap;
      hs.add(h);
      acc += h;
    }
    _heights = hs;
    _offsets = offs;
    _keyWidth = contentWidth;
    _keyScaler = textScaler;
    _keySong = widget.songId;
  }

  /// 与渲染一致地测量文本高度：不限行数（渲染侧同样不限），并按当前系统
  /// 字体缩放测量，否则测量高度会比实际渲染矮。
  double _textHeight(
      String text, TextStyle style, double maxWidth, TextScaler textScaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  void _scrollTo(int index, {required bool animate}) {
    final hs = _heights;
    final offs = _offsets;
    if (hs == null || offs == null || !_sc.hasClients) return;
    if (index < 0 || index >= hs.length) index = 0;
    // 顶部 padding = 视口高一半（见 build），行中心对齐视口中心。
    final topPad = _sc.position.viewportDimension / 2;
    final target =
        (topPad + offs[index] + hs[index] / 2 - _sc.position.viewportDimension / 2)
            .clamp(0.0, _sc.position.maxScrollExtent);
    if (animate) {
      _sc.animateTo(target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    } else {
      _sc.jumpTo(target);
    }
    // 真机对齐排查用（debug 才打印）：可对照「高亮行下标 / 进度毫秒 / 目标
    // 偏移 / 行高 / 视口高」，区分是时间轴不同步（下标与进度对不上）还是
    // 视觉偏移（下标对得上但 offset 与实际渲染行中心有差）。
    if (kDebugMode) {
      debugPrint('[lyrics] pos=${_positionMs}ms idx=$index '
          'offset=${offs[index].toStringAsFixed(1)} '
          'h=${hs[index].toStringAsFixed(1)} '
          'vp=${_sc.position.viewportDimension.toStringAsFixed(1)} '
          'target=${target.toStringAsFixed(1)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final lyricAsync = ref.watch(lyricProvider(widget.songId));
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;

    return lyricAsync.when(
      loading: () => const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Center(
        child: TextButton.icon(
          onPressed: () => ref.invalidate(lyricProvider(widget.songId)),
          icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
          label: const Text('歌词加载失败，点击重试',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return Center(
              child: Text('暂无歌词',
                  style: TextStyle(
                      color: style.textSecondary, fontSize: 14)));
        }
        final index = currentLrcIndex(data.lines, position);
        _positionMs = position.inMilliseconds;
        final textScaler = MediaQuery.textScalerOf(context);
        // 当前行变化时滚动定位；用户手动滚动期间暂停跟随。
        if (index != _lastIndex && _follow) {
          final animate = _lastIndex != -2;
          _lastIndex = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollTo(index < 0 ? 0 : index, animate: animate);
          });
        }
        return NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction == ScrollDirection.idle) return false;
            _onUserScroll();
            return false;
          },
          // 铺满播放容器：左右 24 与页面栅格一致；上下 padding 取视口一半，
          // 保证首行/末行也能滚动到屏幕中央。
          child: LayoutBuilder(builder: (context, constraints) {
            final contentWidth = constraints.maxWidth - 48;
            if (_heights == null ||
                _keyWidth != contentWidth ||
                _keyScaler != textScaler ||
                _keySong != widget.songId) {
              _measure(data, contentWidth, textScaler);
            }
            final heights = _heights!;
            final viewportH = constraints.maxHeight;
            final topPad = viewportH / 2;

            return ListView.builder(
              controller: _sc,
              padding: EdgeInsets.symmetric(vertical: topPad),
              itemCount: data.lines.length,
              itemBuilder: (c, i) {
                final line = data.lines[i];
                final active = i == index;
                final trans = data.transFor(line.time);
                return InkWell(
                  onTap: () {
                    ref.read(audioHandlerProvider).seek(line.time);
                    _follow = true;
                    _lastIndex = -2; // 下一帧直接定位。
                    if (mounted) setState(() {});
                  },
                  child: SizedBox(
                    height: heights[i],
                    child: Padding(
                      // 左右 24 与测量宽度（maxWidth - 48）对应，长句换行不溢出。
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        // 水平居中：歌词在屏幕中左右居中显示。
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 当前行：accent + 大字 + 加粗 + 柔光；其余行退后。
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              color: active
                                  ? style.accent
                                  : style.textSecondary,
                              fontSize: active ? _activeSize : _idleSize,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              height: 1.4,
                              letterSpacing: active
                                  ? _activeTracking
                                  : _idleTracking,
                              shadows: active
                                  ? [
                                      Shadow(
                                          color: style.accent
                                              .withValues(alpha: 0.45),
                                          blurRadius: 18),
                                    ]
                                  : const [],
                            ),
                            child: Text(line.text,
                                textAlign: TextAlign.center),
                          ),
                          if (trans != null)
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 300),
                              style: TextStyle(
                                color: active
                                    ? style.accent.withValues(alpha: 0.85)
                                    : style.textSecondary
                                        .withValues(alpha: 0.7),
                                fontSize: _transSize,
                                height: 1.35,
                              ),
                              child: Text(trans,
                                  textAlign: TextAlign.center),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}
