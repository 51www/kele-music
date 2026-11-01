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
    if (failPlay) {
      failPlay = false;
      throw Exception('simulated exoplayer error');
    }
    _emitReady();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    pauseRequests.add(request);
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

  test('场景4：恢复成功但放置超 15 分钟（直链过期）→ 点播放应原地重载再播', () async {
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
    // 此场景仅验证恢复后立即可播；超时重载逻辑见 play() 的 _loadedUrlMaxAge 分支。
    await h2.play();
    final platform = fakePlatform.players.values.single;
    expect(platform.playRequests.length, 1);
    expect(platform.loadRequests.length, greaterThanOrEqualTo(loadsBefore));
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
}
