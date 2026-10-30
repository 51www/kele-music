/// 收听统计的本地数据模型与聚合口径。
///
/// 设计取舍：
/// - **只存「按天」的最小事实**（当天累计秒数 / 起播次数 / 当天听过的曲目 id），
///   周、月、累计等口径一律在读取时由日数据推导。这样存储体量与使用时长无关
///   （每天一行），改口径时也不用迁移历史数据。
/// - 日期键用本地时区的 `yyyy-MM-dd`：收听行为天然按「用户的一天」划分，
///   跨时区旅行时以当前设备时区为准，不做 UTC 换算。
/// - 曲目 id 只用于明细里的「首数」与去重，保留上限见 [DayListen.maxSongs]。
library;

/// 一天的收听事实。
class DayListen {
  /// 当天累计收听秒数（只有真正在播的时长会计入）。
  final int seconds;

  /// 当天起播次数（同一首重复播放也计数）。
  final int plays;

  /// 当天听过的曲目 id（去重，明细页展示「N 首」）。
  final Set<int> songIds;

  const DayListen({
    required this.seconds,
    required this.plays,
    required this.songIds,
  });

  /// 单日保留的曲目 id 上限：一天的收听量远小于此，超限只截断 id 列表，
  /// 不影响时长与次数（避免异常数据把本地存储撑大）。
  static const int maxSongs = 300;

  static const DayListen empty = DayListen(seconds: 0, plays: 0, songIds: {});

  bool get isEmpty => seconds == 0 && plays == 0 && songIds.isEmpty;

  DayListen addSeconds(int delta) => DayListen(
        seconds: seconds + delta,
        plays: plays,
        songIds: songIds,
      );

  DayListen addSong(int songId) => DayListen(
        seconds: seconds,
        plays: plays + 1,
        songIds: songIds.length >= maxSongs || songIds.contains(songId)
            ? songIds
            : {...songIds, songId},
      );

  Map<String, dynamic> toJson() => {
        'sec': seconds,
        'plays': plays,
        'ids': songIds.toList(),
      };

  factory DayListen.fromJson(Map<String, dynamic> j) => DayListen(
        seconds: (j['sec'] as num?)?.toInt() ?? 0,
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        songIds: {
          for (final id in (j['ids'] as List? ?? const []))
            if (id is num) id.toInt(),
        },
      );
}

/// 图表 / 明细列表的一行：某天的聚合值。
class DayPoint {
  final DateTime date;
  final int seconds;
  final int plays;
  final int songCount;
  const DayPoint({
    required this.date,
    required this.seconds,
    required this.plays,
    required this.songCount,
  });
}

/// 收听统计快照（不可变，供 Riverpod 直接比对重建）。
class ListenStats {
  /// 日期键（yyyy-MM-dd）→ 当天事实；已按 [maxDays] 裁剪。
  final Map<String, DayListen> days;

  final DateTime _now;

  const ListenStats._(this.days, this._now);

  /// 保留天数：够看「本月 / 近 30 天 / 年度回顾」，再久的记录没有展示位。
  static const int maxDays = 366;

  /// 空快照；[now] 仅测试用，业务侧一律传 null 取自系统时钟。
  factory ListenStats.empty([DateTime? now]) =>
      ListenStats._(const {}, now ?? DateTime.now());

  /// 由已解析的日数据构建（顺序无关）。
  factory ListenStats.fromDays(Map<String, DayListen> days,
      {DateTime? now}) {
    final n = now ?? DateTime.now();
    final sorted = days.keys.toList()..sort();
    final keep = sorted.length <= maxDays
        ? sorted
        : sorted.sublist(sorted.length - maxDays);
    return ListenStats._(
      {for (final k in keep) k: days[k]!},
      n,
    );
  }

  /// 读取某天事实（无记录返回 [DayListen.empty]）。
  DayListen dayOf(DateTime d) => days[dayKey(d)] ?? DayListen.empty;

  int secondsOf(DateTime d) => dayOf(d).seconds;

  DateTime get today {
    final n = _now;
    return DateTime(n.year, n.month, n.day);
  }

  int get todaySeconds => secondsOf(today);

  int get yesterdaySeconds =>
      secondsOf(today.subtract(const Duration(days: 1)));

  /// 本周（周一 00:00 起，本地时区）累计秒数。
  int get weekSeconds {
    final start = today.subtract(Duration(days: today.weekday - 1));
    return _sumFrom(start);
  }

  /// 本月（1 号 00:00 起）累计秒数。
  int get monthSeconds => _sumFrom(DateTime(today.year, today.month, 1));

  /// 全部历史累计秒数。
  int get totalSeconds =>
      days.values.fold(0, (sum, d) => sum + d.seconds);

  /// 有收听记录的天数（累计口径，展示「坚持了多久」）。
  int get activeDays => days.values.where((d) => d.seconds > 0).length;

  /// 本月有记录的天数。
  int get monthActiveDays {
    final prefix = '${_now.year}-${_pad(_now.month)}';
    return days.entries
        .where((e) => e.key.startsWith(prefix) && e.value.seconds > 0)
        .length;
  }

  /// 本周日均秒数：分母是「本周已过去的天数」（含今天），
  /// 也就是周一当天看到的就是当天值，不会因为周中而被稀释成 1/7。
  int get weekDailyAverageSeconds {
    final elapsed = today.weekday; // 周一=1 … 周日=7
    return (weekSeconds / elapsed).round();
  }

  /// 最近 [n] 天（含今天）的逐日聚合，按时间升序返回，缺失日期补 0。
  List<DayPoint> recentDays(int n) {
    final list = <DayPoint>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final v = dayOf(d);
      list.add(DayPoint(
        date: d,
        seconds: v.seconds,
        plays: v.plays,
        songCount: v.songIds.length,
      ));
    }
    return list;
  }

  /// 最近 [n] 天里有记录的天，最新在前（明细列表用）。
  List<DayPoint> recordedDays(int n) {
    return recentDays(n).where((p) => p.seconds > 0).toList().reversed
        .toList();
  }

  int _sumFrom(DateTime start) => _range(start, today)
      .fold(0, (sum, d) => sum + secondsOf(d));

  /// [start]~[end] 的逐日序列（含两端，最多 [maxDays] 天）。
  Iterable<DateTime> _range(DateTime start, DateTime end) sync* {
    var cur = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    var guard = 0;
    while (!cur.isAfter(last) && guard++ <= maxDays) {
      yield cur;
      cur = cur.add(const Duration(days: 1));
    }
  }
}

/// 本地日期键（yyyy-MM-dd）。
String dayKey(DateTime d) =>
    '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

String _pad(int v) => v.toString().padLeft(2, '0');

/// 秒 → 展示用分钟（四舍五入到整分钟；统计口径统一为分钟）。
int listenMinutes(int seconds) => (seconds / 60).round();

/// 星期几（周一 … 周日）。
const List<String> kWeekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayLabel(DateTime d) => kWeekdayLabels[d.weekday - 1];

/// 相对日期文案：今天 / 昨天 / M月d日。
String dayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final target = DateTime(d.year, d.month, d.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (target.year == today.year) return '${target.month}月${target.day}日';
  return '${target.year}年${target.month}月${target.day}日';
}
