import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart';

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
      final detail = await ref
          .read(apiProvider)
          .playlistDetail(int.parse(widget.id));
      _songs = detail.tracks;
      _meta = detail.playlist;
    } catch (e) {
      _error = e is ApiException ? e.userMessage : e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 播放整个歌单；[index]=-1 表示随机起点。
  Future<void> _playAll({bool shuffle = false}) async {
    if (_songs.isEmpty || _busy) return;
    setState(() => _busy = true);
    final index =
        shuffle ? Random().nextInt(_songs.length) : 0;
    try {
      // 以整个歌单为播放队列，播完自动切下一首。
      await playQueue(ref, _songs, index);
      if (mounted) context.push('/now-playing');
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is ApiException ? e.userMessage : e.toString());
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onTap(Song s) async {
    final index = _songs.indexOf(s);
    try {
      await playQueue(ref, _songs, index < 0 ? 0 : index);
      if (mounted) context.push('/now-playing');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
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
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: Icon(Icons.refresh,
                                color: style.textSecondary),
                            label: Text('重试',
                                style: TextStyle(color: style.textSecondary)),
                          ),
                        ],
                      ),
                    )
                  : _buildBody(style, fav),
        ),
      ),
    );
  }

  Widget _buildBody(AppStyle style, bool fav) {
    final p = _meta;
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
                              decoration:
                                  BoxDecoration(gradient: style.scrim)),
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
                          IconButton(
                            icon: Icon(
                                fav ? Icons.bookmark : Icons.bookmark_border,
                                color: fav
                                    ? style.accent
                                    : Colors.white),
                            tooltip:
                                fav ? '取消收藏歌单' : '收藏歌单',
                            onPressed: () => ref
                                .read(favoritePlaylistsProvider.notifier)
                                .toggle(p),
                          ),
                        ],
                      ),
                    ),
                    // 信息层：封面缩略 + 名称 + 播放量/曲目数。
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
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
                          const SizedBox(width: 14),
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
                                const SizedBox(height: 6),
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
        // 操作条：播放全部 + 随机播放。
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                                strokeWidth: 2,
                                color: style.bgBottom))
                        : const Icon(Icons.play_arrow, size: 20),
                    label: const Text('播放全部'),
                  ),
                ),
                const SizedBox(width: 10),
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
                padding: const EdgeInsets.all(8),
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
            padding: const EdgeInsets.only(bottom: 24),
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
