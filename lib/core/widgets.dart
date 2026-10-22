import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../providers.dart';
import 'styles.dart';

/// 占位封面图（AI 生成），图片缺失/加载失败/解码失败时统一兜底。
const String kPlaceholderCover = 'assets/images/placeholder_cover.png';

/// 带占位与错误兜底的网络图片：
/// 加载中显示淡色底，失败（含 ImageDecoder 格式识别失败等）时回退到本地占位图。
///
/// 协议策略（关键，决定真机封面能否显示）：
/// 平台图床 p*.music.126.net 的 https 在部分 Android 网络出口会被反爬 403，
/// 而原始 http 明文反而可正常加载（Android 侧 Manifest 已开 usesCleartextTraffic）。
/// 因此对 music.126.net 域名**优先用 http**，失败再回退 https；
/// 其余域名优先 https，失败回退 http。两种方向都只回退一次（用 _triedAlt 防死循环）。
class SafeNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  late String _url = _normalize(widget.url);
  bool _triedAlt = false;

  /// 把 URL 规整为首选协议：music.126.net 优先 http，其余优先 https。
  static String _normalize(String url) {
    var u = url;
    if (u.startsWith('//')) u = 'https:$u';
    final host = Uri.tryParse(u)?.host ?? '';
    final preferHttp = host.contains('music.126.net');
    if (preferHttp) {
      u = u.replaceFirst('https://', 'http://');
    } else {
      u = u.replaceFirst('http://', 'https://');
    }
    return u;
  }

  /// 切换到另一种协议重试一次。
  static String _alternate(String u) => u.startsWith('https://')
      ? u.replaceFirst('https://', 'http://')
      : u.replaceFirst('http://', 'https://');

  @override
  void didUpdateWidget(covariant SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final u = _normalize(widget.url);
    if (u != _url) {
      _url = u;
      _triedAlt = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _url;
    if (u.isEmpty) {
      return Image.asset(kPlaceholderCover,
          width: widget.width, height: widget.height, fit: widget.fit);
    }
    return Image.network(
      u,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // 图床会拒绝缺少浏览器 UA 的请求（返回 403），而浏览器能显示。
      // 这里伪装成桌面 Chrome，避免 Flutter 默认 UA 被反爬拦截——这是
      // 「web 能显示、真机空白」的关键根因之一。
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://music.163.com/',
      },
      loadingBuilder: (c, child, chunk) {
        final expected = chunk?.expectedTotalBytes;
        if (expected == null || chunk!.cumulativeBytesLoaded >= expected) {
          return child;
        }
        // 加载中：默认封面垫底 + 转圈，避免露出深色空块。
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(kPlaceholderCover,
                width: widget.width, height: widget.height, fit: widget.fit),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
      errorBuilder: (c, error, stackTrace) {
        // 排查入口：logcat 过滤 SafeNetworkImage 可见具体失败原因（release 也打）。
        debugPrint('[SafeNetworkImage] load failed: $u -> $error');
        // 仅回退一次：切换 http/https 再试；已试过则显示占位图，避免死循环。
        if (!_triedAlt) {
          _triedAlt = true;
          final alt = _alternate(u);
          scheduleMicrotask(() {
            if (mounted) setState(() => _url = alt);
          });
        }
        return Image.asset(kPlaceholderCover,
            width: widget.width, height: widget.height, fit: widget.fit);
      },
    );
  }
}

/// 安全封面图：url 为空或加载失败时显示占位图，避免 Image.network('') 抛异常。
class CoverImage extends StatelessWidget {
  final String url;
  final double size;
  final BorderRadiusGeometry? radius;
  const CoverImage(
      {super.key, required this.url, required this.size, this.radius});

  @override
  Widget build(BuildContext context) {
    final child = SafeNetworkImage(url: url, width: size, height: size);
    final r = radius;
    if (r != null) return ClipRRect(borderRadius: r, child: child);
    return child;
  }
}

/// 玻璃面板：三套风格统一的半透明卡片容器。
class GlassPanel extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? radius;
  final Color? color;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? style.surface,
        borderRadius: radius ?? BorderRadius.circular(style.uiRadius),
        border: Border.all(color: style.surfaceBorder, width: 1),
      ),
      child: child,
    );
  }
}

/// 板块标题：左侧竖条 + 标题，右侧可选动作。
///
/// 标题行高度固定为 24（与竖条 18 居中对齐），保证所有板块的标题基线一致；
/// 标题与板块内容的间距由 [bottomSpacing] 统一承担，默认为当前断点的
/// `AppSpacing.block`，调用方无需再手写 SizedBox，避免各区块节奏走样。
class SectionHeader extends ConsumerWidget {
  final String title;
  final Widget? action;

