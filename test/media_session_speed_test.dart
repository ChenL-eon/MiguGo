import 'dart:async';

import 'package:flutter_media_session/flutter_media_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/playback_mode.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/services/audio/media_session_bridge.dart';

/// 系统媒体会话的假平台：只记录应用真正推给系统的那份状态。
class _FakeMediaPlatform extends FlutterMediaSessionPlatform {
  final StreamController<MediaAction> _actions =
      StreamController<MediaAction>.broadcast();
  final List<PlaybackState> states = [];
  bool activated = false;

  @override
  Future<void> activate() async => activated = true;

  @override
  Future<void> deactivate() async => activated = false;

  @override
  Future<void> updateMetadata(MediaMetadata metadata) async {}

  @override
  Future<void> updatePlaybackState(PlaybackState state) async {
    states.add(state);
  }

  @override
  Future<void> updateAvailableActions(Set<MediaAction>? actions) async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> setWindowsAppUserModelId(
    String id, {
    String? displayName,
    String? iconPath,
  }) async {}

  @override
  Future<void> setAutoHandleInterruptions(bool enabled) async {}

  @override
  Stream<MediaAction> get onMediaAction => _actions.stream;
}

Song _song() {
  return const Song(
    contentId: 'c1',
    copyrightId: 'cr1',
    name: '晴天',
    artistNames: ['周杰伦'],
    album: '测试专辑',
    duration: Duration(seconds: 200),
    isVipOnly: false,
  );
}

/// 倍速播放时系统媒体卡片要按真实倍速外推，否则进度会一直漂。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterMediaSessionPlatform original;
  late _FakeMediaPlatform platform;

  setUp(() {
    original = FlutterMediaSessionPlatform.instance;
    platform = _FakeMediaPlatform();
    FlutterMediaSessionPlatform.instance = platform;
  });

  tearDown(() {
    FlutterMediaSessionPlatform.instance = original;
  });

  Future<MediaSessionBridge> activatedBridge() async {
    final bridge = MediaSessionBridge();
    await bridge.initialize(
      onPlay: () {},
      onPause: () {},
      onNext: () {},
      onPrevious: () {},
      onStop: () {},
      onSeek: (_) {},
    );
    await bridge.activate();
    expect(platform.activated, isTrue);
    return bridge;
  }

  Future<void> syncAtSpeed(MediaSessionBridge bridge, double speed) {
    return bridge.sync(
      song: _song(),
      playing: true,
      buffering: false,
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 200),
      mode: PlaybackMode.listLoop,
      speed: speed,
    );
  }

  test('倍速播放时系统媒体卡片拿到真实倍速', () async {
    final bridge = await activatedBridge();

    await syncAtSpeed(bridge, 1.5);

    expect(platform.states.single.speed, 1.5);
    expect(platform.states.single.status, PlaybackStatus.playing);
  });

  test('从倍速切回 1.0 时系统媒体卡片也回到 1.0', () async {
    final bridge = await activatedBridge();

    await syncAtSpeed(bridge, 0.75);
    await syncAtSpeed(bridge, 1.0);

    expect(platform.states.map((state) => state.speed), [0.75, 1.0]);
  });
}
