import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/download.dart' as downloader;
import '../../core/styles.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'lyrics_view.dart';
import 'play_utils.dart' as play;

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
    // 进入播放页直接开播：有当前曲目且未在播放时自动恢复，
    // 无需再手动点播放按钮（源加载失败时 play() 为空操作，不报错）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final handler = ref.read(audioHandlerProvider);
      if (handler.currentSong == null) return;
      final ps = ref.read(playbackStateProvider).valueOrNull;
      if (ps?.playing != true) handler.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = kStyles[ref.watch(styleIndexProvider)];
    final item = ref.watch(currentMediaItemProvider);
    final ps = ref.watch(playbackStateProvider);
    final handler = ref.watch(audioHandlerProvider);
    final sleepRemain = ref.watch(sleepTimerProvider);
    final favorites = ref.watch(favoritesProvider);

    if (item.valueOrNull == null) {
      // 数据未就绪（刚点歌/歌单、音源解析中）：占位封面 + loading 态，
      // 数据到达后无缝切换到正式内容；保留返回按钮可随时退出。
      return _bg(
        style,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Text('正在播放',
                      style: TextStyle(
                          color: style.textSecondary,
                          fontSize: 13,
                          letterSpacing: 3)),
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
                          color: Colors.white.withValues(alpha: 0.06),
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
                    ],
                  ),
                ),
              ),
              // 底部空白条：高度接近控制区，减少数据到达后的布局跳动。
              const SizedBox(height: 170),
            ],
          ),
        ),
      );
    }

    final m = item.value!;
    final duration = m.duration ?? Duration.zero;
    final playing = ps.valueOrNull?.playing ?? false;
    final songId = int.tryParse(m.id) ?? 0;
    final isFav = favorites.any((s) => s.id == songId);
    final song = handler.currentSong;

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
        child: Column(
          children: [
            // 顶栏：收起 + 居中场景标签（收藏/定时已移入进度条上方工具栏）。
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                const Spacer(),
                Text('正在播放',
                    style: TextStyle(
                        color: style.textSecondary,
                        fontSize: 13,
                        letterSpacing: 3)),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
            // 倒计时状态条
            if (sleepRemain != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SleepChip(remain: sleepRemain, style: style),
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
                            child: _AlbumArt(
                                style: style,
                                artUri: m.artUri,
                                playing: playing,
                                visual: ref.watch(playbackSettingsProvider
                                    .select((s) => s.nowPlayingVisual)))),
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
                    tooltip: isFav ? '取消收藏' : '收藏',
                    onPressed: () {
                      final song = handler.currentSong;
                      if (song != null) {
                        ref.read(favoritesProvider.notifier).toggle(song);
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    icon: Icon(Icons.timer_outlined,
                        color: sleepRemain != null
                            ? style.accent
                            : style.textSecondary,
                        size: 22),
                    tooltip: sleepRemain != null ? '定时停止中' : '定时停止',
                    onPressed: () => _showSleepSheet(context, ref, style),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    icon: Icon(_showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                        color: _showLyrics ? style.accent : style.textSecondary,
                        size: 22),
                    tooltip: _showLyrics ? '返回封面' : '查看歌词',
                    onPressed: () => setState(() => _showLyrics = !_showLyrics),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    icon: Icon(Icons.info_outline,
                        color: style.textSecondary, size: 22),
                    tooltip: '歌曲信息',
                    onPressed: () => _showInfoSheet(context, ref, style),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    icon: Icon(Icons.download_outlined,
                        color: style.textSecondary, size: 22),
                    tooltip: '下载',
                    onPressed: () => _downloadCurrent(context, ref),
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
                      style: style, duration: duration, onSeek: handler.seek),
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
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: style.textPrimary),
                        onPressed: () => playing ? handler.pause() : handler.play(),
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
                        icon: const Icon(Icons.queue_music,
                            color: Colors.white70, size: 24),
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
        ),
          ),
        ],
      ),
    );
  }

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
                    Color.alphaBlend(style.surface, const Color(0x8C000000)),
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
              color: Color.alphaBlend(style.surface, const Color(0x8C000000)),
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
                          Icon(Icons.timer_outlined,
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
    final mm = remain.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remain.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 14, color: style.accent),
          const SizedBox(width: 4),
          Text('$mm:$ss 后停止播放',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => ref.read(sleepTimerProvider.notifier).cancel(),
            child: const Icon(Icons.close, size: 14, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

/// 进度条：缓冲进度 + 平滑播放进度 + 播放中呼吸脉动圆点，支持点击/拖拽 seek。
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

    return LayoutBuilder(builder: (context, constraints) {
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
                  height: 4,
                  decoration: BoxDecoration(
                      color: widget.style.textSecondary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2))),
              // 缓冲
              FractionallySizedBox(
                widthFactor: bufF,
                child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: widget.style.textSecondary
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2))),
              ),
              // 已播放（进度随 positionStream 平滑推进）
              FractionallySizedBox(
                widthFactor: posF,
                child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: widget.style.accent,
                        borderRadius: BorderRadius.circular(2))),
              ),
              // 播放头
              Positioned(
                left: (w - 12) * posF,
                child: _PulseThumb(
                    color: widget.style.accent, animate: playing),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// 播放头圆点：播放中轻微呼吸脉动（音画同步的可视反馈）。
class _PulseThumb extends StatefulWidget {
  final Color color;
  final bool animate;
  const _PulseThumb({required this.color, required this.animate});

  @override
  State<_PulseThumb> createState() => _PulseThumbState();
}

class _PulseThumbState extends State<_PulseThumb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (c, _) {
        final t = widget.animate ? 0.75 + 0.25 * _c.value : 1.0;
        return Container(
          width: 12 * t,
          height: 12 * t,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 6 * t),
              ]),
        );
      },
    );
  }
}

