import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 全部歌单页：按分类浏览热门歌单（/playlist/catlist + /top/playlist）。
/// 分类 chips 横滑，第一个为「热门推荐」（全部）；列表滚动到底自动翻页。
class AllPlaylistsScreen extends ConsumerStatefulWidget {
  const AllPlaylistsScreen({super.key});
  @override
  ConsumerState<AllPlaylistsScreen> createState() => _AllPlaylistsScreenState();
}

class _AllPlaylistsScreenState extends ConsumerState<AllPlaylistsScreen> {
  static const _pageSize = 30;

  List<String> _categories = [];
  List<Playlist> _playlists = [];
  String? _selectedCat; // null = 热门推荐（全部）
  bool _loadingCats = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollCtrl.position.pixels >
        _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    try {
      final cats = await ref.read(apiProvider).playlistCategories();
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {
      // 分类加载失败不阻塞主列表，仅隐藏 chips。
      if (mounted) setState(() => _categories = const []);
    } finally {
      if (mounted) setState(() => _loadingCats = false);
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiProvider).topPlaylists(
            cat: _selectedCat,
            offset: 0,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _playlists = list;
        _hasMore = list.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.userMessage : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final list = await ref.read(apiProvider).topPlaylists(
            cat: _selectedCat,
            offset: _playlists.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        // 按 id 去重防翻页重复。
        final ids = _playlists.map((p) => p.id).toSet();
        _playlists.addAll(list.where((p) => !ids.contains(p.id)));
        _hasMore = list.length >= _pageSize;
      });
    } catch (_) {
      // 翻页失败静默，下次滚动重试。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectCat(String? cat) {
    if (cat == _selectedCat) return;
    _selectedCat = cat;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶栏：返回 + 标题。
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new,
                        color: style.textPrimary, size: 20),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('全部歌单',
                      style: TextStyle(
                          color: style.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 4),
              // 分类 chips：热门推荐 + 全部分类，横滑。
              if (!_loadingCats && _categories.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (c, i) {
                      final name = i == 0 ? '热门推荐' : _categories[i - 1];
                      final cat = i == 0 ? null : _categories[i - 1];
                      final selected = cat == _selectedCat;
                      return ChoiceChip(
                        label: Text(name),
                        selected: selected,
                        selectedColor: style.accent,
                        backgroundColor: style.surface,
                        side: BorderSide(
                            color: selected
                                ? style.accent
                                : style.surfaceBorder),
                        labelStyle: TextStyle(
                            color: selected
                                ? style.bgBottom
                                : style.textPrimary,
                            fontSize: 12.5),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _selectCat(cat),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(style)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppStyle style) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: style.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh, color: style.textSecondary),
              label: Text('重试', style: TextStyle(color: style.textSecondary)),
            ),
          ],
        ),
      );
    }
    if (_playlists.isEmpty) {
      return Center(
          child: Text('该分类暂无歌单',
              style: TextStyle(color: style.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 960 ? 5 : (w >= 640 ? 4 : 2);
        return GridView.builder(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 186,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
          ),
          itemCount: _playlists.length + (_hasMore ? 1 : 0),
          itemBuilder: (c, i) {
            if (i >= _playlists.length) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: _loadingMore
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : null,
                  ),
                ),
              );
            }
            final p = _playlists[i];
            return PlaylistCard(
              playlist: p,
              onTap: () => context.push('/playlist/${p.id}'),
            );
          },
        );
      }),
    );
  }
}
