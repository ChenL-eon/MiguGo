import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/lyric_parser.dart';
import 'package:migu_lele/models/lyric_line.dart';

void main() {
  group('LyricParser.parse', () {
    test('解析时间标签并排序', () {
      const raw = '''
[00:12.50]第一行
[00:03.2]第二行
[01:05.500]第三行
[ar:测试歌手]
''';
      final lines = LyricParser.parse(raw);

      expect(lines.length, 3);
      expect(lines[0].start, const Duration(milliseconds: 3200));
      expect(lines[0].text, '第二行');
      expect(lines[1].start, const Duration(milliseconds: 12500));
      expect(lines[2].start, const Duration(milliseconds: 65500));
    });

    test('同一时间点的双语歌词会合并', () {
      const raw = '''
[00:10.00]Hello
[00:10.00]你好
[00:10.00]Hello
''';
      final lines = LyricParser.parse(raw);

      expect(lines.length, 1);
      expect(lines.single.text, 'Hello\n你好');
    });

    test('一行多个时间标签会拆分为多行', () {
      const raw = '[00:10.00][01:20.00]副歌';
      final lines = LyricParser.parse(raw);

      expect(lines.length, 2);
      expect(lines[0].start, const Duration(seconds: 10));
      expect(lines[1].start, const Duration(seconds: 80));
      expect(lines.every((line) => line.text == '副歌'), isTrue);
    });

    test('忽略没有时间标签或内容为空的行', () {
      const raw = '''
[ti:标题]
[00:01.00]
[00:02.00]正文
''';
      final lines = LyricParser.parse(raw);

      expect(lines.length, 1);
      expect(lines.single.text, '正文');
    });
  });

  group('LyricParser.activeIndex', () {
    final lines = [
      const LyricLine(start: Duration(seconds: 0), text: 'A'),
      const LyricLine(start: Duration(seconds: 5), text: 'B'),
      const LyricLine(start: Duration(seconds: 10), text: 'C'),
    ];

    test('空歌词返回 -1', () {
      expect(LyricParser.activeIndex(const [], Duration.zero), -1);
    });

    test('位置早于第一行返回 -1', () {
      const linesWithDelay = [LyricLine(start: Duration(seconds: 2), text: 'A')];
      expect(LyricParser.activeIndex(linesWithDelay, const Duration(seconds: 1)), -1);
    });

    test('命中每一行的起始时间', () {
      expect(LyricParser.activeIndex(lines, Duration.zero), 0);
      expect(LyricParser.activeIndex(lines, const Duration(seconds: 5)), 1);
      expect(LyricParser.activeIndex(lines, const Duration(seconds: 10)), 2);
    });

    test('位于两行之间时仍返回上一行', () {
      expect(
        LyricParser.activeIndex(lines, const Duration(seconds: 9, milliseconds: 999)),
        1,
      );
      expect(LyricParser.activeIndex(lines, const Duration(minutes: 3)), 2);
    });
  });
}
