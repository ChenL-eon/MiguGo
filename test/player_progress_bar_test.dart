import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/pages/player_page.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// 只替换进度条真正用到的三条通道，不碰音频平台。
class _StubPlayer extends PlayerProvider {
  _StubPlayer()
    : super(
        MiguMusicApi(
          client: MiguApiClient(
            cookieStore: MiguCookieStore(secureStorage: FakeSecureCookieStorage()),
          ),
        ),
      );

  final List<Duration> seeks = [];

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

Song _song(String id, int seconds) {
  return Song(
    contentId: id,
    copyrightId: 'cr_$id',
    name: '歌$id',
    artistNames: const ['周杰伦'],
    album: '测试专辑',
    duration: Duration(seconds: seconds),
    isVipOnly: false,
  );
}

Future<void> _pumpBar(WidgetTester tester, _StubPlayer player, Song song) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: PlayerProgressBar(player: player, song: song),
          ),
        ),
      ),
    ),
  );
}

/// 进度条拖动期间恰好切歌：上一首的拖动比例不能落到新歌上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('拖到一半切歌后显示新歌进度，松手也不会拿新时长换算旧比例', (tester) async {
    final player = _StubPlayer();
    final first = _song('a', 200);
    final second = _song('b', 100);

    await _pumpBar(tester, player, first);
    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await tester.pump();
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(
      tester.widget<Slider>(sliderFinder).value,
      lessThan(0.5),
      reason: '拖动中应跟随手指离开中点',
    );

    await _pumpBar(tester, player, second);
    await tester.pump();

    expect(
      tester.widget<Slider>(sliderFinder).value,
      0.0,
      reason: '切歌后应显示新歌自己的进度，而不是上一首的拖动位置',
    );

    await gesture.up();
    await tester.pump();

    expect(player.seeks, isEmpty, reason: '松手时的比例属于上一首，不能拿新歌时长换成另一个位置');
  });

  testWidgets('同一首歌内拖动松手仍然 seek 到对应位置', (tester) async {
    final player = _StubPlayer();
    final song = _song('a', 200);

    await _pumpBar(tester, player, song);
    final sliderFinder = find.byType(Slider);

    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await tester.pump();
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    final dragValue = tester.widget<Slider>(sliderFinder).value;
    await gesture.up();
    await tester.pump();

    expect(player.seeks, hasLength(1));
    expect(
      player.seeks.single.inMilliseconds,
      (const Duration(seconds: 200).inMilliseconds * dragValue).round(),
    );
  });
}
