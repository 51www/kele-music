import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      child: SafeArea(
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
                                playing: playing)),
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
                      IconButton(
                        iconSize: 40,
                        icon: Icon(Icons.skip_previous, color: style.textPrimary),
                        onPressed: () => play.skipPrevious(ref, context),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 56,
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: style.textPrimary),
                        onPressed: () => playing ? handler.pause() : handler.play(),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 40,
                        icon: Icon(Icons.skip_next, color: style.textPrimary),
                        onPressed: () => play.skipNext(ref, context),
                      ),
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
      final url = await ref.read(apiProvider).songUrl(song.id);
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

/// 播放页封面：三种展示形态；播放中慢速旋转（12s/圈），暂停即停；
/// 图片未加载/加载失败时显示默认封面（不再露黑块）。
class _AlbumArt extends StatefulWidget {
  final AppStyle style;
  final Uri? artUri;
  final bool playing;
  const _AlbumArt(
      {required this.style, required this.artUri, required this.playing});

  @override
  State<_AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<_AlbumArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _AlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      widget.playing ? _spin.repeat() : _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

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

    switch (style.albumPresentation) {
      case AlbumPresentation.vinyl:
        return RotationTransition(
          turns: _spin,
          child: Container(
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
        );
      case AlbumPresentation.card:
        return RotationTransition(
          turns: _spin,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(style.cardRadius),
            child: SizedBox(width: 240, height: 240, child: img),
          ),
        );
      case AlbumPresentation.blurred:
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: SafeNetworkImage(url: url),
              ),
            ),
            RotationTransition(
              turns: _spin,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 200, height: 200, child: img),
              ),
            ),
          ],
        );
    }
  }
}
