// 收听时长展示单位的边界回归：分钟 / 小时 / 天三档阈值与整数截断。
// 运行：flutter test test/listen_duration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kele_music_client/data/listen_stats.dart';

void main() {
  group('收听时长展示单位', () {
    test('不超过 60 分钟仍按分钟', () {
      expect(formatListenMinutes(0).compact, '0分钟');
      expect(formatListenDuration(47 * 60).compact, '47分钟');
      expect(formatListenMinutes(60).compact, '60分钟');
    });

    test('超过 60 分钟按小时，不足 1 小时舍去', () {
      expect(formatListenMinutes(79).compact, '1小时');
      expect(formatListenDuration(79 * 60).compact, '1小时');
      expect(formatListenMinutes(119).compact, '1小时');
      expect(formatListenMinutes(120).compact, '2小时');
      expect(formatListenMinutes(20 * 60).compact, '20小时');
    });

    test('超过 24 小时按天，不足 1 天舍去', () {
      expect(formatListenMinutes(24 * 60).compact, '24小时');
      expect(formatListenMinutes(30 * 60).compact, '1天');
      expect(formatListenDuration(30 * 60 * 60).compact, '1天');
      expect(formatListenMinutes(49 * 60).compact, '2天');
    });

    test('大字与单位可拆分展示，整句保留空格语感', () {
      final d = formatListenDuration(79 * 60);
      expect(d.value, 1);
      expect(d.unit, ListenDurationUnit.hours);
      expect(d.unitLabel, '小时');
      expect(d.spaced, '1 小时');
    });

    test('异常负值按 0 分钟兜底', () {
      expect(formatListenMinutes(-30).compact, '0分钟');
    });
  });
}
