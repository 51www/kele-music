import 'package:flutter_riverpod/flutter_riverpod.dart';
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
