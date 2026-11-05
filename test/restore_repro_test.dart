// 复现测试：「断点续听恢复后点播放条无法播放」。
//
// 用真实 NcmAudioHandler + fake just_audio 平台层，模拟真机冷启动场景：
//   会话1：播放队列两首歌（模拟昨天退出 App 前的现场）；
//   会话2：新 handler（模拟进程被杀后冷启动）→ restoreQueue 恢复为暂停态
//          → 用户点击播放条的 ▶（handler.play()）。
// 验证 Dart 状态机在恢复成功 / 恢复失败重试 / 恢复在飞等待接管 /
// 平台层错误自愈等情况下能否正常起播（修复后为回归测试）。
//
// 运行：flutter test test/restore_repro_test.dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:kele_music_client/core/errors.dart';
import 'package:kele_music_client/data/models.dart';
import 'package:kele_music_client/data/player_repository.dart';

// ---------------------------------------------------------------------------
// fake just_audio 平台层：记录平台调用，可模拟加载成功/失败。
// ---------------------------------------------------------------------------

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  final eventController = StreamController<PlaybackEventMessage>.broadcast();

  /// 平台调用记录（供断言）。
  final playRequests = <PlayRequest>[];
  final pauseRequests = <PauseRequest>[];
  final seekRequests = <SeekRequest>[];
  final loadRequests = <LoadRequest>[];

  /// 本实例 setUrl 是否抛异常（模拟直链加载失败）：剩余失败次数。
  int failLoads = 0;

  /// 所属平台（平台级失败计数用）。
  FakeJustAudioPlatform? owner;

  /// play() 是否抛异常（模拟 ExoPlayer 错误）。
  bool failPlay = false;

  /// 模拟「播放器对象失效」（ColorOS 长时间冻结/回收音频引擎）：
  /// play() 的 Future 永不完成，且平台已回收解码器（广播 idle）。
  /// 对应真机上「点播放毫无反应、只能拖进度条或杀进程」的状态。
  bool frozen = false;

  /// 是否模拟真实 just_audio play() 语义：Future 挂起直到 pause()/stop()
  /// 才完成（0.9.x 官方语义「completes when the playback completes or is
  /// paused or stopped」）。默认 false（立即完成）保持既有场景行为。
  bool holdPlayUntilPause = false;
  Completer<PlayResponse>? _pendingPlay;

  Duration duration = const Duration(minutes: 3);
  Duration position = Duration.zero;
  bool _ready = false;

  FakeAudioPlayerPlatform(super.id);

  void _emitReady() {
    _ready = true;
    eventController.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition: duration,
      duration: duration,
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
  }

  /// 模拟一首播完：广播 completed 事件（just_audio 语义下 playing 仍为 true）。
  void emitCompleted() {
    position = duration;
    eventController.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.completed,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition: duration,
      duration: duration,
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loadRequests.add(request);
    if (failLoads > 0) {
      failLoads--;
      throw Exception('simulated load failure (expired/dead url)');
    }
    if (owner != null && owner!.failNextLoads > 0) {
      owner!.failNextLoads--;
      throw Exception('simulated load failure (platform-level)');
    }
    position = request.initialPosition ?? Duration.zero;
    _emitReady();
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playRequests.add(request);
    if (frozen) {
      // 引擎已被系统回收：平台层不再推进播放，只上报 idle；Future 永不完成。
      _ready = false;
      eventController.add(PlaybackEventMessage(
        processingState: ProcessingStateMessage.idle,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: position,
        duration: duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ));
      return Completer<PlayResponse>().future;
    }
    if (failPlay) {
      failPlay = false;
      throw Exception('simulated exoplayer error');
    }
    _emitReady();
    if (holdPlayUntilPause) {
      // 真实语义：本次 play 的 Future 挂起，直到下一次 pause 才完成。
      _pendingPlay?.complete(PlayResponse());
      final c = Completer<PlayResponse>();
      _pendingPlay = c;
      return c.future;
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    pauseRequests.add(request);
    _pendingPlay?.complete(PlayResponse());
    _pendingPlay = null;
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    seekRequests.add(request);
    position = request.position ?? Duration.zero;
    if (_ready) _emitReady();
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
                  request) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await eventController.close();
    return DisposeResponse();
  }
}