  /// 标题与下方内容的间距；null = 跟随断点的 `AppSpacing.block`。
  final double? bottomSpacing;
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.bottomSpacing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing ?? sp.block),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: style.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(title,
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (action != null)
              // 动作按钮统一压到标题行高度内，否则会撑高标题行、破坏板块节奏。
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 24),
                child: action!,
              ),
          ],
        ),
      ),
    );
  }
}

/// 栏目板块容器：全应用组织「板块」的唯一入口。
///
/// 板块上边距（`AppSpacing.section`）**由板块自己承担**，而不是父级 ListView
/// 里插 SizedBox。这一点是节奏统一的关键：某个板块因游客态 / 空数据缺席时，
/// 父级插入的空档会残留下来，导致相邻两处的留白一宽一窄。
///
/// [title] 为 null 时只提供上边距，用于 Hero 卡、快捷入口这类无标题板块；
/// 需要自定义标题样式时，直接用 `Padding(padding: sp.sectionPadding, ...)`。
class AppSection extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  const AppSection({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final sp = AppSpacing.of(context);
    return Padding(
      padding: sp.sectionPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) SectionHeader(title: title!, action: action),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 横向滚动条：统一「可鼠标拖拽 + 隐藏滚动条 + 相邻项间距 = `AppSpacing.inline`」。
///
/// [height] 必须显式给定并与子项真实高度一致，否则容器下方会留下一条死白，
/// 视觉上就等于「这一处的板块间距比别处宽」。
class AppHorizontalStrip extends StatelessWidget {
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  const AppHorizontalStrip({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final sp = AppSpacing.of(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
        scrollbars: false,
      ),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: padding,
          itemCount: itemCount,
          separatorBuilder: (_, __) => SizedBox(width: sp.inline),
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

/// 宽屏内容列封顶 + 居中：屏宽超过 [AppSpacing.maxContentWidth] 后不再把内容
/// 拉成一整行（行长过长不易阅读），改为居中一列、两侧自然留白。
/// 配合 `AppSpacing` 的断点分档，构成宽屏下的间距策略。
class AppContentColumn extends StatelessWidget {
  final Widget child;
  const AppContentColumn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 用 Align + heightFactor=1 而不是 Center：本组件同时用在 Scaffold 的
    // bottomNavigationBar（高度无界）里，Center 会把它撑满、把 body 挤成 0 高；
    // heightFactor 让自身高度恒等于子组件高度，在有界/无界两种上下文都稳定。
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: child,
      ),
    );
  }
}

/// 统一空态：图标 + 标题 + 引导文案。
class EmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String hint;
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.hint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 56, color: style.textSecondary.withValues(alpha: 0.7)),
          SizedBox(height: sp.block),
          Text(title, style: TextStyle(color: style.textPrimary, fontSize: 15)),
          SizedBox(height: sp.micro),
          Text(hint,
              style: TextStyle(color: style.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 歌曲行：封面 + 名称/歌手 + VIP 标 + 当前播放高亮（均衡器动效图标）。
/// 全应用（搜索结果 / 歌单详情 / 收藏 / 队列）共用，保证「正在播」识别一致。
/// 可选能力：序号（榜单排序语义，前三名 accent 高亮）、封面与序号同显、
/// 专辑名副行、右侧时长（等宽数字防跳动）。
class SongTile extends ConsumerWidget {
  final Song song;
  final int? index; // 显示序号（歌单/榜单场景），null 则显示封面。
  final bool showCover; // 序号与封面同显（搜索结果场景）。
  final bool showAlbum; // 副行追加「 · 专辑名」。
  final int? durationMs; // 行尾显示时长（mm:ss）。
  final VoidCallback? onTap;
  final Widget? trailing;
  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.showCover = false,
    this.showAlbum = false,
    this.durationMs,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final q = ref.watch(queueProvider).valueOrNull;
    final isCurrent = q != null &&
        q.index >= 0 &&
        q.index < q.songs.length &&
        q.songs[q.index].id == song.id;
    final ps = ref.watch(playbackStateProvider).valueOrNull;
    final playing = ps?.playing ?? false;

    // 序号语义：搜索结果是相关性排序，前三名用 accent 强调排名信息。
    final topRank = index != null && index! <= 3;
    final Widget? indexWidget = index == null
        ? null
        : SizedBox(
            width: 26,
            child: isCurrent
                ? _EqBars(color: style.accent, animate: playing)
                : Text(
                    '${index! > 99 ? '99+' : index!.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: topRank
                            ? style.accent
                            : style.textSecondary.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        fontWeight: topRank ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()])),
          );

    final Widget? coverWidget = !showCover
        ? (index == null
            ? CoverImage(
                url: song.coverUrl,
                size: 44,
                radius: BorderRadius.circular(style.uiRadius / 2))
            : null)
        : CoverImage(
            url: song.coverUrl,
            size: 44,
            radius: BorderRadius.circular(style.uiRadius / 2));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(style.uiRadius / 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.micro, vertical: AppSpacing.micro),
        child: Row(
          children: [
            if (indexWidget != null) indexWidget,
            if (coverWidget != null) ...[
              if (indexWidget != null) SizedBox(width: sp.inline),
              coverWidget,
            ],
            SizedBox(width: sp.inline),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isCurrent ? style.accent : style.textPrimary,
                          fontSize: 14.5,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w400)),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      if (song.isVip)
                        Container(
                          margin: const EdgeInsets.only(right: AppSpacing.xxs),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: style.accent, width: 0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('VIP',
                              style: TextStyle(
                                  color: style.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      Expanded(
                        child: Text(
                            showAlbum && song.album.name.isNotEmpty
                                ? '${song.artistName} · ${song.album.name}'
                                : song.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (durationMs != null) ...[
              SizedBox(width: sp.inline),
              Text(fmtDurationMs(durationMs!),
                  style: TextStyle(
                      color: style.textSecondary.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 时长格式化：毫秒 → mm:ss。
String fmtDurationMs(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 「正在播放」均衡器小动效（三根竖条随节拍起伏）。
class _EqBars extends StatefulWidget {
  final Color color;
  final bool animate;
  const _EqBars({required this.color, required this.animate});

  @override
  State<_EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<_EqBars> with TickerProviderStateMixin {
  late final List<AnimationController> _cs;
  final List<double> _heights = [12, 7, 10];

  @override
  void initState() {
    super.initState();
    _cs = List.generate(3, (i) {
      final c = AnimationController(
          vsync: this, duration: Duration(milliseconds: 420 + i * 130));
      if (widget.animate) c.repeat(reverse: true);
      return c;
    });
  }

  @override
  void didUpdateWidget(covariant _EqBars old) {
    super.didUpdateWidget(old);
    for (final c in _cs) {
      widget.animate ? c.repeat(reverse: true) : c.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in _cs) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(_cs),
      builder: (c, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final t = widget.animate ? _cs[i].value : 1.0;
          final h = _heights[i] * (0.45 + 0.55 * t);
          return Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 歌单封面卡：封面（右下角播放量角标）+ 两行名称。
///
/// 卡高 = 封面 [size] + 封面与名称间距 5 + 两行名称 33 = 168（size=130 时），
/// 横向列表容器按此高度设定，避免固定容器高度在卡片下方留出死白。
class PlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final double size;
  final VoidCallback? onTap;
  const PlaylistCard(
      {super.key, required this.playlist, this.size = 130, this.onTap});

  /// 封面与名称之间的间距（`AppSpacing.micro`，卡内微间距）。
  static const double coverGap = AppSpacing.micro;

  /// 两行名称的固定高度（保证一排卡片底边对齐）。
  static const double titleBlockHeight = 33;

  /// size=130 时的卡片总高度，供横向列表容器对齐使用。
  static double cardHeight(double size) => size + coverGap + titleBlockHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(
                    url: playlist.coverImgUrl,
                    size: size,
                    radius: BorderRadius.circular(style.uiRadius)),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow,
                            size: 10, color: Colors.white),
                        Text(fmtCount(playlist.playCount),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: coverGap),
            SizedBox(
              height: titleBlockHeight,
              width: size,
              child: Text(playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: style.textPrimary, fontSize: 12.5, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放量格式化：亿 / 万。
String fmtCount(int n) {
  if (n >= 100000000) {
    final v = (n / 100000000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}亿';
  }
  if (n >= 10000) {
    final v = (n / 10000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}万';
  }
  return '$n';
}

/// 播放模式图标。
IconData playModeIcon(PlayMode m) {
  switch (m) {
    case PlayMode.sequential:
      return Icons.playlist_play; // 顺序播放
    case PlayMode.loop:
      return Icons.repeat;
    case PlayMode.repeatOne:
      return Icons.repeat_one;
    case PlayMode.shuffle:
      return Icons.shuffle;
  }
}

/// 播放模式文案。
String playModeLabel(PlayMode m) {
  switch (m) {
    case PlayMode.sequential:
      return '顺序播放';
    case PlayMode.loop:
      return '列表循环';
    case PlayMode.repeatOne:
      return '单曲循环';
    case PlayMode.shuffle:
      return '随机播放';
  }
}