/// 时间标签：左=当前进度，右=总时长。
class _TimeLabels extends ConsumerWidget {
  const _TimeLabels();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(currentMediaItemProvider).valueOrNull?.duration ??
        Duration.zero;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_fmt(position),
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(_fmt(duration),
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

Widget _bg(AppStyle style, {required Widget child}) => Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: style.backgroundGradient),
        child: child,
      ),
    );

/// 播放页封面，按设置切两种视觉（playbackSettingsProvider.nowPlayingVisual）：
/// - vinylWave（默认）：黑胶版式走 [_VinylDisc]（唱片 + 背后波形线 + 播放动效）；
/// - classic：经典静态圆盘封面 + 水波纹扩散。
/// 卡片/柔焦版式不受此设置影响，保持静态呈现，播放中封面后方叠加水波纹；
/// 暂停动效即停（平滑消退）；图片未加载/加载失败时显示默认封面（不露黑块）。
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
    final style = widget.style;

    // 黑胶版式按设置分流：经典模式恢复原静态圆盘 + 水波纹。
    if (style.albumPresentation == AlbumPresentation.vinyl) {
      if (widget.visual == kVisualClassic) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _Ripple(
                color: style.accent,
                playing: widget.playing,
                baseRadius: 126),
            Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black),
              padding: const EdgeInsets.all(18),
              child: ClipOval(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 6),
                  ),
                  child: ClipOval(child: img),
                ),
              ),
            ),
          ],
        );
      }
      // 黑胶动效：唱片居中 + 背后音符波形线，自带动效（见 _VinylDisc）。
      return _VinylDisc(
          style: style, artUri: widget.artUri, playing: widget.playing);
    }

    final Widget art;
    final double rippleBase; // 水波纹起始半径（略大于封面外接尺寸）

    if (style.albumPresentation == AlbumPresentation.card) {
      rippleBase = 174; // 方形封面外接对角线一半 ≈ 170，从角落外起波
      art = ClipRRect(
        borderRadius: BorderRadius.circular(style.cardRadius),
        child: SizedBox(width: 240, height: 240, child: img),
      );
    } else {
      rippleBase = 146;
      art = Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: SafeNetworkImage(url: url),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 200, height: 200, child: img),
          ),
        ],
      );
    }

    // 水波纹在封面后方扩散：playing 驱动，暂停平滑消退。
    return Stack(
      alignment: Alignment.center,
      children: [
        _Ripple(
            color: style.accent,
            playing: widget.playing,
            baseRadius: rippleBase),
        art,
      ],
    );
  }
}

