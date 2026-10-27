import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;

/// 每日推荐页：需登录（平台 /recommend/songs 依赖 cookie）。
/// 未登录引导去登录；已登录拉取当日推荐歌曲并可直接播放。
class DailyRecommendScreen extends ConsumerStatefulWidget {
  const DailyRecommendScreen({super.key});
  @override
  ConsumerState<DailyRecommendScreen> createState() =>
      _DailyRecommendScreenState();
}

class _DailyRecommendScreenState extends ConsumerState<DailyRecommendScreen> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loggedIn =
        ref.read(authStateProvider).status == AuthStatus.authenticated;
    if (!loggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final songs = await ref.read(apiProvider).recommendSongs();
      if (mounted) {
        setState(() {
          _songs = songs;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException ? e.userMessage : e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _playAll() async {
    if (_busy || _songs.isEmpty) return;
    setState(() => _busy = true);
    ref.read(playStartErrorProvider.notifier).state = null;
    context.push('/now-playing');
    try {
      await play.playQueue(ref, _songs, 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.userMessage : '播放失败'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2)));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final sp = AppSpacing.of(context);
    final loggedIn =
        ref.watch(authStateProvider).status == AuthStatus.authenticated;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          child: AppContentColumn(
            child: Column(
              children: [
                _buildAppBar(style, loggedIn),
                Expanded(
                  child: !loggedIn
                      ? _buildLoginHint(style)
                      : _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_error!,
                                          style: TextStyle(
                                              color: style.textSecondary)),
                                      SizedBox(height: sp.block),
                                      OutlinedButton.icon(
                                        onPressed: _load,
                                        icon: Icon(Icons.refresh,
                                            color: style.textSecondary),
                                        label: Text('重试',
                                            style: TextStyle(
                                                color: style.textSecondary)),
                                      ),
                                    ],
                                  ),
                                )
                              : _songs.isEmpty
                                  ? Center(
                                      child: Text('今日暂无推荐',
                                          style: TextStyle(
                                              color: style.textSecondary)))
                                  : ListView.separated(
                                      padding: EdgeInsets.fromLTRB(
                                          sp.gutter, 0, sp.gutter, sp.section),
                                      itemCount: _songs.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(
                                              height: AppSpacing.xxs),
                                      itemBuilder: (c, i) => SongTile(
                                        song: _songs[i],
                                        onTap: () => play.playAndOpen(
                                            ref, context, _songs, i),
                                      ),
                                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(AppStyle style, bool loggedIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: style.textPrimary),
          ),
          Expanded(
            child: Text('每日推荐',
                style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          if (loggedIn && _songs.isNotEmpty)
            FilledButton.icon(
              onPressed: _busy ? null : _playAll,
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              label: const Text('播放全部'),
            ),
        ],
      ),
    );
  }

  Widget _buildLoginHint(AppStyle style) {
    final sp = AppSpacing.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.recommend_outlined,
                size: 56, color: style.textSecondary.withValues(alpha: 0.7)),
            SizedBox(height: sp.block),
            Text('每日推荐需要登录',
                style: TextStyle(color: style.textPrimary, fontSize: 16)),
            const SizedBox(height: AppSpacing.micro),
            Text('登录后为你精选当日好歌',
                style: TextStyle(color: style.textSecondary, fontSize: 12)),
            SizedBox(height: sp.block),
            FilledButton.icon(
              onPressed: () => context.push('/login'),
              style: FilledButton.styleFrom(
                backgroundColor: style.accent,
                foregroundColor: style.bgBottom,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: 10),
              ),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
