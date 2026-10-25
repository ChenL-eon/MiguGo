import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/lyric_line.dart';
import 'package:migu_lele/services/platform/desktop_lyrics_snapshot.dart';

List<LyricLine> _lines() => const [
  LyricLine(start: Duration(seconds: 1), text: '第一句'),
  LyricLine(start: Duration(seconds: 5), text: '第二句\nsecond line'),
  LyricLine(start: Duration(seconds: 9), text: '第三句'),
];

DesktopLyricsSnapshot _build({
  required List<LyricLine> lines,
  required Duration position,
  String status = 'MiguGo 桌面歌词',
  bool doubleLine = true,
}) {
  return buildDesktopLyricsSnapshot(
    lines: lines,
    position: position,
    status: status,
    fontPt: 22,
    colorArgb: 0xFFFFD166,
    unplayedArgb: 0xFFB9BEC9,
    strokeArgb: 0,
    panelAlpha: 96,
    doubleLine: doubleLine,
    topmost: true,
    locked: false,
    playing: true,
    windowPosition: const [100, 200],
  );
}

void main() {
  test('没有歌词时只回显占位文案', () {
    final snapshot = _build(lines: const [], position: Duration.zero);
    expect(snapshot.lines, isEmpty);
    expect(snapshot.status, 'MiguGo 桌面歌词');
    expect(snapshot.progress, 0);
  });

  test('播放位置在首句之前时不显示歌词', () {
    final snapshot = _build(
      lines: _lines(),
      position: const Duration(milliseconds: 500),
      status: '纯音乐，请欣赏',
    );
    expect(snapshot.lines, isEmpty);
    expect(snapshot.status, '纯音乐，请欣赏');
  });

  test('双行取下一句，单行只保留当前句', () {
    final twoLines = _build(lines: _lines(), position: const Duration(seconds: 2));
    expect(twoLines.lines, ['第一句', '第二句']);

    final single = _build(
      lines: _lines(),
      position: const Duration(seconds: 2),
      doubleLine: false,
    );
    expect(single.lines, ['第一句']);
  });

  test('带翻译的一行优先把译文作为第二行', () {
    final snapshot = _build(lines: _lines(), position: const Duration(seconds: 6));
    expect(snapshot.lines, ['第二句', 'second line']);
  });

  test('进度按当前句到下一句的区间线性推进', () {
    final half = _build(lines: _lines(), position: const Duration(seconds: 3));
    expect(half.progress, closeTo(0.5, 0.001));
    // 原生浮层拿这个时长在自己的时钟上继续推进高亮。
    expect(half.lineDurationMs, 4000);

    final before = _build(lines: _lines(), position: const Duration(milliseconds: 900));
    expect(before.progress, 0);

    final lastLine = _build(
      lines: _lines(),
      position: const Duration(seconds: 30),
      doubleLine: false,
    );
    expect(lastLine.progress, 0);
    expect(lastLine.lineDurationMs, 0);
    expect(lastLine.lines, ['第三句']);
  });

  test('载荷映射覆盖原生窗口需要的全部字段', () {
    final snapshot = _build(lines: _lines(), position: const Duration(seconds: 2));
    expect(snapshot.toMap(), {
      'lines': ['第一句', '第二句'],
      'status': 'MiguGo 桌面歌词',
      'progress': snapshot.progress,
      'lineDurationMs': 4000,
      'fontPt': 22,
      'color': 0xFFFFD166,
      'unplayedColor': 0xFFB9BEC9,
      'strokeColor': 0,
      'backgroundAlpha': 96,
      'doubleLine': isTrue,
      'topmost': isTrue,
      'locked': isFalse,
      'playing': isTrue,
      'x': 100,
      'y': 200,
    });
  });

  test('描边与未播放颜色都进入签名', () {
    final base = _build(lines: _lines(), position: const Duration(seconds: 2));
    final stroked = buildDesktopLyricsSnapshot(
      lines: _lines().toList(),
      position: const Duration(seconds: 2),
      status: 'MiguGo 桌面歌词',
      fontPt: 22,
      colorArgb: 0xFFFFD166,
      unplayedArgb: 0xFFB9BEC9,
      strokeArgb: 0xE6000000,
      panelAlpha: 96,
      doubleLine: true,
      topmost: true,
      locked: false,
      playing: true,
      windowPosition: const [100, 200],
    );
    expect(base.signature, isNot(stroked.signature));
    expect(stroked.toMap()['strokeColor'], 0xE6000000);
  });

  test('未记录位置时下发 -1 让原生自行定位', () {
    final snapshot = buildDesktopLyricsSnapshot(
      lines: const [],
      position: Duration.zero,
      status: '未在播放',
      fontPt: 20,
      colorArgb: 0xFFFFFFFF,
      unplayedArgb: 0xFFB9BEC9,
      strokeArgb: 0xE6000000,
      panelAlpha: 60,
      doubleLine: true,
      topmost: true,
      locked: true,
      playing: false,
    );
    expect(snapshot.toMap()['x'], -1);
    expect(snapshot.toMap()['y'], -1);
  });

  test('签名忽略位置变化，但随歌词与进度改变', () {
    final a = _build(lines: _lines(), position: const Duration(seconds: 2));
    final moved = buildDesktopLyricsSnapshot(
      lines: _lines().toList(),
      position: const Duration(seconds: 2),
      status: 'MiguGo 桌面歌词',
      fontPt: 22,
      colorArgb: 0xFFFFD166,
      unplayedArgb: 0xFFB9BEC9,
      strokeArgb: 0,
      panelAlpha: 96,
      doubleLine: true,
      topmost: true,
      locked: false,
      playing: true,
      windowPosition: const [900, 100],
    );
    expect(a.signature, moved.signature);

    final later = _build(lines: _lines(), position: const Duration(seconds: 6));
    expect(a.signature, isNot(later.signature));
  });
}
