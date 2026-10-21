import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../player/play_utils.dart' as play;
import '../player/song_actions.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<Song> _songs = [];
  String _query = '';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _doSearch([String? keyword]) async {
    final kw = (keyword ?? _ctrl.text).trim();
    if (kw.isEmpty) return;
    // 点热词/历史词时回填输入框。
    if (kw != _ctrl.text) _ctrl.text = kw;
    setState(() {
      _loading = true;
      _error = null;
      _query = kw;
    });
    ref.read(searchHistoryProvider.notifier).add(kw);
    try {
      _songs = await ref.read(apiProvider).search(kw);
    } catch (e) {
      _error = e is ApiException ? e.userMessage : e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _clearInput() {
    _ctrl.clear();
    setState(() {
      _songs = [];
      _query = '';
      _error = null;
    });
    _focus.requestFocus();
  }

  Future<void> _onTap(Song s) async {
    // 立即跳播放页，音源解析在后台进行。
    await play.playAndOpen(ref, context, [s], 0);
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final history = ref.watch(searchHistoryProvider);
    final hots = ref.watch(hotSearchProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 搜索框。
                TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  style: TextStyle(color: style.textPrimary),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                  decoration: InputDecoration(
                    hintText: '搜索歌曲 / 歌手 / 专辑',
                    hintStyle: TextStyle(color: style.textSecondary),
                    prefixIcon: Icon(Icons.search, color: style.textSecondary),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close,
                                size: 20, color: style.textSecondary),
                            onPressed: _clearInput,
                          )
                        : null,
                    filled: true,
                    fillColor: style.surface,
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: style.surfaceBorder),
                        borderRadius:
                            BorderRadius.circular(style.uiRadius + 10)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: style.accent),
                        borderRadius:
                            BorderRadius.circular(style.uiRadius + 10)),
                  ),
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LinearProgressIndicator(
                        minHeight: 2,
                        color: style.accent,
                        backgroundColor: Colors.transparent),
                  ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.redAccent, fontSize: 13))),
                Expanded(
                  child: _query.isNotEmpty
                      ? _buildResults(style)
                      : _buildIdle(style, history, hots),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 未搜索态：搜索历史 + 热搜榜。
  Widget _buildIdle(AppStyle style, List<String> history, AsyncValue<List<String>> hots) {
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.history, size: 16, color: style.textSecondary),
              const SizedBox(width: 6),
              Text('搜索历史',
                  style: TextStyle(
                      color: style.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
                child: Icon(Icons.delete_outline,
                    size: 18, color: style.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: history
                .map((kw) => InputChip(
                      label: Text(kw,
                          style: TextStyle(
                              color: style.textPrimary, fontSize: 12.5)),
                      backgroundColor: style.surface,
                      side: BorderSide(color: style.surfaceBorder),
                      deleteIconColor: style.textSecondary,
                      onPressed: () => _doSearch(kw),
                      onDeleted: () => ref
                          .read(searchHistoryProvider.notifier)
                          .remove(kw),
                    ))
                .toList(),
          ),
          const SizedBox(height: 22),
        ],
        hots.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (words) {
            if (words.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_outlined,
                        size: 16, color: style.textSecondary),
                    const SizedBox(width: 6),
                    Text('热搜榜',
                        style: TextStyle(
                            color: style.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(words.length, (i) {
                    final hot = i < 3;
                    return ActionChip(
                      backgroundColor: style.surface,
                      side: BorderSide(
                          color: hot
                              ? style.accent.withValues(alpha: 0.6)
                              : style.surfaceBorder),
                      onPressed: () => _doSearch(words[i]),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hot)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      color: style.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                          Text(words[i],
                              style: TextStyle(
                                  color: style.textPrimary, fontSize: 12.5)),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 搜索结果：序号 + 封面 + 名称/歌手·专辑 + 时长 + ⋮ 操作菜单。
  Widget _buildResults(AppStyle style) {
    if (_songs.isEmpty && !_loading) {
      return EmptyState(
          icon: Icons.search_off,
          title: '没有找到「$_query」相关内容',
          hint: '换个关键词试试');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _songs.length,
      separatorBuilder: (_, __) => Divider(
          color: style.textSecondary.withValues(alpha: 0.12),
          height: 1,
          indent: 4),
      itemBuilder: (c, i) {
        final s = _songs[i];
        return SongTile(
          song: s,
          index: i + 1,
          showCover: true,
          showAlbum: true,
          durationMs: s.duration,
          onTap: () => _onTap(s),
          trailing: IconButton(
            icon: Icon(Icons.more_vert,
                size: 20, color: style.textSecondary),
            tooltip: '更多操作',
            // 拦截点击，避免冒泡触发整行播放。
            onPressed: () => showSongActionsSheet(context, ref, s),
          ),
        );
      },
    );
  }
}
