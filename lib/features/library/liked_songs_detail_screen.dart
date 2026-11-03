import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 「我喜欢的音乐」详情页（收藏页签固定入口）：
/// 未登录或云端歌单 id 不可用时展示本机/云端收藏的单曲列表。
/// 只读歌单（不可改名/删除），单曲可取消收藏，点击即播放。
class LikedSongsDetailScreen extends ConsumerWidget {
  const LikedSongsDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final likedState = ref.watch(likedSongsProvider);
    final songs = likedState.songs;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: AppContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(0, sp.inline, 0, sp.block),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            Icon(Icons.arrow_back, color: style.textPrimary),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('我喜欢的音乐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: style.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                      ),
                      // 右侧留白与列表行尾图标对齐（48px 按钮内 20px 图标居中，
                      // 加 4px 行内边距 ≈ 18px），避免标题行贴边、列表不贴边。
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Text('${songs.length} 首',
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: songs.isEmpty
                      ? RefreshIndicator(
                          color: style.accent,
                          onRefresh: () => ref
                              .read(likedSongsProvider.notifier)
                              .refresh(),
                          child: ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: sp.section),
                              const EmptyState(
                                  icon: Icons.favorite_border,
                                  title: '还没有收藏的单曲',
                                  hint: '在歌曲 ⋮ 菜单或播放页点击 ♥ 收藏'),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: sp.scrollPadding,
                          itemCount: songs.length,
                          separatorBuilder: (_, __) => Divider(
                              color: style.textSecondary
                                  .withValues(alpha: 0.12),
                              height: 1,
                              indent: 4),
                          itemBuilder: (c, i) {
                            final s = songs[i];
                            return SongTile(
                              song: s,
                              index: i + 1,
                              onTap: () =>
                                  play.playAndOpen(ref, context, songs, i),
                              trailing: IconButton(
                                icon: Icon(Icons.favorite,
                                    color: style.accent, size: 20),
                                tooltip: '取消收藏',
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(likedSongsProvider.notifier)
                                        .toggle(s);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        behavior:
                                            SnackBarBehavior.floating,
                                        content: Text(e is ApiException
                                            ? e.userMessage
                                            : '操作失败，请稍后重试'),
                                      ));
                                    }
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
