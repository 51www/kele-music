import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../data/player_repository.dart';
import '../providers.dart';
import 'styles.dart';

/// 占位封面图（AI 生成），图片缺失/加载失败/解码失败时统一兜底。
const String kPlaceholderCover = 'assets/images/placeholder_cover.png';

/// 带占位与错误兜底的网络图片：
/// 加载中显示淡色底，失败（含 ImageDecoder 格式识别失败等）时回退到本地占位图。
class SafeNetworkImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 网易云 CDN 返回 http:// 图片地址，Web 混合内容策略与 Android 9+ 明文限制
    // 都会拦截，统一升级为 https 后再加载。
    final u = url.replaceFirst('http://', 'https://');
    if (u.isEmpty) {
      return Image.asset(kPlaceholderCover,
          width: width, height: height, fit: fit);
    }
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (c, child, chunk) {
        final expected = chunk?.expectedTotalBytes;
        if (expected == null || chunk!.cumulativeBytesLoaded >= expected) {
          return child;
        }
        return Container(
          width: width,
          height: height,
          color: Colors.white12,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) =>
          Image.asset(kPlaceholderCover, width: width, height: height, fit: fit),
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
class SectionHeader extends ConsumerWidget {
  final String title;
  final Widget? action;
  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: style.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: style.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

/// 统一空态：图标 + 标题 + 引导文案。
class EmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String hint;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.hint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: style.textSecondary.withValues(alpha: 0.7)),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(color: style.textPrimary, fontSize: 15)),
          const SizedBox(height: 6),
          Text(hint,
              style: TextStyle(color: style.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 歌曲行：封面 + 名称/歌手 + VIP 标 + 当前播放高亮（均衡器动效图标）。
/// 全应用（搜索结果 / 歌单详情 / 收藏 / 队列）共用，保证「正在播」识别一致。
class SongTile extends ConsumerWidget {
  final Song song;
  final int? index; // 显示序号（歌单/榜单场景），null 则显示封面。
  final VoidCallback? onTap;
  final Widget? trailing;
  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final q = ref.watch(queueProvider).valueOrNull;
    final isCurrent =
        q != null && q.index >= 0 && q.index < q.songs.length && q.songs[q.index].id == song.id;
    final ps = ref.watch(playbackStateProvider).valueOrNull;
    final playing = ps?.playing ?? false;

    final leading = index != null
        ? SizedBox(
            width: 28,
            child: isCurrent
                ? _EqBars(color: style.accent, animate: playing)
                : Text('$index',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: style.textSecondary, fontSize: 13)),
          )
        : CoverImage(
            url: song.coverUrl,
            size: 44,
            radius: BorderRadius.circular(style.uiRadius / 2));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(style.uiRadius / 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
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
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (song.isVip)
                        Container(
                          margin: const EdgeInsets.only(right: 5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: style.accent, width: 0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('VIP',
                              style: TextStyle(
                                  color: style.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      Expanded(
                        child: Text(song.artistName,
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
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
          vsync: this,
          duration: Duration(milliseconds: 420 + i * 130));
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
class PlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final double size;
  final VoidCallback? onTap;
  const PlaylistCard(
      {super.key, required this.playlist, this.size = 130, this.onTap});

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                                color: Colors.white, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              width: size,
              child: Text(playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 12,
                      height: 1.25)),
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
