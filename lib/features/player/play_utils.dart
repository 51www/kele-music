import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// 统一播放入口：把队列交给 audio handler，由 handler 通过注入的
/// urlResolver 解析音源并播放（含队列内自动切歌）。
///
/// 单曲播放：await playSong(ref, song);
/// 队列播放：await playQueue(ref, songs, index);
Future<void> playSong(WidgetRef ref, Song song) =>
    playQueue(ref, [song], 0);

/// 以 [songs] 为播放队列播放 [index] 处的曲目。
/// 音源为空等业务错误以异常抛出，由调用方提示。
Future<void> playQueue(WidgetRef ref, List<Song> songs, int index) async {
  final handler = ref.read(audioHandlerProvider);
  await handler.playQueue(songs, index);
}

/// 点击歌曲/歌单的统一入口：**立即跳转播放页**，音源解析与加载
/// 在后台进行（不再让用户在列表页干等）。起播失败以轻提示告知，
/// 播放页保持暂停态并展示错误原因。
Future<void> playAndOpen(WidgetRef ref, BuildContext context,
    List<Song> songs, int index) async {
  ref.read(playStartErrorProvider.notifier).state = null;
  context.push('/now-playing');
  try {
    await playQueue(ref, songs, index);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.userMessage : '播放失败，请稍后重试'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }
}

void _edgeToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 1200),
  ));
}

/// 下一曲（带边界提示）：已在队列末尾时轻提示"没有下一曲了"。
Future<void> skipNext(WidgetRef ref, BuildContext context) async {
  bool ok;
  try {
    ok = await ref.read(audioHandlerProvider).skipToNext();
  } catch (_) {
    // 切歌异常已在 handler 内部兜底；这里再兜一层，防 release 闪退。
    return;
  }
  if (!ok && context.mounted) _edgeToast(context, '没有下一曲了');
}

/// 上一曲（带边界提示）：队首且播放不足 3 秒时轻提示"没有上一曲了"。
Future<void> skipPrevious(WidgetRef ref, BuildContext context) async {
  bool ok;
  try {
    ok = await ref.read(audioHandlerProvider).skipToPrevious();
  } catch (_) {
    return;
  }
  if (!ok && context.mounted) _edgeToast(context, '没有上一曲了');
}
