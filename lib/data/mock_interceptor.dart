import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Mock 拦截器：`--dart-define=USE_MOCK=1` 时启用。
///
/// 启用后所有请求不再出网（含 QR 登录全流程、短信登录、签到），
/// 由本地返回与真实接口同构的 JSON——日常开发/调试零风控风险。
/// 数据形状严格对齐 NcmApi 各类型化端点的解析逻辑（见 data/models.dart）。
class MockInterceptor extends Interceptor {
  static const bool enabled = bool.fromEnvironment('USE_MOCK');

  /// QR 轮询状态机计数：第 1 次「等待」，第 2 次「已扫」，第 3 次起「成功」，
  /// 可离线走完整个登录链路（801 → 802 → 803）。
  int _qrPolls = 0;

  // ---- 云端收藏 mock 状态（对应平台 /like 与 /playlist/subscribe） ----
  /// 已喜欢的歌曲 id（初始喜欢第 1 首，便于验证列表非空）。
  final Set<int> _likedIds = {900001};

  /// 已收藏的歌单 id（初始收藏 2002，验证收藏 Tab 非空）。
  final Set<int> _subscribedIds = {2002};

  // ---- 创建歌单 mock 状态（对应 /playlist/create 等增删改接口） ----
  int _createdSeq = 0;
  final List<Map<String, dynamic>> _createdExtra = [];

