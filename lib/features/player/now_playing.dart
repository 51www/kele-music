import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/download.dart' as downloader;
import '../../core/errors.dart';
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'lyrics_view.dart';
import 'play_utils.dart' as play;
import 'add_to_playlist_sheet.dart';
import 'comments_sheet.dart';
import 'more_sheet.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    // 仅在「音源尚未就绪」时于首帧推进起播：
    // - 起播在飞（先跳页后起播的入口）：handler.play() 内部的重入守卫
    //   交给在飞的 _playAt 完成，不产生同曲并发加载/重入；
    // - 此前解析失败（loadedSongId 不命中）：重试一次；
    // - 音源已加载成功：暂停是用户意图，打开播放页不再自动续播
    //   （否则主动暂停后点迷你条进播放页会被强制恢复播放）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final handler = ref.read(audioHandlerProvider);
      final song = handler.currentSong;
      if (song == null) return;
      if (handler.loadedSongId == song.id) return;
      final ps = ref.read(playbackStateProvider).valueOrNull;
      if (ps?.playing != true) handler.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final item = ref.watch(currentMediaItemProvider);
    final ps = ref.watch(playbackStateProvider);
    final liked = ref.watch(likedSongsProvider);
    // 仅 macOS 桌面端应用标题栏 inset 适配（隐藏标题栏后避开交通灯）。
    // 宽屏左右分栏按宽度判断、不限平台（见下方 useWide）。
    final isMac =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    // macOS 隐藏标题栏（fullSizeContentView）后内容铺到交通灯之下，SafeArea
    // 不感知；顶部预留交通灯高度，收起按钮等自有内容避开系统按钮区域。
    // 与 app_shell 的 macInset 保持同一取值与判定方式。
    final macInset = isMac ? 30.0 : 0.0;

    if (item.valueOrNull == null) {
      // 起播前置请求失败（见 playStartErrorProvider）：占位态改为展示
      // 失败原因 + 「返回」出口，避免永远转圈；否则正常转圈占位，
      // 数据到达后无缝切换到正式内容。
      final startError = ref.watch(playStartErrorProvider);
      return _bg(
        style,
        child: SafeArea(
          // 与正式内容一致：macOS 下预留标题栏高度，收起按钮避开交通灯。
          child: Padding(
            padding: EdgeInsets.only(top: macInset),
            child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down,
                        color: style.textPrimary),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Text('正在播放',
                      style: TextStyle(
                          color: style.textSecondary,
                          fontSize: 13,
                          letterSpacing: 0.2)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 占位封面：与正式封面同尺寸的圆角卡。
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(style.cardRadius),
                          color: style.surface,
                          border: Border.all(color: style.surfaceBorder),
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(style.cardRadius),
                          child: Image.asset(kPlaceholderCover,
                              fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (startError == null) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: style.accent),
                        ),
                        const SizedBox(height: 12),
                        Text('正在准备播放…',
                            style: TextStyle(
                                color: style.textSecondary, fontSize: 13)),
                      ] else ...[
                        Icon(Icons.error_outline,
                            color: style.textSecondary, size: 30),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(startError,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: style.textSecondary, fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('返回'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: style.textSecondary,
                              side: BorderSide(color: style.surfaceBorder)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 底部空白条：高度接近控制区，减少数据到达后的布局跳动。
              const SizedBox(height: 170),
            ],
            ),
          ),
        ),
      );
    }

    final m = item.value!;
    final duration = m.duration ?? Duration.zero;
    final playing = ps.valueOrNull?.playing ?? false;
    // 音源获取中：封面盖一层 loading，但按钮仍可点（点暂停会立即回 ▶）。
    final loading = ref.watch(playbackLoadingProvider).valueOrNull ??
        ref.read(audioHandlerProvider).isPreparing;
    final songId = int.tryParse(m.id) ?? 0;
    final isFav = liked.songs.any((s) => s.id == songId);
    final song = ref.read(audioHandlerProvider).currentSong;

    // 左右分栏按宽度判断，不限平台：macOS 宽窗、平板 / 车机横屏（宽度≥960）
    // 都启用「左封面右歌词」桌面式布局。手机竖屏（宽度通常 <960）与
    // 手机横屏多数仍在 960 以下，保持原有单列展示。
    final useWide = MediaQuery.sizeOf(context).width >= 960;
    final playerPage = _narrowNowPlaying(
      style: style,
      m: m,
      playing: playing,
      loading: loading,
      songId: songId,
      isFav: isFav,
      song: song,
      duration: duration,
      showLyricsToggle: !useWide,
    );

    return _bg(
      style,
      child: Stack(
        children: [
          // 毛玻璃封面背景：铺满页面上部约 62%，向下渐隐融入主题渐变。
          // 放在 SafeArea 之外，顶栏文字直接压在暗化封面上。
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 0.62,
                child: _CoverBackdrop(
                    style: style, url: m.artUri?.toString() ?? ''),
              ),
            ),
          ),
          SafeArea(
            // macOS 窗口采用 fullSizeContentView（透明标题栏、内容铺满整窗），
            // 交通灯固定占窗口左上角约 28pt，而 SafeArea 对此不感知（top=0）。
            // 手动预留标题栏高度，把收起按钮等自有内容压到系统按钮下方，
            // 避免与其重叠；背景毛玻璃仍铺满整窗不受影响。
            child: Padding(
              padding: EdgeInsets.only(top: macInset),
              child: useWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 左：播放页（封面 / 信息 / 工具栏 / 进度与播放控制）
                        Expanded(flex: 5, child: playerPage),
                        Container(
                            width: 0.5,
                            color: style.surfaceBorder),
                        // 右：歌词（参考桌面端同类产品，常驻右栏）
                        Expanded(
                            flex: 6,
                            child: _lyricsPane(style: style, songId: songId)),
                      ],
                    )
                  : playerPage,
            ),
          ),
        ],
      ),
    );
  }

  /// 播放页主体（窄屏单列 / 宽屏作为左栏复用）：顶栏 + 中部封面<->歌词切换 +
  /// 标题信息 + 工具栏 + 进度与播放控制。[showLyricsToggle] 控制工具栏里
  /// 「歌词」按钮是否出现（宽屏歌词常驻右栏，故隐藏）。
  Widget _narrowNowPlaying({
    required AppStyle style,
    required MediaItem m,
    required bool playing,
    required bool loading,
    required int songId,
    required bool isFav,
    required dynamic song,
    required Duration duration,
    required bool showLyricsToggle,
  }) {
    final remain = ref.watch(sleepTimerProvider);
    return Column(
        children: [
          // 顶栏：收起 + 居中场景标签（收藏/定时已移入进度条上方工具栏）。
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.keyboard_arrow_down, color: style.textPrimary),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              Text('正在播放',
                  style: TextStyle(
                      color: style.textSecondary,
                      fontSize: 13,
                      letterSpacing: 0.2)),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
          // 倒计时状态条
          if (remain != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SleepChip(remain: remain, style: style),
            ),
          const SizedBox(height: 12),
          // 中部：封面 <-> 歌词，由工具栏「歌词」按钮显式切换
          // （原全屏点击切换已移除，避免误触）。
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: _showLyrics
                  ? LyricsView(
                      key: const ValueKey('lyrics'),
                      style: style,
                      songId: songId)
                  : Padding(
                      key: const ValueKey('album'),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _AlbumArt(
                                style: style,
                                artUri: m.artUri,
                                playing: playing,
                                visual: ref.watch(playbackSettingsProvider
                                    .select((s) => s.nowPlayingVisual))),
                            if (loading) _CoverLoading(style: style),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(m.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: style.textPrimary,
                  fontSize: style.titleSize,
                  fontWeight: style.titleWeight,
                  letterSpacing: style.letterSpacing)),
          const SizedBox(height: 6),
          Text(m.artist ?? '',
              style: TextStyle(color: style.textSecondary, fontSize: 14)),
          // 补充歌曲信息行：专辑 · 时长，充实标题区内容。
          if (song != null) ...[
            const SizedBox(height: 5),
            Text('${song.album.name} · ${_fmtDuration(m.duration)}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: style.textSecondary.withValues(alpha: 0.75),
                    fontSize: 11.5)),
          ],
          // 原 Spacer 空白改为固定间距：布局紧凑，消除歌词下方大片留白。
          const SizedBox(height: 18),
          // 工具栏：收藏 / 定时 / 歌词 / 歌曲信息 / 下载（进度条上方）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? style.accent : style.textSecondary,
                      size: 22),
                  tooltip: isFav ? '取消喜欢' : '喜欢',
                  onPressed: () {
                    final song = ref.read(audioHandlerProvider).currentSong;
                    if (song == null) return;
                    // 云端喜欢（/like）：乐观更新失败回滚，错误浮层提示。
                    ref
                        .read(likedSongsProvider.notifier)
                        .toggle(song)
                        .catchError((Object e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 1800),
                            content: Text(e is ApiException
                                ? e.userMessage
                                : '操作失败，请稍后重试'),
                          ));
                      }
                    });
                  },
                ),
                const SizedBox(width: 14),
                IconButton(
                  icon: Icon(Icons.timer,
                      color: ref.watch(sleepTimerProvider) != null
                          ? style.accent
                          : style.textSecondary,
                      size: 22),
                  tooltip: ref.watch(sleepTimerProvider) != null
                      ? '定时停止中'
                      : '定时停止',
                  onPressed: () => _showSleepSheet(context, ref, style),
                ),
                if (showLyricsToggle) ...[
                  const SizedBox(width: 14),
                  IconButton(
                    icon: Icon(_showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                        color: _showLyrics ? style.accent : style.textSecondary,
                        size: 22),
                    tooltip: _showLyrics ? '返回封面' : '查看歌词',
                    onPressed: () => setState(() => _showLyrics = !_showLyrics),
                  ),
                ],
                const SizedBox(width: 14),
                IconButton(
                  icon: Icon(Icons.comment_outlined,
                      color: style.textSecondary, size: 22),
                  tooltip: '查看评论',
                  onPressed: () => showCommentsSheet(
                      context,
                      songId: songId,
                      songName: m.title),
                ),
                const SizedBox(width: 14),
                IconButton(
                  icon: Icon(Icons.more_horiz,
                      color: style.textSecondary, size: 22),
                  tooltip: '更多',
                  onPressed: () => showMoreSheet(
                        context,
                        onDownload: () => _downloadCurrent(context, ref),
                        onInfo: () => _showInfoSheet(context, ref, style),
                        onAddToPlaylist: () {
                          final song =
                              ref.read(audioHandlerProvider).currentSong;
                          if (song == null) return;
                          showAddToPlaylistSheet(context, ref, [song]);
                        },
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                // 进度条：缓冲 + 播放进度动效 + 拖拽定位
                _ProgressBar(
                    style: style,
                    duration: duration,
                    onSeek: ref.watch(audioHandlerProvider).seek),
                const SizedBox(height: 4),
                const _TimeLabels(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 播放模式：顺序 → 列表循环 → 单曲循环 → 随机。
                    IconButton(
                      icon: Icon(playModeIcon(ref.watch(playModeProvider)),
                          color: style.accent, size: 24),
                      tooltip: playModeLabel(ref.watch(playModeProvider)),
                      onPressed: () =>
                          ref.read(playModeProvider.notifier).cycle(),
                    ),
                    // 上一曲：播放超 3 秒可回本曲开头，否则需不在队首；
                    // 不可用时置灰（跟随 position 流实时刷新）。
                    Consumer(builder: (c, cref, _) {
                      final pos = cref
                              .watch(positionStreamProvider)
                              .valueOrNull ??
                          Duration.zero;
                      final q = cref.watch(queueProvider).valueOrNull;
                      final ok = (q != null && q.index > 0) ||
                          pos.inSeconds >= 3;
                      return IconButton(
                        iconSize: 40,
                        icon: Icon(Icons.skip_previous,
                            color: ok
                                ? style.textPrimary
                                : style.textSecondary.withValues(alpha: 0.35)),
                        tooltip: ok ? '上一首' : '没有上一曲',
                        onPressed:
                            ok ? () => play.skipPrevious(ref, context) : null,
                      );
                    }),
                    const SizedBox(width: 16),
                    IconButton(
                      iconSize: 56,
                      icon: Icon(
                          playing
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: style.textPrimary),
                      onPressed:
                          ref.watch(audioHandlerProvider).togglePlayPause,
                    ),
                    const SizedBox(width: 16),
                    // 下一曲：顺序模式到队尾置灰；循环/随机总可用。
                    Consumer(builder: (c, cref, _) {
                      final q = cref.watch(queueProvider).valueOrNull;
                      final mode = cref.watch(playModeProvider);
                      final ok = q != null &&
                          q.songs.isNotEmpty &&
                          (mode != PlayMode.sequential ||
                              q.index < q.songs.length - 1);
                      return IconButton(
                        iconSize: 40,
                        icon: Icon(Icons.skip_next,
                            color: ok
                                ? style.textPrimary
                                : style.textSecondary.withValues(alpha: 0.35)),
                        tooltip: ok ? '下一首' : '没有下一曲',
                        onPressed:
                            ok ? () => play.skipNext(ref, context) : null,
                      );
                    }),
                    IconButton(
                      icon: Icon(Icons.queue_music,
                          color: style.textSecondary, size: 24),
                      tooltip: '播放队列',
                      onPressed: () => context.push('/queue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      );
  }

  /// 宽屏右栏歌词面板：标题「歌词」+ 常驻滚动歌词（当前行 accent 高亮）。
  Widget _lyricsPane({required AppStyle style, required int songId}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 36, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
              child: Text('歌词',
                  style: TextStyle(
                      color: style.textSecondary,
                      fontSize: 13,
                      letterSpacing: 0.2)),
            ),
            Expanded(child: LyricsView(style: style, songId: songId)),
          ],
        ),
      );

  void _showSleepSheet(BuildContext context, WidgetRef ref, AppStyle style) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bc) => const _SleepSheet(),
    );
  }

  /// 歌曲信息弹窗：玻璃拟态面板，展示封面/标题/艺人/专辑/时长/ID。
  void _showInfoSheet(BuildContext context, WidgetRef ref, AppStyle style) {
    final handler = ref.read(audioHandlerProvider);
    final song = handler.currentSong;
    final m = handler.mediaItem.valueOrNull;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bc) {
        final radius = BorderRadius.circular(style.uiRadius + 8);
        final dur = song != null
            ? Duration(milliseconds: song.duration)
            : (m?.duration ?? Duration.zero);
        final artistNames =
            song?.artists.map((a) => a.name).join(' / ') ?? (m?.artist ?? '-');
        final title = song?.name ?? m?.title ?? '-';
        final cover = song?.album.picUrl ?? m?.artUri?.toString() ?? '';
        return SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color:
                    style.bgBottom,
                borderRadius: radius,
                border: Border.all(color: style.surfaceBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 拖拽把手
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: style.textSecondary
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 封面 + 标题/艺人
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SafeNetworkImage(
                                  url: cover,
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: style.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(artistNames,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: style.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _infoRow(style, '专辑', song?.album.name ?? '-'),
                        _infoRow(
                            style,
                            '时长',
                            '${dur.inMinutes.remainder(60).toString().padLeft(2, '0')}:${dur.inSeconds.remainder(60).toString().padLeft(2, '0')}'),
                        _infoRow(style, '歌曲 ID', song != null ? '${song.id}' : '-'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 时长格式化：mm:ss。
  String _fmtDuration(Duration? d) {
    final v = d ?? Duration.zero;
    return '${v.inMinutes.remainder(60).toString().padLeft(2, '0')}:${v.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  Widget _infoRow(AppStyle style, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style:
                      TextStyle(color: style.textSecondary, fontSize: 12))),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: style.textPrimary, fontSize: 13)),
          ),
        ]),
      );

  /// 下载当前歌曲：解析音源 → Web 走 Blob 下载（失败退化为新标签页），
  /// 移动/桌面端经平台通道保存到系统 Download 目录。
  Future<void> _downloadCurrent(
      BuildContext context, WidgetRef ref) async {
    final handler = ref.read(audioHandlerProvider);
    final song = handler.currentSong;
    if (song == null) return;
    final messenger = ScaffoldMessenger.of(context);
    void toast(String msg) => messenger.showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
    toast('正在准备下载：${song.name}');
    try {
      final level = ref.read(playbackSettingsProvider).downloadLevel;
      final url =
          await ref.read(apiProvider).songUrl(song.id, level: level);
      if (url == null || url.isEmpty) {
        toast('该歌曲暂无可用音源');
        return;
      }
      final artists = song.artists.map((a) => a.name).join('/');
      // 文件名净化：替换文件系统/媒体库非法字符。
      final filename =
          '$artists - ${song.name}.mp3'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ok = await downloader.downloadFile(url, filename);
      toast(ok ? '已保存到系统 Download 目录' : '下载失败，请稍后重试');
    } catch (_) {
      toast('下载失败，请稍后重试');
    }
  }
}