/// 黑胶唱片视觉（参考设计稿）：页面中央一张黑色唱片，唱片中心放置歌曲
/// 封面并裁剪为圆形；唱片下层（后方）一根贯穿左右的音符波形线。
/// 动效：播放中唱片匀速慢转、波形线随节奏律动；暂停时两者同时静止。
/// 性能：全部 CustomPaint + 两个 AnimationController，无 widget 级重建。
class _VinylDisc extends StatefulWidget {
  final AppStyle style;
  final Uri? artUri;
  final bool playing;
  const _VinylDisc(
      {required this.style, required this.artUri, required this.playing});

  @override
  State<_VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<_VinylDisc>
    with TickerProviderStateMixin {
  // 唱片旋转：约 9s 一圈，缓慢持续。
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(seconds: 9));
  // 波形相位：1.2s 一循环，播放中循环推进；停止时冻结在当前相位。
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    _sync(widget.playing);
  }

  void _sync(bool playing) {
    if (playing) {
      _spin.repeat();
      _wave.repeat();
    } else {
      _spin.stop();
      _wave.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _sync(widget.playing);
  }

  @override
  void dispose() {
    _spin.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final url = widget.artUri?.toString() ?? '';
    // 封面图：占位垫底防黑块，网络图加载完成后覆盖。
    final coverImg = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(kPlaceholderCover, fit: BoxFit.cover),
          SafeNetworkImage(url: url),
        ],
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      // 波形线横贯可用宽度（比唱片宽，两端露出）。
      final waveWidth = math.max(constraints.maxWidth, 320.0);
      return Stack(
        alignment: Alignment.center,
        children: [
          // 波形线：位于唱片后方（下层），播放时律动，暂停静止。
          AnimatedBuilder(
            animation: _wave,
            builder: (_, __) => CustomPaint(
              size: Size(waveWidth, 150),
              painter: _WaveLinePainter(color: style.accent, t: _wave.value),
            ),
          ),
          // 唱片本体（盘面 + 圆形封面）整体旋转，暂停停转。
          AnimatedBuilder(
            animation: _spin,
            builder: (_, __) => Transform.rotate(
              angle: _spin.value * 2 * math.pi,
              child: _buildRecord(coverImg),
            ),
          ),
        ],
      );
    });
  }

  /// 唱片：黑色盘面（带纹路高光）+ 圆形封面 + 中心主轴孔。
  Widget _buildRecord(Widget coverImg) => SizedBox(
        width: 240,
        height: 240,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 盘面：纯画笔绘制底色、唱纹、外缘描边（内容恒定，不重绘）。
            const CustomPaint(painter: _VinylPainter()),
            // 圆形封面：白描边 + 投影，随唱片一起旋转。
            Center(
              child: Container(
                width: 116,
                height: 116,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.fromBorderSide(
                      BorderSide(color: Colors.white24, width: 5)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black38,
                        blurRadius: 10,
                        spreadRadius: 1),
                  ],
                ),
                child: ClipOval(child: coverImg),
              ),
            ),
            // 中心主轴孔：唱片旋转的视觉锚点。
            Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(color: Colors.white38, width: 1.4),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 黑胶盘面画笔：黑色底盘 + 细密唱纹 + 外缘微光，静态内容不触发重绘。
