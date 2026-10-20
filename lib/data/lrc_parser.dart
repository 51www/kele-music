// LRC 歌词解析：把 [mm:ss.xx]文本 格式解析成带时间轴的行，供歌词视图同步高亮。

/// 一行歌词：时间戳 + 文本。
class LrcLine {
  final Duration time;
  final String text;
  const LrcLine(this.time, this.text);
}

/// 解析后的歌词数据：主歌词行（按时间升序）+ 翻译行。
class LyricData {
  final List<LrcLine> lines;
  final List<LrcLine> trans;
  const LyricData(this.lines, this.trans);
  bool get isEmpty => lines.isEmpty;

  /// 按时间戳查找某行的翻译（tlyric 与主歌词时间戳通常一致）。
  String? transFor(Duration time) {
    for (final t in trans) {
      if (t.time == time) return t.text;
    }
    return null;
  }
}

final _lrcTagRegex = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// 解析 LRC 文本。非法/无时间戳行忽略；一行可带多个时间戳（展开成多行）。
List<LrcLine> parseLrc(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <LrcLine>[];
  for (final line in raw.split('\n')) {
    final matches = _lrcTagRegex.allMatches(line);
    if (matches.isEmpty) continue;
    final text = line.replaceAll(_lrcTagRegex, '').trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final mm = int.parse(m.group(1)!);
      final ss = int.parse(m.group(2)!);
      final frac = m.group(3);
      // 百分之一/千分之一秒统一归一为毫秒。
      final ms = frac == null
          ? 0
          : int.parse(frac.padRight(3, '0').substring(0, 3));
      out.add(LrcLine(
        Duration(minutes: mm, seconds: ss, milliseconds: ms),
        text,
      ));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// 二分查找当前播放进度对应的歌词行下标（无任何行已开始时返回 -1）。
int currentLrcIndex(List<LrcLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= position) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
