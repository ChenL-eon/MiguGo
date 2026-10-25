/// 从歌单分享链接或纯数字中提取歌单 ID。
String? parsePlaylistId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  if (RegExp(r'^\d{5,12}$').hasMatch(text)) return text;

  final patterns = <RegExp>[
    RegExp(r'playlist/(\d{5,12})', caseSensitive: false),
    RegExp(r'playlistId=(\d{5,12})', caseSensitive: false),
    RegExp(r'[?&]id=(\d{5,12})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }

  final fallback = RegExp(r'(\d{5,12})').firstMatch(text);
  return fallback?.group(1);
}
