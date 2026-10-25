/// 一行已解析的歌词。
class LyricLine {
  const LyricLine({required this.start, required this.text});

  final Duration start;
  final String text;

  @override
  String toString() => '${start.inMilliseconds}ms $text';
}
