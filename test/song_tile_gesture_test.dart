import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/widgets/song_tile.dart';

const _song = Song(
  contentId: 'c1',
  copyrightId: 'cr1',
  name: '测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 180),
  isVipOnly: false,
);

Future<void> _pumpTile(
  WidgetTester tester, {
  required bool doubleTap,
  required VoidCallback onPlay,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 720,
            child: SongTile(
              song: _song,
              number: 1,
              doubleTapToPlay: doubleTap,
              onTap: onPlay,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('桌面模式下单击不起播，双击才播放', (tester) async {
    var plays = 0;
    await _pumpTile(tester, doubleTap: true, onPlay: () => plays++);
    final center = tester.getCenter(find.text('测试歌曲'));

    final first = await tester.startGesture(center);
    await first.up();
    await tester.pump(const Duration(milliseconds: 80));
    expect(plays, 0);

    final second = await tester.startGesture(center);
    await second.up();
    await tester.pump(const Duration(milliseconds: 80));
    expect(plays, 1);
  });

  testWidgets('触屏模式下仍然单击播放', (tester) async {
    var plays = 0;
    await _pumpTile(tester, doubleTap: false, onPlay: () => plays++);

    await tester.tap(find.text('测试歌曲'));
    await tester.pump();
    expect(plays, 1);
  });
}