class FakeJustAudioPlatform extends JustAudioPlatform {
  final players = <String, FakeAudioPlayerPlatform>{};

  /// 平台级「接下来 N 次 load 失败」计数：just_audio 每次 setUrl 激活
  /// 可能重新 init 平台播放器，按实例注入会被新实例绕过。
  int failNextLoads = 0;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final p = FakeAudioPlayerPlatform(request.id)..owner = this;
    players[request.id] = p;
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse();
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

const Song songA = Song(
  id: 101,
  name: '歌曲A',
  artists: [],
  album: Album(id: 1, name: '专辑', picUrl: ''),
  duration: 180000,
  fee: 0,
);
const Song songB = Song(
  id: 102,
  name: '歌曲B',
  artists: [],
  album: Album(id: 1, name: '专辑', picUrl: ''),
  duration: 200000,
  fee: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // audio_session 在测试宿主（macOS）上 Platform.isAndroid=false，
  // setActive 会直接返回 true；getConfiguration 走通道需 mock 掉避免报错。
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sessionChannel, (call) async => null);

  late FakeJustAudioPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
  });

  test('场景1：恢复成功后点播放 ▶ → 应正常起播', () async {
    final playedUrls = <int, String>{};
    Future<String?> resolver(int id) async {
      playedUrls[id] = 'https://cdn.example.com/$id.mp3';
      return playedUrls[id];
    }

    // ---- 会话1（昨天）：播队列两首，播到第二首后退出 ----
    final h1 = NcmAudioHandler()..urlResolver = resolver;
    await h1.playQueue([songA, songB], 0);
    expect(h1.isPlaying, isTrue, reason: '会话1起播应成功');
    await h1.skipToNext(); // 切到第二首
    await h1.pause(); // 用户暂停后退出（或直接划掉 App）
    expect(h1.isPlaying, isFalse);

    // ---- 会话2（今天冷启动）：新 handler = 新进程新播放器 ----
    final h2 = NcmAudioHandler()..urlResolver = resolver;
    await h2.restoreQueue([songA, songB], 1, const Duration(seconds: 66));

    expect(h2.queueIndex, 1, reason: '应恢复到第二首');
    expect(h2.loadedSongId, songB.id, reason: '恢复装载应成功');
    expect(h2.isPlaying, isFalse, reason: '恢复为暂停态');

    // ---- 用户点播放条 ▶ ----
    await h2.play();
    // PlayRequest 由 handler 以 fire-and-forget 方式发出（不 await play()，
    // 避免 Web 平台 Future 不完成卡住导航），需让一个事件循环轮次跑完。
    await Future<void>.delayed(Duration.zero);

    final platform = fakePlatform.players.values.last;
    expect(platform.playRequests.length, 1,
        reason: '点播放后应向平台层发出 PlayRequest');
    expect(h2.isPlaying, isTrue, reason: '播放状态应为 playing');
  });

  test('场景2：恢复时音源解析失败 → 点播放 ▶ 应自动重试起播', () async {
    var failOnce = true;
    Future<String?> resolver(int id) async {
      if (failOnce) {
        failOnce = false;
        return null; // 模拟冷启动瞬间网络/接口失败
      }
      return 'https://cdn.example.com/$id.mp3';
    }

    final h2 = NcmAudioHandler()..urlResolver = resolver;
    await h2.restoreQueue([songA, songB], 1, const Duration(seconds: 30));
    expect(h2.loadedSongId, isNull, reason: '解析失败时音源未装载');

    // 用户点 ▶：play() 走 _safePlayAt 重试路径
    await h2.play();
    expect(h2.isPlaying, isTrue, reason: '重试应成功起播');
  });

  test('场景3：恢复装载在飞时点播放 ▶ → 等待装载完成后自动接管起播', () async {
    final gate = Completer<void>();
    Future<String?> resolver(int id) async {
      await gate.future; // 模拟慢接口（冷启动网关冷启动/弱网）
      return 'https://cdn.example.com/$id.mp3';
    }

    final h2 = NcmAudioHandler()..urlResolver = resolver;
    final restoring = h2.restoreQueue([songA, songB], 1, Duration.zero);
    // restoreQueue 同步推进到等待解析的位置（_playAtRunning 已置位）
    await Future<void>.delayed(Duration.zero);

    // 恢复还在飞时用户就点了 ▶：等待装载完成后接管起播（不再静默吞掉）
    final tap = h2.play();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h2.isPlaying, isFalse, reason: '装载完成前处于等待态');

    gate.complete();
    await tap;
    await restoring;

    expect(h2.loadedSongId, songB.id, reason: '在飞装载应成功完成');
    expect(h2.isPlaying, isTrue,
        reason: '恢复窗口期的点击应在装载完成后自动起播');
  });

  test('场景4：恢复成功但放置超 15 分钟（直链过期）→ 点播放应重建播放器再播', () async {
    var resolveCount = 0;
    Future<String?> resolver(int id) async {
      resolveCount++;
      return 'https://cdn.example.com/$id-$resolveCount.mp3';
    }

    final h2 = NcmAudioHandler()..urlResolver = resolver;
    await h2.restoreQueue([songA, songB], 1, const Duration(seconds: 66));
    expect(h2.loadedSongId, songB.id);
    final loadsBefore = fakePlatform.players.values.single.loadRequests.length;

    // 模拟放置超时：无法直接改 _loadedAt（私有），改用行为验证——
    // 直链过期（或冷启动恢复）不再复用旧实例原地重载，而是销毁重建
    // （旧实例在长后台后可能已僵死，复用会再次卡死）。
    await h2.play();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fakePlatform.players.length, greaterThan(1),
        reason: '过期后应换新实例重建，而不是复用旧实例');
    final platform = fakePlatform.players.values.last;
    expect(platform.playRequests.length, 1, reason: '重建后应重新起播');
    expect(platform.loadRequests.length, greaterThanOrEqualTo(1),
        reason: '重建需重新装载音源（此前旧实例装载次数 $loadsBefore）');
    expect(h2.isPlaying, isTrue);
  });

  test('场景5：恢复装载 setUrl 两次均失败（直链已死）→ 点播放 ▶ 应强刷重解析起播', () async {
    Future<String?> resolver(int id) async {
      return 'https://cdn.example.com/$id.mp3';
    }

    // 让恢复路径的两次 setUrl（首载 + 强刷重试）都失败：
    // 平台级计数，避免 just_audio 每次激活重建播放器实例绕过注入。
    fakePlatform.failNextLoads = 2;
    final h2 = NcmAudioHandler()..urlResolver = resolver;

    await h2.restoreQueue([songA, songB], 1, const Duration(seconds: 10));
    expect(h2.loadedSongId, isNull, reason: '装载失败时音源未就绪');

    // 用户点 ▶：play() → _loadedSongId != song.id → _safePlayAt 重试
    await h2.play();
    // 重试路径经 _playAt 的 unawaited(_player.play())，PlayRequest 在
    // audio session 激活的异步间隙后才发出，稍等再断言。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(h2.isPlaying, isTrue, reason: '重试应重新解析并成功起播');
    final totalPlays = fakePlatform.players.values
        .map((p) => p.playRequests.length)
        .fold<int>(0, (a, b) => a + b);
    expect(totalPlays, 1, reason: '重试应向平台层发出 PlayRequest');
  });

  test('场景6：播放中平台层报错（ExoPlayer error）→ 状态复位 + 再次点播放可自愈', () async {
    Future<String?> resolver(int id) async {
      return 'https://cdn.example.com/$id.mp3';
    }

    final h2 = NcmAudioHandler()..urlResolver = resolver;
    final errors = <String>[];
    final sub = h2.playErrorStream.listen(errors.add);
    addTearDown(sub.cancel);

    await h2.playQueue([songA, songB], 0);
    final platform = fakePlatform.players.values.single;
    expect(h2.isPlaying, isTrue, reason: '正常起播');

    // 模拟 ExoPlayer 播放错误：平台层经 playbackEventMessageStream 发错误
    // 事件（真机上解码失败/网络中断/CDN 拒绝都走这条路径）。旧实现把错误
    // 整个吞掉，playing 标志与实际发声脱节，此后点播放永久 no-op。
    platform.eventController.addError(Exception('exoplayer error'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(h2.loadedSongId, isNull, reason: '错误后音源归属应作废');
    expect(h2.playbackState.value.playing, isFalse,
        reason: '播放态应复位为暂停（UI 回到 ▶ 而非卡在 ⏸）');
    expect(errors, isNotEmpty, reason: '应经 playErrorStream 广播失败提示');

    // 用户再次点 ▶：应走重装载路径恢复，而不是无声 no-op
    await h2.play();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(h2.isPlaying, isTrue, reason: '错误后点播放应重装载并恢复播放');
    expect(platform.playRequests.length, 2,
        reason: '恢复应再次向平台层发出 PlayRequest');
  });

  test('场景7：播放中点暂停 ⏸ → 应彻底暂停，不被自动复播（回归）', () async {
    Future<String?> resolver(int id) async =>
        'https://cdn.example.com/$id.mp3';

    final h = NcmAudioHandler()..urlResolver = resolver;
    await h.playQueue([songA, songB], 0);
    expect(h.isPlaying, isTrue, reason: '正常起播');
    final platform = fakePlatform.players.values.single;
    // playQueue 的起播是 unawaited：平台层 PlayRequest 经 audio session
    // 激活的异步间隙才发出，稍等再断言。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.playRequests.length, 1, reason: '起播应向平台层发出一次 play');

    // 模拟真实 just_audio 语义：此后 play() 的 Future 挂起直到 pause。
    // 真机上「点 ▶ 恢复 → 点 ⏸ 暂停」时，handler.play() 里那个
    // await _player.play() 会一直挂到用户按暂停的一刻才返回——
    // 旧实现的「无声自愈」兜底把这次正常暂停误判为播放失败，
    // 作废音源归属并重装载自动复播（暂停 1~2 秒后又自己响起来）。
    platform.holdPlayUntilPause = true;

    await h.pause(); // 先暂停一次（当前 UI 状态为暂停）
    final tap = h.play(); // 用户点 ▶：该 Future 真机上挂起到下次暂停
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.isPlaying, isTrue, reason: '恢复播放应生效');
    // 计数基准取「恢复成功后、按暂停前」：恢复那一击本身合法地发了一次 play。
    final playsBefore = platform.playRequests.length;
    final loadsBefore = platform.loadRequests.length;

    await h.pause(); // 用户点 ⏸：旧实现在此触发错误自愈 → 1~2 秒后自动复播
    await tap; // 等挂起的 play() 返回、兜底分支执行完
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(h.isPlaying, isFalse, reason: '暂停后必须保持暂停，不得自动复播');
    expect(h.loadedSongId, songA.id,
        reason: '正常暂停不得作废音源归属（作废会触发重装载复播）');
    expect(platform.playRequests.length, playsBefore,
        reason: '暂停不得向平台层再次发起 play');
    expect(platform.loadRequests.length, loadsBefore,
        reason: '暂停不得重装载音源');
  });

  // ===== 播放按钮乐观更新 / 封面 loading / 失败回滚 / 连点连切 =====

  test('乐观更新：点播放瞬间即切 ⏸，不等音源与平台起播', () async {
    Future<String?> resolver(int id) async =>
        'https://cdn.example.com/$id.mp3';
    final h = NcmAudioHandler()..urlResolver = resolver;
    await h.playQueue([songA], 0);
    await h.pause();
    expect(h.uiPlaying, isFalse, reason: '暂停后应显示 ▶');

    final future = h.play();
    // play() 的同步段就写入乐观意图，尚未等音频会话激活 / 平台 play。
    expect(h.uiPlaying, isTrue, reason: '点播放应立即显示 ⏸');
    expect(h.playbackState.value.playing, isTrue,
        reason: '播放态也应立即切换');
    await future;
    expect(h.isPlaying, isTrue, reason: '随后底层应真正起播');
  });

  test('封面 loading：装载即出现、完成撤下；装载中点暂停不自动复播', () async {
    final gate = Completer<void>();
    Future<String?> resolver(int id) async {
      await gate.future;
      return 'https://cdn.example.com/$id.mp3';
    }

    final h = NcmAudioHandler()..urlResolver = resolver;
    final playFuture = h.playQueue([songA], 0);
    expect(h.isPreparing, isTrue, reason: '音源获取中应出现封面 loading');
    expect(h.uiPlaying, isTrue, reason: '按钮立即乐观显示 ⏸');

    await h.pause();
    expect(h.isPreparing, isFalse, reason: '暂停应立即撤下 loading');
    expect(h.uiPlaying, isFalse, reason: '暂停应立即回 ▶');

    gate.complete();
    await playFuture;
    await Future<void>.delayed(Duration.zero);
    expect(h.isPlaying, isFalse, reason: '装载完成也不得在暂停态自动起播');
    expect(h.isPreparing, isFalse, reason: 'loading 不得残留');
    expect(fakePlatform.players.values.single.playRequests, isEmpty,
        reason: '暂停后不得再向平台层发起 play');

    // 再点播放：应立即回 ⏸，并在真正起播后撤下 loading。
    final resume = h.play();
    expect(h.uiPlaying, isTrue);
    await resume;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.isPlaying, isTrue);
    expect(h.isPreparing, isFalse);
  });

  test('获取失败回滚：按钮回 ▶、loading 撤下、经 playErrorStream 提示', () async {
    Future<String?> resolver(int id) async => null;
    final h = NcmAudioHandler()..urlResolver = resolver;
    final errors = <String>[];
    final sub = h.playErrorStream.listen(errors.add);
    addTearDown(sub.cancel);

    final future = h.playQueue([songA], 0);
    expect(h.uiPlaying, isTrue, reason: '点击瞬间乐观在播');
    expect(h.isPreparing, isTrue, reason: '点击瞬间出现 loading');

    await expectLater(future, throwsA(isA<ApiException>()));
    expect(h.uiPlaying, isFalse, reason: '失败后必须回滚到 ▶');
    expect(h.playbackState.value.playing, isFalse);
    expect(h.isPreparing, isFalse, reason: '失败后 loading 必须撤下');

    // 再点播放重试仍失败：应广播失败提示，且仍保持暂停态。
    await h.play();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(errors, isNotEmpty, reason: '失败应给出可见提示');
    expect(h.uiPlaying, isFalse, reason: '重试失败不得停留在在播态');
    expect(h.isPreparing, isFalse);
  });

  test('连点：装载中播放/暂停快切 → 最终暂停、无 loading 残留、无多余起播', () async {
    final gate = Completer<void>();
    Future<String?> resolver(int id) async {
      await gate.future;
      return 'https://cdn.example.com/$id.mp3';
    }

    final h = NcmAudioHandler()..urlResolver = resolver;
    final playFuture = h.playQueue([songA], 0); // 装载中
    await h.togglePlayPause(); // → 暂停
    expect(h.uiPlaying, isFalse);
    final resumeFuture = h.togglePlayPause(); // → 播放（等待在飞装载）
    expect(h.uiPlaying, isTrue);
    await h.togglePlayPause(); // → 又暂停
    expect(h.uiPlaying, isFalse);
    expect(h.isPreparing, isFalse, reason: '暂停应立即撤下 loading');

    gate.complete();
    await playFuture;
    await resumeFuture;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.isPlaying, isFalse, reason: '快切后最终必须是暂停态，不能自己响');
    expect(h.isPreparing, isFalse, reason: '不得残留 loading');
    expect(fakePlatform.players.values.single.playRequests, isEmpty,
        reason: '快切过程中不得堆叠或多发 play 请求');
  });

  test('连切：旧歌装载晚返回不得覆盖新歌状态 / 重新点亮 loading', () async {
    final gateA = Completer<void>();
    Future<String?> resolver(int id) async {
      if (id == songA.id) await gateA.future;
      return 'https://cdn.example.com/$id.mp3';
    }

    final h = NcmAudioHandler()..urlResolver = resolver;
    unawaited(h.playQueue([songA, songB], 0)); // A 装载挂起
    expect(h.isPreparing, isTrue);

    await h.skipToNext(); // 立刻切到 B
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.queueIndex, 1);
    expect(h.uiPlaying, isTrue);
    expect(h.isPreparing, isFalse, reason: '新歌装载完成应撤下 loading');
    final playsAfterSwitch =
        fakePlatform.players.values.single.playRequests.length;

    gateA.complete(); // 旧歌请求此刻才回来
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.queueIndex, 1, reason: '旧请求不得回切到 A');
    expect(h.isPreparing, isFalse, reason: '旧请求不得重新点亮 loading');
    expect(h.uiPlaying, isTrue, reason: '仍应播放 B');
    expect(fakePlatform.players.values.single.playRequests.length,
        playsAfterSwitch,
        reason: '旧请求不得再发 play');
  });

  test('播完最后一首：按钮回 ▶、不残留「显示在播」', () async {
    final h = NcmAudioHandler()
      ..urlResolver = (id) async => 'https://cdn.example.com/$id.mp3';
    await h.playQueue([songA], 0);
    expect(h.uiPlaying, isTrue);

    final p = fakePlatform.players.values.single;
    p.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(h.uiPlaying, isFalse, reason: '播完最后一首应显示暂停态 ▶');
    expect(h.playbackState.value.playing, isFalse);
    // just_audio 播完后 playing 仍为 true，必须 pause 复位，
    // 否则下次点播放会被 play() 的 `if (playing) return;` 吞掉。
    expect(h.isPlaying, isFalse, reason: '底层 playing 标志应被复位');
  });

  // ===== 长后台失效：播放请求看门狗 + 播放器重建 + 回前台对账 =====

  test('play 超时触发自愈：平台实例僵死（Future 永不返回）→ 看门狗判定失效并重建', () async {
    Future<String?> resolver(int id) async =>
        'https://cdn.example.com/$id.mp3';
    // 缩短看门狗超时以便测试，语义与真机 4s 相同。
    final h = NcmAudioHandler(playStartTimeout: const Duration(milliseconds: 80))
      ..urlResolver = resolver;
    final errors = <String>[];
    final sub = h.playErrorStream.listen(errors.add);
    addTearDown(sub.cancel);

    await h.playQueue([songA], 0);
    await h.pause();
    final playersBefore = fakePlatform.players.length;
    final dead = fakePlatform.players.values.last;

    // 模拟 ColorOS 长时间冻结后引擎被回收：该实例的 play() 永不返回。
    dead.frozen = true;

    await h.play();
    // 真机上这里会「点了没反应」：旧实现一直 await 平台 play() 的 Future。
    expect(h.uiPlaying, isTrue, reason: '点击瞬间仍是乐观在播');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(errors, isNotEmpty, reason: '超时必须有可见提示，不得静默');
    expect(fakePlatform.players.length, greaterThan(playersBefore),
        reason: '失效实例应被销毁并重建，而不是复用');
    final rebuilt = fakePlatform.players.values.last;
    expect(rebuilt, isNot(same(dead)), reason: '必须换成新的平台播放器实例');
    expect(rebuilt.playRequests.length, 1, reason: '重建后应重新起播');
    expect(h.loadedSongId, songA.id, reason: '重建后音源归属应恢复');
    expect(h.isPlaying, isTrue, reason: '自愈后应真正进入播放态');
  });

  test('暂停 → 后台 → 回前台 → 播放：对账不自动起播，陈旧引擎重建后可正常播放', () async {
    Future<String?> resolver(int id) async =>
        'https://cdn.example.com/$id.mp3';
    // staleEngineAfter 注入 0：等价真机「暂停后后台放置约 1 小时」。
    final h = NcmAudioHandler(
      staleEngineAfter: Duration.zero,
    )..urlResolver = resolver;

    await h.playQueue([songA], 0);
    await h.pause();
    expect(h.uiPlaying, isFalse);
    expect(h.isPlaying, isFalse);
    final playersBefore = fakePlatform.players.length;

    // 模拟 App 退后台很久后回到前台：QueueSnapshotStore 会调用该方法。
    await h.reactivateForForeground();

    // 对账以真实状态为准：用户主动暂停的歌不得被回前台动作自动播起来。
    expect(h.isPlaying, isFalse, reason: '回前台对账不得自动复播');
    expect(h.playbackState.value.playing, isFalse, reason: 'UI 与真实态一致');
    expect(h.uiPlaying, isFalse, reason: '按钮应保持 ▶');
    expect(fakePlatform.players.length, playersBefore,
        reason: '回前台本身不重载（避免切换停顿），只在下次起播时重建');

    // 用户点播放：陈旧引擎 → 换新实例（保存 position → dispose → 重建 →
    // seek 回原位 → 播放），而不是复用僵死实例重装载。
    await h.play();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fakePlatform.players.length, greaterThan(playersBefore),
        reason: '陈旧引擎应被重建');
    expect(h.isPlaying, isTrue, reason: '回前台后点播放必须能起播');
    expect(h.uiPlaying, isTrue);
  });
}
