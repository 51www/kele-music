import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 评论面板入口：玻璃拟态底部抽屉，展示当前歌曲的「热门/最新」评论。
/// [songId] 为当前播放歌曲 id（本地歌曲为负数，单独提示不支持）。
void showCommentsSheet(BuildContext context,
    {required int songId, required String songName}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => CommentsSheet(songId: songId, songName: songName),
  );
}

class CommentsSheet extends ConsumerStatefulWidget {
  final int songId;
  final String songName;
  const CommentsSheet(
      {super.key, required this.songId, required this.songName});

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  CommentTab _tab = CommentTab.latest;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 滚动近底自动加载更多（仅最新 Tab；热门无分页）。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      ref.read(songCommentsProvider((widget.songId, _tab)).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final mq = MediaQuery.of(context);
    final radius = BorderRadius.circular(style.uiRadius + 8);
    final isLocal = widget.songId < 0;

    return SafeArea(
      child: AMGlass(
        kind: AMGlassKind.sheet,
        animateAppearance: true,
        borderRadius: radius,
        margin: const EdgeInsets.all(16),
        constraints:
            BoxConstraints(maxWidth: 420, maxHeight: mq.size.height * 0.86),
        child: Column(
          children: [
            _handle(style),
            _header(style, isLocal),
            if (isLocal)
              Expanded(child: _localUnsupported(style))
            else ...[
              _tabBar(style),
              Expanded(child: _list(style)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _handle(AppStyle style) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          decoration: BoxDecoration(
            color: style.textSecondary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header(AppStyle style, bool isLocal) {
    final total = isLocal
        ? 0
        : ref.watch(songCommentsProvider((widget.songId, _tab))).total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Row(
        children: [
          Text('评论',
              style: TextStyle(
                  color: style.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: style.textSecondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(fmtCount(total),
                  style: TextStyle(color: style.textSecondary, fontSize: 11)),
            ),
          const Spacer(),
          // 歌名（避免过长截断）
          Flexible(
            child: Text(widget.songName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: style.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(AppStyle style) {
    final tabs = [
      (CommentTab.hot, '热门'),
      (CommentTab.latest, '最新'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: style.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (final (tab, label) in tabs)
            InkWell(
              onTap: () {
                if (_tab != tab) setState(() => _tab = tab);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 22, bottom: 8),
                padding: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  border: _tab == tab
                      ? Border(
                          bottom: BorderSide(color: style.accent, width: 2),
                        )
                      : null,
                ),
                child: Text(label,
                    style: TextStyle(
                      color:
                          _tab == tab ? style.textPrimary : style.textSecondary,
                      fontSize: 14,
                      fontWeight:
                          _tab == tab ? FontWeight.w700 : FontWeight.w400,
                    )),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(AppStyle style) {
    final state = ref.watch(songCommentsProvider((widget.songId, _tab)));

    if (state.loading && state.comments.isEmpty) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2.2, color: style.accent),
      );
    }
    if (state.error != null && state.comments.isEmpty) {
      return _errorState(style, state.error!);
    }
    if (state.comments.isEmpty) {
      return _emptyState(style);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: ListView.separated(
        key: ValueKey(_tab),
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        itemCount: state.comments.length + 1,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: style.surfaceBorder.withValues(alpha: 0.6),
        ),
        itemBuilder: (context, i) {
          if (i >= state.comments.length) {
            // 列表尾部：加载更多状态 / 「没有更多了」。
            if (state.loadingMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: style.accent),
                  ),
                ),
              );
            }
            if (state.hasMore) {
              return TextButton(
                onPressed: () => ref
                    .read(songCommentsProvider((widget.songId, _tab)).notifier)
                    .loadMore(),
                child: Text('加载更多',
                    style: TextStyle(color: style.accent, fontSize: 13)),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('没有更多了',
                    style: TextStyle(
                        color: style.textSecondary.withValues(alpha: 0.6),
                        fontSize: 12)),
              ),
            );
          }
          return _CommentTile(style: style, comment: state.comments[i]);
        },
      ),
    );
  }

  Widget _emptyState(AppStyle style) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: style.textSecondary.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text('暂无评论',
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ],
        ),
      );

  Widget _errorState(AppStyle style, String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: style.textSecondary.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: style.textSecondary, fontSize: 13)),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => ref
                  .read(songCommentsProvider((widget.songId, _tab)).notifier)
                  .load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: style.surfaceBorder),
              ),
            ),
          ],
        ),
      );

  Widget _localUnsupported(AppStyle style) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_outlined,
                size: 48, color: style.textSecondary.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text('本地歌曲暂不支持评论',
                style: TextStyle(color: style.textPrimary, fontSize: 14)),
          ],
        ),
      );
}

/// 单条评论：头像 + 昵称 + 正文 + 底部（相对时间 / 点赞数）。
class _CommentTile extends StatelessWidget {
  final AppStyle style;
  final Comment comment;
  const _CommentTile({required this.style, required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SafeNetworkImage(
              url: comment.avatarUrl,
              width: 36,
              height: 36,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comment.nickname.isEmpty ? '匿名' : comment.nickname,
                    style:
                        TextStyle(color: style.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(comment.content.isEmpty ? '（评论已删除）' : comment.content,
                    style: TextStyle(
                        color: style.textPrimary,
                        fontSize: 13.5,
                        height: 1.45)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_relTime(comment.time),
                        style: TextStyle(
                            color: style.textSecondary.withValues(alpha: 0.7),
                            fontSize: 11)),
                    const Spacer(),
                    Icon(Icons.favorite_border,
                        size: 14, color: style.textSecondary),
                    const SizedBox(width: 4),
                    Text(fmtCount(comment.likedCount),
                        style: TextStyle(
                            color: style.textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 相对时间：分钟/小时/天前，更早显示日期（YYYY-MM-DD）。
  String _relTime(int ms) {
    if (ms <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