  /// 1x1 灰色 PNG（base64）：_decodeQr 只做 base64 → bytes 展示，合法 PNG 即可。
  static const String _qrPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // 模拟网络延迟，让 loading 态可复现。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      final data = _resolve(options);
      handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options, data: data, statusCode: 200));
    } catch (e) {
      debugPrint('[MockInterceptor] unmatched: ${options.path} ($e)');
      handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          data: <String, dynamic>{
            'code': 200,
            'mock': true,
            'message': 'mock 未覆盖该接口: ${options.path}'
          },
          statusCode: 200));
    }
  }

  Map<String, dynamic> _resolve(RequestOptions o) {
    final path = o.path;
    final q = o.queryParameters;

    // ---- 登录相关（优先匹配长路径） ----
    if (path.startsWith('/login/qr/check')) {
      _qrPolls++;
      if (_qrPolls >= 3) {
        return {
          'code': 803,
          'cookie': 'MUSIC_U=mock_cookie_uid_1; os=pc',
        };
      }
      if (_qrPolls == 2) return {'code': 802};
      return {'code': 801};
    }
    if (path.startsWith('/login/qr/create')) {
      return {
        'code': 200,
        'data': {
          'qrurl': 'https://music.163.com/login?codekey=mock',
          'qrimg': 'data:image/png;base64,$_qrPng'
        }
      };
    }
    if (path.startsWith('/login/qr/key')) {
      return {
        'code': 200,
        'data': {'code': 200, 'unikey': 'mock-unikey'}
      };
    }
    if (path.startsWith('/login/cellphone')) {
      return {'code': 200, 'cookie': 'MUSIC_U=mock_cookie_uid_1'};
    }
    if (path.startsWith('/login/refresh') || path.startsWith('/login/status')) {
      return {'code': 200};
    }
    if (path.startsWith('/captcha/')) return {'code': 200};

    // ---- 登录态相关 ----
    if (path.startsWith('/logout')) return {'code': 200};
    if (path.startsWith('/daily_signin')) {
      return {'code': 200, 'point': 1};
    }
    if (path.startsWith('/user/account')) {
      // cookie 参数存在（NcmApi._params 注入）视为已登录。
      final cookie = q['cookie']?.toString();
      if (cookie == null || cookie.isEmpty)
        return {'code': 200, 'profile': null};
      return {
        'code': 200,
        'profile': {'userId': 1, 'nickname': 'Mock 用户', 'avatarUrl': ''}
      };
    }
    if (path.startsWith('/user/playlist')) {
      // userId/creator 区分创建者：1 = Mock 用户（创建），2 = 他人（收藏）。
      // 收藏歌单由 _subscribedIds 动态生成，订阅/取订立即反映到列表；
      // 1001 标记 specialType=5（「我喜欢的音乐」），创建的歌单放最前。
      return {
        'code': 200,
        'playlist': [
          for (final p in _createdExtra) p,
          _playlist(1001, 'Mock 我喜欢的音乐',
              trackCount: _likedIds.length, specialType: 5),
          _playlist(1002, 'Mock 日常创作', trackCount: 3),
          for (final id in _subscribedIds)
            _playlist(id, 'Mock 收藏歌单 $id', trackCount: 5, userId: 2),
        ]
      };
    }

    // ---- 云端收藏（喜欢歌曲 / 收藏歌单） ----
    // 注意顺序：/likelist 必须先于 /like 匹配（前缀包含关系）。
    if (path.startsWith('/likelist')) {
      return {
        'code': 200,
        'ids': _likedIds.toList(),
        'checkFlag': 0,
      };
    }
    if (path.startsWith('/like')) {
      final id = int.tryParse('${q['id'] ?? ''}') ?? 0;
      final like = '${q['like']}'.toLowerCase() == 'true';
      like ? _likedIds.add(id) : _likedIds.remove(id);
      return {'code': 200, 'playlistId': 1001, 'threads': []};
    }
    if (path.startsWith('/song/detail')) {
      final ids =
          '${q['ids'] ?? ''}'.split(',').where((e) => e.isNotEmpty).toSet();
      return {
        'code': 200,
        'songs': _songs.where((s) => ids.contains('${s['id']}')).toList(),
        'privileges': [],
      };
    }
    if (path.startsWith('/playlist/subscribe')) {
      final id = int.tryParse('${q['id'] ?? ''}') ?? 0;
      final t = int.tryParse('${q['t'] ?? ''}') ?? 0;
      // 与真实接口同构的业务码：502=已收藏过，501=未收藏过。
      if (id == 0 || t == 0) return {'code': 400, 'message': '请求参数错误'};
      if (t == 1 && _subscribedIds.contains(id)) return {'code': 502};
      if (t == 2 && !_subscribedIds.contains(id)) return {'code': 501};
      t == 1 ? _subscribedIds.add(id) : _subscribedIds.remove(id);
      return {'code': 200};
    }

    // ---- 创建歌单增删改（需登录端点，mock 里直接改内存状态） ----
    if (path.startsWith('/playlist/create')) {
      final name = '${q['name'] ?? '新建歌单'}';
      final id = 1100 + (++_createdSeq);
      final p = _playlist(id, name, trackCount: 0);
      _createdExtra.insert(0, p);
      return {'code': 200, 'id': id, 'playlist': p};
    }
    if (path.startsWith('/playlist/delete')) {
      final id = int.tryParse('${q['id'] ?? ''}') ?? 0;
      _createdExtra.removeWhere((p) => p['id'] == id);
      return {'code': 200};
    }
    if (path.startsWith('/playlist/name/update')) {
      final id = int.tryParse('${q['id'] ?? ''}') ?? 0;
      final name = '${q['name'] ?? ''}';
      for (final p in _createdExtra) {
        if (p['id'] == id) p['name'] = name;
      }
      return {'code': 200};
    }
    if (path.startsWith('/playlist/tracks')) {
      final pid = int.tryParse('${q['pid'] ?? ''}') ?? 0;
      final op = '${q['op'] ?? ''}';
      final n =
          '${q['tracks'] ?? ''}'.split(',').where((e) => e.isNotEmpty).length;
      for (final p in _createdExtra) {
        if (p['id'] == pid) {
          final cur = (p['trackCount'] as int?) ?? 0;
          p['trackCount'] = op == 'add' ? cur + n : (cur - n).clamp(0, cur);
        }
      }
      return {
        'code': 200,
        'body': {'code': 200}
      };
    }

    // ---- 内容类 ----
    if (path.startsWith('/personalized/newsong')) {
      return {
        'code': 200,
        'result': [
          for (final s in _songs.take(6))
            {'id': s['id'], 'name': s['name'], 'picUrl': '', 'song': s}
        ]
      };
    }
    if (path.startsWith('/personalized')) {
      return {
        'code': 200,
        'result': [
          _playlist(2001, 'Mock 每日精选'),
          _playlist(2002, 'Mock 晚安电台'),
          _playlist(2003, 'Mock 蔬菜批发 BGM'),
        ]
      };
    }
    if (path.startsWith('/toplist')) {
      return {
        'code': 200,
        'list': [
          {
            'id': 3001,
            'name': 'Mock 飙升榜',
            'coverImgUrl': '',
            'updateFrequency': '每 日'
          },
          {
            'id': 3002,
            'name': 'Mock 热歌榜',
            'coverImgUrl': '',
            'updateFrequency': '每 周'
          },
        ]
      };
    }
    if (path.startsWith('/search/hot/detail')) {
      return {
        'code': 200,
        'data': [
          for (final w in ['mock 热搜', '蔬菜批发', '黑胶VIP', '测试关键词'])
            {'searchWord': w}
        ]
      };
    }
    // /cloudsearch（新搜索接口）与旧 /search 同构，共用同一份 mock 歌曲。
    if (path.startsWith('/cloudsearch') || path.startsWith('/search')) {
      return {
        'code': 200,
        'result': {'songs': _songs}
      };
    }
    if (path.startsWith('/playlist/detail')) {
      return {
        'code': 200,
        'playlist': {
          ..._playlist(2001, 'Mock 每日精选', trackCount: _songs.length),
          'tracks': _songs,
        }
      };
    }
    // ---- 专辑详情（/album）：与真实接口同构，曲目复用 _songs ----
    if (path.startsWith('/album')) {
      final id = int.tryParse('${q['id'] ?? ''}') ?? 0;
      final n = id > 0 ? ((id - 1) % 4) + 1 : 1;
      return {
        'code': 200,
        'album': {
          'id': id,
          'name': 'Mock 专辑 $n',
          'picUrl': '',
          'artist': {'name': 'Mock 歌手 1'},
          'company': '可乐唱片',
          'description':
              '一张用于离线开发演示的虚拟专辑，收录 ${_songs.length} 首曲目。曲目序号与整轨收听流程都可在这里验证。',
          'publishTime': 1704067200000, // 2024-01-01
          'size': _songs.length,
          'subType': '录音室专辑',
          'type': '专辑',
        },
        'songs': _songs,
      };
    }
    if (path.startsWith('/song/url')) {
      // 指向 web/ 下自带的 30s 静音 WAV（相对路径按页面 origin 解析），
      // mock 模式下可真实起播 → 完整走通播放态 UI（水波纹动效）。
      return {
        'code': 200,
        'data': [
          {'id': (q['id'] ?? 0).toString(), 'url': 'mock_silence.wav'}
        ]
      };
    }
    if (path.startsWith('/lyric')) {
      return {
        'code': 200,
        'lrc': {'lyric': '[00:00.00]Mock 歌词（离线开发模式）\n[00:02.00]第二行测试文本'},
        'tlyric': {'lyric': ''}
      };
    }
    if (path.startsWith('/banner')) {
      return {
        'code': 200,
        'banners': [
          {
            'imageUrl': '',
            'title': 'Mock Banner',
            'typeTitle': '离线模式',
            'url': ''
          }
        ]
      };
    }
    // ---- 歌曲评论（/comment/music，与真实接口同构） ----
    if (path.startsWith('/comment/music')) {
      final id = int.tryParse('${q['id'] ?? 0}') ?? 0;
      final limit = int.tryParse('${q['limit'] ?? 20}') ?? 20;
      final offset = int.tryParse('${q['offset'] ?? 0}') ?? 0;
      final all = _commentsFor(id);
      final total = all.length;
      final slice = all.skip(offset).take(limit).toList();
      // 热门取前 5 条（与 offset 无关，每次都给，对齐真实 hotComments 行为）；
      // 最新按 offset/limit 切片，more 由是否还有余量决定。
      final hot = all.take(5).toList();
      final more = offset + slice.length < total;
      return {
        'code': 200,
        'total': total,
        'hotComments': hot,
        'comments': slice,
        'more': more,
        'moreHot': false,
      };
    }
    throw UnimplementedError(path);
  }

  static Map<String, dynamic> _playlist(int id, String name,
      {int trackCount = 0, int userId = 1, int specialType = 0}) {
    return {
      'id': id,
      'name': name,
      'coverImgUrl': '',
      'trackCount': trackCount,
      'playCount': 1000 + id,
      'userId': userId,
      if (specialType != 0) 'specialType': specialType,
      'creator': {
        'userId': userId,
        'nickname': userId == 1 ? 'Mock 用户' : 'Mock 其他用户',
      },
    };
  }

  static final List<Map<String, dynamic>> _songs = [
    for (int i = 1; i <= 8; i++)
      {
        'id': 900000 + i,
        'name': 'Mock 歌曲 $i',
        'artists': [
          {'id': i, 'name': 'Mock 歌手 ${i % 3 + 1}'}
        ],
        'album': {'id': i, 'name': 'Mock 专辑 ${i % 4 + 1}', 'picUrl': ''},
        'duration': 180000 + i * 1000,
        'fee': i == 2 ? 1 : 0, // 第 2 首带 VIP 标，覆盖角标 UI
      }
  ];

  /// 按歌曲 id 确定性生成一批假评论（离线演示用）：头像留空走占位图，
  /// 文案/昵称循环复用固定池，点赞数与回复数随下标变化，便于验证列表与
  /// 分页。返回顺序即「最新」倒序（下标越大越新）。
  static List<Map<String, dynamic>> _commentsFor(int id) {
    const nicks = [
      '深夜电台',
      '黑胶收藏家',
      '乐迷小柯',
      '通勤BGM',
      '副歌循环机',
      '钢琴边的猫',
      '失真效果器',
      '晚风散步',
      '母带工程师',
      '耳机发烧友',
    ];
    const texts = [
      '前奏一响就起鸡皮疙瘩，这首歌真的封神。',
      '单曲循环第三天，越听越上头。',
      '间奏的编曲太顶了，制作很用心。',
      '深夜听到这句歌词直接破防。',
      '当年这首歌陪我熬过很多个夜晚。',
      '副歌一出来整个人都松弛下来了。',
      '求问这是什么乐器？音色太特别了。',
      '现场版比录音室还炸，循环ing。',
      '第一次听就加到我喜欢的音乐了。',
      '评论区比歌词还精彩，哈哈。',
    ];
    const count = 30;
    final base = id * 1000;
    return [
      for (int i = 0; i < count; i++)
        {
          'commentId': base + i,
          'user': {
            'userId': 1000 + i,
            'nickname': nicks[i % nicks.length],
            'avatarUrl': '',
          },
          'content': texts[i % texts.length],
          // 时间随下标递减（下标大 = 更新），用于「最新」倒序展示。
          'time': 1710000000000 - i * 3600 * 1000,
          'likedCount': (i * 37) % 999,
          'replyCount': (i * 13) % 80,
        }
    ];
  }
}
