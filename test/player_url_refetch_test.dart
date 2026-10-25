import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/audio_quality.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只暴露取链与歌词两条路径的假接口：第一次取链被闸门卡住，
/// 好让测试精确掌握「加载还没走到起播」这一步，不靠固定等待；
/// 第二次取链直接失败，避免加载走到 just_audio 的平台通道
/// （单测宿主没有原生实现，会抛出与本用例无关的 MissingPluginException）。
class _GatedMusicApi extends MiguMusicApi {
  int resolveCalls = 0;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String> resolvePlaybackUrl(
    Song song, {
    AudioQuality quality = AudioQuality.hq,
  }) async {
    resolveCalls++;
    if (resolveCalls == 1) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return 'https://play.migu.cn/$quality.mp3';
    }
    throw const MiguApiException('播放地址已过期。');
  }

  @override
  Future<String?> fetchLyrics(Song song) async => null;
}

Song _song() {
  return Song(
    contentId: 'c1',
    copyrightId: 'cr1',
    name: '晴天',
    artistNames: const ['周杰伦'],
    album: '测试专辑',
    duration: const Duration(seconds: 200),
    isVipOnly: false,
  );
}

/// README 承诺「播放链接过期后重新请求」：自动续播撞上过期地址时不该卡死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('播放失败自动重新取链一次，再来一次就停手', () async {
    final api = _GatedMusicApi();
    final player = PlayerProvider(api);

    unawaited(player.playQueue([_song()], 0));
    await api.entered.future;
    expect(api.resolveCalls, 1);

    await player.handlePlaybackFailure('音频解码失败');
    expect(api.resolveCalls, 2, reason: '过期地址要自动重新取链，不用用户手点重试');

    await player.handlePlaybackFailure('还是坏地址');
    expect(api.resolveCalls, 2, reason: '重取要有封顶，不能无限重试打接口');
    expect(player.error, isNotNull);

    api.release.complete();
    // 让上面那次被闸门卡住的加载按代际作废后收尾；不 dispose 播放器：
    // 单测宿主没有 just_audio 的平台通道，销毁会抛与本用例无关的异常。
    await Future<void>.value();
  });
}
