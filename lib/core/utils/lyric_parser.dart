import '../../models/lyric_line.dart';

/// 轻量 LRC 解析器，支持一行多个时间标签与同时间点的双语歌词合并。
class LyricParser {
  const LyricParser._();

  static final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static List<LyricLine> parse(String raw) {
    final grouped = <int, List<String>>{};

    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final matches = _timeTag.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;

      final text = rawLine.replaceAll(_timeTag, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fractionText = match.group(3) ?? '0';
        final fraction = int.tryParse(fractionText) ?? 0;
        final fractionMs = switch (fractionText.length) {
          1 => fraction * 100,
          2 => fraction * 10,
          _ => fraction,
        };
        final milliseconds = (minutes * 60 + seconds) * 1000 + fractionMs;
        grouped.putIfAbsent(milliseconds, () => []).add(text);
      }
    }

    final lines = grouped.entries.map((entry) {
      final texts = <String>[];
      for (final text in entry.value) {
        if (!texts.contains(text)) texts.add(text);
      }
      return LyricLine(
        start: Duration(milliseconds: entry.key),
        text: texts.join('\n'),
      );
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    return lines;
  }

  /// 二分查找当前播放位置对应的歌词下标，找不到时返回 -1。
  static int activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].start <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