class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // 黑色底盘（略带深灰渐层感：两层叠加）
    canvas.drawCircle(
        center, radius, Paint()..color = const Color(0xFF0E0E0E));
    canvas.drawCircle(
      center,
      radius * 0.97,
      Paint()
        ..shader = ui.Gradient.radial(
          center - const Offset(30, 40),
          radius * 1.3,
          [const Color(0xFF2A2A2A), const Color(0xFF0A0A0A)],
        ),
    );

    // 细密唱纹：从封面外缘到盘边的同心细环。
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);
    for (var r = radius * 0.54; r < radius - 5; r += 4.5) {
      canvas.drawCircle(center, r, groove);
    }

    // 外缘描边：轻微轮廓光，避免黑盘融入深色背景。
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant _VinylPainter oldDelegate) => false;
}

/// 音符波形线画笔：横贯左右的平滑曲线，波峰集中在唱片两侧
/// （中间被唱片遮住，无需强起伏）。播放中相位随 t 推进、整体振幅
/// 按 2Hz 起伏模拟「随节奏跳动」；暂停时 t 冻结 → 曲线静止。
class _WaveLinePainter extends CustomPainter {
  final Color color;
  final double t; // 0..1 相位
  _WaveLinePainter({required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final midY = size.height / 2;
    final path = Path();
    const cycles = 3.0; // 全宽波峰数
    // 节奏感：整体振幅随时间缓慢起伏（暂停时冻结）。
    final amp =
        size.height * 0.34 * (0.72 + 0.28 * math.sin(t * 2 * math.pi * 2));
    // 包络：两端收窄、靠近唱片处最宽（正弦包络）。
    double envelope(double x) =>
        math.pow(math.sin(math.pi * x / w), 1.4).toDouble();

    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final y = midY +
          envelope(x) *
              amp *
              math.sin(2 * math.pi * (cycles * x / w) + t * 2 * math.pi);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_WaveLinePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
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
    // 接缝色：本层只铺页面上部 62%（heightFactor 0.62），而页面背景是
    // bgTop→bgBottom 的全页线性渐变，在该高度处的实际颜色是
    // lerp(bgTop, bgBottom, 0.62)。此前渐隐终点是纯 bgBottom，与页面
    // 中间态存在色差 → 底边出现一条硬边。渐到接缝色即可无缝衔接。
    final seamColor = Color.lerp(style.bgTop, style.bgBottom, 0.62)!;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 占位垫底：封面未加载/为空时不露主题渐变以外的底色。
          Image.asset(kPlaceholderCover, fit: BoxFit.cover),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: SafeNetworkImage(url: url, fit: BoxFit.cover),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
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
                  seamColor.withValues(alpha: 0.45),
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

/// 播放态水波纹：以封面为中心的三圈扩散涟漪。
/// 性能：单 AnimationController + CustomPaint 纯画笔绘制（每帧 3 个圆环），
/// 无 widget 重建；暂停时停止推进并整体平滑淡出（AnimatedOpacity）。
class _Ripple extends StatefulWidget {
  final Color color;
  final bool playing;
  final double baseRadius;
  const _Ripple(
      {required this.color, required this.playing, required this.baseRadius});

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Ripple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      widget.playing ? _c.repeat() : _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.playing ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _c,
          builder: (c, _) => CustomPaint(
            size: Size.square(widget.baseRadius * 2 + 160),
            painter: _RipplePainter(
                color: widget.color, base: widget.baseRadius, t: _c.value),
          ),
        ),
      ),
    );
  }
}

/// 涟漪画笔：三圈相位均错开，扩散用 easeOutCubic（前快后慢，贴近水波），
/// 透明度随扩散二次衰减，波纹淡出柔和无跳变。
class _RipplePainter extends CustomPainter {
  final Color color;
  final double base;
  final double t;
  _RipplePainter({required this.color, required this.base, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const rings = 3;
    for (var i = 0; i < rings; i++) {
      final p = (t + i / rings) % 1.0;
      final eased = 1 - math.pow(1 - p, 3).toDouble();
      final radius = base + eased * 72;
      final alpha = (1 - p) * (1 - p) * 0.30;
      if (alpha <= 0.004) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color || oldDelegate.base != base;
}
