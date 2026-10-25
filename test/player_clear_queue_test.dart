import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/playback_mode.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// 退出登录时播放器要做到的复位：不用联网，也不用真的起播。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PlayerProvider> createPlayer() async {
    final cookieStore = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
    await cookieStore.init();
    return PlayerProvider(
      MiguMusicApi(client: MiguApiClient(cookieStore: cookieStore)),
    );
  }

  test('清空队列后回到未播放状态', () async {
    final player = await createPlayer();

    await player.clearQueue();

    expect(player.queue, isEmpty);
    expect(player.hasSong, isFalse);
    expect(player.currentIndex, -1);
    expect(player.isPlaying, isFalse);
    expect(player.isLoading, isFalse);
    expect(player.isBuffering, isFalse);
    expect(player.error, isNull);
    expect(player.lyrics, isEmpty);
  });

  test('清空队列顺手取消睡眠定时', () async {
    final player = await createPlayer();
    player.setSleepTimer(const Duration(minutes: 30));
    expect(player.hasSleepTimer, isTrue);

    await player.clearQueue();

    expect(player.hasSleepTimer, isFalse);
    expect(player.sleepRemaining, isNull);
  });

  test('播放顺序与音量这类偏好不被清空队列带走', () async {
    final player = await createPlayer();
    await player.setPlaybackMode(PlaybackMode.singleLoop);
    await player.setVolume(0.4);
    await player.setSpeed(1.5);

    await player.clearQueue();

    expect(player.mode, PlaybackMode.singleLoop);
    expect(player.volume, 0.4);
    expect(player.speed, 1.5);
  });
}
