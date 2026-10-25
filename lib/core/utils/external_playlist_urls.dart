/// 支持导入的外部歌单平台。
enum ExternalPlatform { netease, qqMusic, kugou }

extension ExternalPlatformLabel on ExternalPlatform {
  String get label => switch (this) {
    ExternalPlatform.netease => '网易云音乐',
    ExternalPlatform.qqMusic => 'QQ音乐',
    ExternalPlatform.kugou => '酷狗音乐',
  };
}

/// 解析出的歌单链接。短链接暂时没有 ID，需要先跟随跳转。
class ExternalPlaylistLink {
  const ExternalPlaylistLink({required this.platform, required this.url, this.id});

  final ExternalPlatform platform;
  final Uri url;
  final String? id;

  bool get needsResolution => id == null || id!.isEmpty;
}

/// 从分享链接中识别平台与歌单 ID；无法识别时返回 null。
ExternalPlaylistLink? parseExternalPlaylistLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final urlMatch = RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(text);
  if (urlMatch == null) return null;

  final rawUrl = urlMatch.group(0)!.replaceAll(RegExp(r'[)\]}>，。；、]+$'), '');
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.host.isEmpty) return null;

  final platform = _platformForHost(uri.host);
  if (platform == null) return null;

  final id = switch (platform) {
    ExternalPlatform.netease => _netEaseId(text),
    ExternalPlatform.qqMusic => _qqMusicId(text),
    ExternalPlatform.kugou => _kugouId(text),
  };

  return ExternalPlaylistLink(platform: platform, url: uri, id: id);
}

ExternalPlatform? _platformForHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'music.163.com' ||
      normalized == '163cn.tv' ||
      normalized.endsWith('.163cn.tv')) {
    return ExternalPlatform.netease;
  }
  if (normalized == 'y.qq.com' ||
      normalized == 'c.y.qq.com' ||
      normalized == 'c6.y.qq.com' ||
      normalized == 'i.y.qq.com' ||
      normalized.endsWith('.y.qq.com')) {
    return ExternalPlatform.qqMusic;
  }
  if (normalized == 'kugou.com' || normalized.endsWith('.kugou.com')) {
    return ExternalPlatform.kugou;
  }
  return null;
}

String? _netEaseId(String text) {
  final patterns = <RegExp>[
    RegExp(r'/playlist/(\d{5,})', caseSensitive: false),
    RegExp(r'[?&#]id=(\d{5,})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

String? _qqMusicId(String text) {
  final patterns = <RegExp>[
    RegExp(r'/playlist/(\d{5,})', caseSensitive: false),
    RegExp(r'[?&](?:disstid|id)=(\d{5,})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

String? _kugouId(String text) {
  final patterns = <RegExp>[
    RegExp(
      r'/special/single/([A-Za-z0-9_]+?)(?:\.html)?(?:[?#]|$)',
      caseSensitive: false,
    ),
    RegExp(r'/plist/list/(\d{5,})', caseSensitive: false),
    RegExp(r'[?&]specialid=(\d{5,})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}
