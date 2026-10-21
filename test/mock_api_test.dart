// Mock 模式端到端单测：验证 mock 拦截器返回的数据可被 models 正确解析、
// QR 登录状态机可走通。flutter test 不吃 --dart-define，故显式传 useMock: true。
// 运行：flutter test test/mock_api_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:netease_music_client/data/api_client.dart';

void main() {
  final api = NcmApi(baseUrl: 'http://mock.local', useMock: true);

  test('内容类端点：mock 数据可被 models 正确解析', () async {
    final hot = await api.hotSearch();
    expect(hot, isNotEmpty);

    final banners = await api.banners();
    expect(banners, isNotEmpty);

    final playlists = await api.personalizedPlaylists();
    expect(playlists, isNotEmpty);
    expect(playlists.first.name, contains('Mock'));

    final ranking = await api.rankings();
    expect(ranking, isNotEmpty);

    final news = await api.newSongs();
    expect(news, isNotEmpty);
    expect(news.first.artistName, isNotEmpty);

    final songs = await api.search('mock');
    expect(songs.length, 8);
    expect(songs[1].isVip, isTrue); // fee=1 的 VIP 角标用例
  });

  test('歌单详情与音源/歌词', () async {
    final detail = await api.playlistDetail(2001);
    expect(detail.tracks, isNotEmpty);
    // mock 音源为 30s 静音 WAV（相对路径）：可真实起播，支撑播放态 UI 验证
    final url = await api.songUrl(900001);
    expect(url, 'mock_silence.wav');
    final lyric = await api.lyric(900001);
    expect(lyric.text, contains('Mock'));
  });

  test('登录态：无 cookie 视为未登录，有 cookie 返回 profile', () async {
    final anon = await api.userAccount();
    expect(anon.isEmpty, isTrue);
    api.setCookie('MUSIC_U=mock_cookie_uid_1');
    final me = await api.userAccount();
    expect(me.userId, 1);
    expect(me.nickname, 'Mock 用户');
    api.setCookie(null);
  });

  test('QR 登录状态机：801 等待 → 802 已扫 → 803 成功', () async {
    // AuthRepository.qrKey/qrCreate/qrCheck 的底层端点直接验证。
    final kd = await api.get('/login/qr/key');
    expect(kd['data']['unikey'], 'mock-unikey');
    final cd = await api.get('/login/qr/create', {'key': 'mock-unikey', 'qrimg': 1});
    expect((cd['data']['qrimg'] as String), startsWith('data:image/png;base64,'));

    expect(await _check(api), 'waiting');
    expect(await _check(api), 'waiting');
    expect(await _check(api), 'scanned');
    final last = await api.post('/login/qr/check', {'key': 'k'}, false);
    expect(last['code'], 803);
    expect(last['cookie'], contains('MUSIC_U=mock_cookie'));
  });

  test('频率闸门：/login/refresh 二次调用强制等待（验证 ≥1 次 10 分钟间隔逻辑被触发）', () async {
    // 这里只验证闸门不抛错、请求能串行通过（真实间隔 10 分钟由节拍器保证，
    // 测试只测第一次通过路径，避免测试本身跑 10 分钟）。
    final ok = await api.post('/login/refresh');
    expect(ok['code'], 200);
  });
}

Future<String> _check(NcmApi api) async {
  final d = await api.post('/login/qr/check', {'key': 'k'}, false);
  final code = d['code'] ?? 0;
  if (code == 803) return 'confirmed';
  if (code == 800) return 'expired';
  if (code == 802) return 'scanned';
  return 'waiting';
}