/// 定时停止弹窗：玻璃拟态面板 + 居中排版，复用设计 tokens
/// （surface / surfaceBorder / uiRadius / accent），与整体风格一致。
/// 宽屏下内容限宽 420 居中，键盘弹出时自动滚动，小屏不溢出。
class _SleepSheet extends ConsumerStatefulWidget {
  const _SleepSheet();
  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  final _controller = TextEditingController();
  String? _error;

  static const _presets = [15, 30, 45, 60, 90];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(Duration d) {
    ref.read(sleepTimerProvider.notifier).start(d);
    Navigator.pop(context);
  }

  void _startCustom() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v <= 0 || v > 24 * 60) {
      setState(() => _error = '请输入 1 - 1440 之间的分钟数');
      return;
    }
    _start(Duration(minutes: v));
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final active = ref.watch(sleepTimerProvider);
    final mq = MediaQuery.of(context);
    final radius = BorderRadius.circular(style.uiRadius + 8);

    String? remainText;
    final remain = active;
    if (remain != null) {
      final mm = remain.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = remain.inSeconds.remainder(60).toString().padLeft(2, '0');
      final hh = remain.inHours;
      remainText = hh > 0 ? '$hh:${mm.padLeft(2, '0')}:$ss 后停止' : '$mm:$ss 后停止';
    }

    return SafeArea(
      child: SingleChildScrollView(
        // 键盘弹出时底部让位，避免输入框被遮挡。
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Center(
          child: Container(
            // 宽屏（Web/平板）限宽居中，窄屏自然铺满。
            margin: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              // 深色玻璃底 + 主题色调染色，保证任何背景下文字可读。
              color: style.bgBottom,
              borderRadius: radius,
              border: Border.all(color: style.surfaceBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 拖拽把手
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: style.textSecondary.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 标题（居中）
                      Text('定时停止播放',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: style.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: style.letterSpacing)),
                      const SizedBox(height: 6),
                      // 状态副标题（居中）：进行中显示倒计时，否则提示语
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer,
                              size: 14, color: style.accent),
                          const SizedBox(width: 4),
                          Text(
                            remainText ?? '选择时长，到时自动停止播放',
                            style: TextStyle(
                                color: remainText != null
                                    ? style.accent
                                    : style.textSecondary,
                                fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // 预设时长：居中 Wrap 药丸芯片
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final minutes in _presets)
                            _SleepPill(
                              style: style,
                              label: '$minutes',
                              onTap: () =>
                                  _start(Duration(minutes: minutes)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // 自定义输入（居中）+ 错误提示
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (_) =>
                            setState(() => _error = null),
                        onSubmitted: (_) => _startCustom(),
                        style: TextStyle(
                            color: style.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: '自定义分钟数（1 - 1440）',
                          hintStyle: TextStyle(
                              color: style.textSecondary
                                  .withValues(alpha: 0.6),
                              fontSize: 13),
                          errorText: _error,
                          errorStyle: const TextStyle(fontSize: 11),
                          counterText: '',
                          filled: true,
                          fillColor:
                              style.textSecondary.withValues(alpha: 0.12),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(style.uiRadius),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(style.uiRadius),
                            borderSide:
                                BorderSide(color: style.accent, width: 1.2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 主操作：开始计时（accent 实心按钮，居中文字）
                      Material(
                        color: style.accent,
                        borderRadius:
                            BorderRadius.circular(style.uiRadius),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(style.uiRadius),
                          onTap: _startCustom,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text('开始计时',
                                  style: TextStyle(
                                      color: Color(0xE6000000),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                      // 取消倒计时（仅进行中显示）
                      if (remain != null) ...[
                        const SizedBox(height: 10),
                        Material(
                          color: Colors.redAccent.withValues(alpha: 0.14),
                          borderRadius:
                              BorderRadius.circular(style.uiRadius),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(style.uiRadius),
                            onTap: () {
                              ref
                                  .read(sleepTimerProvider.notifier)
                                  .cancel();
                              Navigator.pop(context);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text('取消倒计时',
                                    style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 预设时长药丸芯片：玻璃描边 + 数字大字 + “分钟”小字，文字居中。
class _SleepPill extends StatelessWidget {
  final AppStyle style;
  final String label;
  final VoidCallback onTap;
  const _SleepPill(
      {required this.style, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: style.textSecondary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: style.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 3),
              Text('分钟',
                  style: TextStyle(
                      color: style.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 倒计时状态 chip：剩余时间 + 取消按钮。
class _SleepChip extends ConsumerWidget {
  final Duration remain;
  final AppStyle style;
  const _SleepChip({required this.remain, required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hh = remain.inHours;
    final mm = remain.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remain.inSeconds.remainder(60).toString().padLeft(2, '0');
    // 超 1 小时带小时位（90 分钟预设显示 1:30:00 而非 30:00），
    // 与 _SleepSheet 的 remainText 处理保持一致。
    final text = hh > 0 ? '$hh:$mm:$ss 后停止播放' : '$mm:$ss 后停止播放';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 14, color: style.accent),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(color: style.textPrimary, fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => ref.read(sleepTimerProvider.notifier).cancel(),
            child: Icon(Icons.close, size: 14, color: style.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 进度条：缓冲进度 + 平滑播放进度，hover/拖拽时出现的细线播放头，支持点击/拖拽 seek。
class _ProgressBar extends ConsumerStatefulWidget {
  final AppStyle style;
  final Duration duration;
  final Future<void> Function(Duration) onSeek;
  const _ProgressBar(
      {required this.style, required this.duration, required this.onSeek});

  @override
  ConsumerState<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends ConsumerState<_ProgressBar> {
  double? _dragValue; // 拖拽中的临时值（0-1），松手后 seek。
  bool _hover = false;

  double _fraction(Duration d) {
    if (widget.duration <= Duration.zero) return 0;
    return (d.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  void _seekTo(double fraction) {
    final ms = (fraction * widget.duration.inMilliseconds).round();
    if (ms >= 0) widget.onSeek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final buffered =
        ref.watch(bufferedPositionStreamProvider).valueOrNull ?? Duration.zero;
    final posF = _dragValue ?? _fraction(position);
    final bufF = _fraction(buffered).clamp(posF, 1.0);
    final playing =
        ref.watch(playbackStateProvider).valueOrNull?.playing ?? false;
    // Apple Music：静止 3pt 细线，hover / 拖拽时加粗到 5pt 并显示播放头。
    final trackH = (_hover || _dragValue != null) ? 5.0 : 3.0;
    final showThumb = _hover || _dragValue != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final f = (d.localPosition.dx / w).clamp(0.0, 1.0);
            _seekTo(f);
          },
          onHorizontalDragUpdate: (d) {
            setState(() =>
                _dragValue = (d.localPosition.dx / w).clamp(0.0, 1.0));
          },
          onHorizontalDragEnd: (_) {
            if (_dragValue != null) _seekTo(_dragValue!);
            setState(() => _dragValue = null);
          },
          child: SizedBox(
            height: 26,
            width: w,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 底轨
                Container(
                    height: trackH,
                    decoration: BoxDecoration(
                        color:
                            widget.style.textSecondary.withValues(alpha: 0.25),
                        borderRadius:
                            BorderRadius.circular(AMTokens.radiusLine))),
                // 缓冲
                FractionallySizedBox(
                  widthFactor: bufF,
                  child: Container(
                      height: trackH,
                      decoration: BoxDecoration(
                          color: widget.style.textSecondary
                              .withValues(alpha: 0.45),
                          borderRadius:
                              BorderRadius.circular(AMTokens.radiusLine))),
                ),
                // 已播放（进度随 positionStream 平滑推进）
                FractionallySizedBox(
                  widthFactor: posF,
                  child: Container(
                      height: trackH,
                      decoration: BoxDecoration(
                          color: widget.style.accent,
                          borderRadius:
                              BorderRadius.circular(AMTokens.radiusLine))),
                ),
                // 播放头：仅 hover / 拖拽时出现，静态无呼吸。
                if (showThumb)
                  Positioned(
                    left: (w - 10) * posF,
                    child: _PulseThumb(
                        color: widget.style.accent, animate: playing),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 播放头：10pt 静态圆点，仅 hover / 拖拽时显示，无呼吸动画。
class _PulseThumb extends StatelessWidget {
  final Color color;
  final bool animate;
  const _PulseThumb({required this.color, required this.animate});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: animate ? 1.0 : 0.8),
        ),
      );
}

/// 时间标签：左=当前进度，右=总时长（等宽数字，随主题取色）。
class _TimeLabels extends ConsumerWidget {
  const _TimeLabels();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(currentMediaItemProvider).valueOrNull?.duration ??
        Duration.zero;
    final labelStyle = TextStyle(
        color: style.textSecondary,
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_fmt(position), style: labelStyle),
        Text(_fmt(duration), style: labelStyle),
      ],
    );
  }
}

Widget _bg(AppStyle style, {required Widget child}) => Scaffold(
      backgroundColor: style.bgTop,
      body: Container(
        color: style.bgTop,
        child: child,
      ),
    );

/// 封面上的音源获取中遮罩：只盖封面区域、不拦点击（IgnorePointer），
/// 播放按钮与暂停操作不受影响；音源就绪或失败/超时后由状态流撤下。
class _CoverLoading extends StatelessWidget {
  final AppStyle style;
  const _CoverLoading({required this.style});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 240,
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: style.accent),
            ),
            const SizedBox(height: 10),
            Text('正在获取音源…',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

/// 播放页封面，按设置切两种 Apple Music 呈现
/// （playbackSettingsProvider.nowPlayingVisual，枚举值与持久化不变）：
/// - vinylWave（默认）：静态大尺寸圆角专辑封面；
/// - classic：静态封面 + 背后一层极轻的取色光晕。
/// 两者均无循环动画；图片未加载/加载失败时显示默认封面（不露黑块）。
class _AlbumArt extends StatefulWidget {
  final AppStyle style;
  final Uri? artUri;
  final bool playing;
  final String visual; // kVisualVinylWave / kVisualClassic
  const _AlbumArt(
      {required this.style,
      required this.artUri,
      required this.playing,
      required this.visual});

  @override
  State<_AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<_AlbumArt> {
  @override
  Widget build(BuildContext context) {
    final url = widget.artUri?.toString() ?? '';
    // 默认封面垫底：网络图加载中/失败时露出的是占位图而非黑块。
    final img = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(kPlaceholderCover, fit: BoxFit.cover),
          SafeNetworkImage(url: url),
        ],
      ),
    );
    // 封面入场：一次性缩放淡入，静止后不再重复；减少动态效果时瞬时完成。
    final cover = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1.0),
      duration: AMTokens.revealDuration(context),
      curve: Curves.easeOutCubic,
      builder: (c, v, child) => Transform.scale(
        scale: v,
        child: Opacity(opacity: v, child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AMTokens.radiusHero),
        child: SizedBox(width: 300, height: 300, child: img),
      ),
    );
    // Apple Music：静态大尺寸圆角封面，不做黑胶旋转 / 波形 / 涟漪。
    // nowPlayingVisual 两项设置仍各有可见差异：标准封面 = 纯封面，
    // 氛围封面 = 封面背后一层极轻的静态光晕；设置与持久化逻辑不变。
    if (widget.visual == kVisualClassic) {
      return _Ripple(
        color: widget.style.accent,
        playing: widget.playing,
        baseRadius: 126,
        child: cover,
      );
    }
    return cover;
  }
}

/// 封面毛玻璃背景：铺满播放页上部区域，底缘渐隐融入主题渐变。
/// 用 ImageFiltered 做静态模糊（内容不变时合成器缓存，无逐帧采样开销，
/// 优于 BackdropFilter）；暗化 scrim 保证顶栏/标题文字可读。
class _CoverBackdrop extends StatelessWidget {
  final AppStyle style;
  final String url;
  const _CoverBackdrop({required this.style, required this.url});

  @override
  Widget build(BuildContext context) {
    // 主背景为恒定中性纯色，接缝色直接取底色，渐隐终点与之无缝衔接。
    final seamColor = style.bgTop;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 占位垫底：封面未加载/为空时不露主题渐变以外的底色。
          Image.asset(kPlaceholderCover, fit: BoxFit.cover),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: AMTokens.backdropBlur, sigmaY: AMTokens.backdropBlur),
            child: SafeNetworkImage(url: url, fit: BoxFit.cover),
          ),
          // 中性半透明罩：明暗主题下都把封面压成低对比氛围层。
          Container(color: style.bgTop.withValues(alpha: 0.55)),
          // 底缘渐隐：0.45 起隐 → 中段缓入 → 底边精确落在接缝色，
          // 三段过渡比两段更柔，消除与页面渐变的生硬分界。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.45, 0.78, 1.0],
                colors: [
                  Colors.transparent,
                  seamColor.withValues(alpha: 0.35),
                  seamColor,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面背后的静态取色光晕（无循环动画），仅「氛围封面」设置下出现。
class _Ripple extends StatelessWidget {
  final Color color;
  final bool playing;
  final double baseRadius;
  final Widget child;
  const _Ripple({
    required this.color,
    required this.playing,
    required this.baseRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: baseRadius * 2 + 80,
              height: baseRadius * 2 + 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: playing ? 0.10 : 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      );
}
