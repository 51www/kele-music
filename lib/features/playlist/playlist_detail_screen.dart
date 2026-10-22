import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const PlaylistDetailScreen({super.key, required this.id});
  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  List<Song> _songs = [];
  Playlist? _meta;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await ref.read(apiProvider).playlistDetail(int.parse(widget.id));
      _songs = detail.tracks;
      _meta = detail.playlist;
    } catch (e) {
      _error = e is ApiException ? e.userMessage : e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 播放整个歌单；[index]=-1 表示随机起点。
  /// 立即跳播放页，起播（含随机起点计算）在后台完成。
  Future<void> _playAll({bool shuffle = false}) async {
    if (_songs.isEmpty || _busy) return;
    setState(() => _busy = true);
    final index = shuffle ? Random().nextInt(_songs.length) : 0;
    // 以整个歌单为播放队列，播完自动切下一首。
    await play.playAndOpen(ref, context, _songs, index);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onTap(Song s) async {
    final index = _songs.indexOf(s);
    await play.playAndOpen(ref, context, _songs, index < 0 ? 0 : index);
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    // 收藏歌单：元信息加载完成后可用（本地持久化）。
    final fav = _meta != null &&
        ref.watch(favoritePlaylistsProvider
            .select((l) => l.any((p) => p.id == _meta!.id)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _meta == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: TextStyle(color: style.textSecondary)),
                          SizedBox(height: AppSpacing.of(context).block),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon:
                                Icon(Icons.refresh, color: style.textSecondary),
                            label: Text('重试',
                                style: TextStyle(color: style.textSecondary)),
                          ),
                        ],
                      ),
                    )
                  : AppContentColumn(
                      child: _buildBody(style, fav),
                    ),
        ),
      ),
    );
  }

  Widget _buildBody(AppStyle style, bool fav) {
    final p = _meta;
    final sp = AppSpacing.of(context);
    return CustomScrollView(
      slivers: [
        // Hero 头：封面作背景 + 压暗渐变，浮动返回/收藏按钮。
        SliverToBoxAdapter(
          child: p == null
              ? const SizedBox(height: 120)
              : Stack(
                  children: [
                    SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SafeNetworkImage(
                              url: p.coverImgUrl, fit: BoxFit.cover),
                          DecoratedBox(
                              decoration: BoxDecoration(gradient: style.scrim)),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      right: 4,
                      child: Row(
                        children: [
                          IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => context.pop()),
                          const Spacer(),
                          // 收藏按钮：加半透明圆形底座——白色镂空图标直接叠在
                          // 浅色封面上几乎不可见（曾被视为"没有收藏入口"）。
                          IconButton(
                            icon: Icon(
                                fav ? Icons.bookmark : Icons.bookmark_border,
                                color: fav ? style.accent : Colors.white),
                            tooltip: fav ? '取消收藏歌单' : '收藏歌单',
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.30),
                            ),
                            onPressed: () async {
                              // 云端收藏（/playlist/subscribe）：乐观更新，
                              // 失败回滚并提示；未登录（301）提示先登录。
                              final notifier =
                                  ref.read(favoritePlaylistsProvider.notifier);
                              final wasFav = notifier.isFavorite(p.id);
                              try {
                                await notifier.toggle(p);
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                      content: Text(wasFav
                                          ? '已取消收藏「${p.name}」'
                                          : '已收藏，可在「音乐库 · 收藏」查看'),
                                    ));
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                      content: Text(e is ApiException
                                          ? e.userMessage
                                          : '收藏失败，请稍后重试'),
                                    ));
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    // 信息层：封面缩略 + 名称 + 播放量/曲目数。
                    Positioned(
                      left: sp.gutter,
                      right: sp.gutter,
                      bottom: sp.block,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SafeNetworkImage(
                                url: p.coverImgUrl,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover),
                          ),
                          SizedBox(width: sp.block),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        height: 1.3)),
                                SizedBox(height: sp.inline),
                                Text(
                                    '${fmtCount(p.playCount)} 次播放 · ${p.trackCount} 首',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        // 操作条：播放全部 + 随机播放。与下方曲目列表构成上下两个板块，
        // 间距统一走 AppSpacing。
        SliverToBoxAdapter(
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(sp.gutter, sp.block, sp.gutter, sp.inline),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _playAll(),
                    style: FilledButton.styleFrom(
                      backgroundColor: style.accent,
                      foregroundColor: style.bgBottom,
                    ),
                    icon: _busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: style.bgBottom))
                        : const Icon(Icons.play_arrow, size: 20),
                    label: const Text('播放全部'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _playAll(shuffle: true),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: style.surfaceBorder),
                      foregroundColor: style.textPrimary,
                    ),
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: const Text('随机播放'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.all(sp.inline),
                child: Text(_error!,
                    style: TextStyle(color: Colors.redAccent, fontSize: 13))),
          ),
        // 曲目列表。
        if (_songs.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
                icon: Icons.music_off_outlined,
                title: '歌单是空的',
                hint: '没有可播放的曲目'),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(
                horizontal: sp.gutter, vertical: sp.inline),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) => SongTile(
                  song: _songs[i],
                  index: i + 1,
                  onTap: () => _onTap(_songs[i]),
                ),
                childCount: _songs.length,
              ),
            ),
          ),
      ],
    );
  }
}
