import 'dart:convert';
import 'dart:math' as math;

import '../core/utils/external_playlist_urls.dart';
import '../core/utils/json_read.dart';
import 'song.dart';

/// 外部歌单读取失败时抛出的可展示异常。
class ExternalPlaylistException implements Exception {
  const ExternalPlaylistException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 外部平台歌单里的一首曲目，只保留匹配咪咕所需的歌名与歌手。
class ExternalTrack {
  const ExternalTrack({required this.title, required this.artist});

  final String title;
  final String artist;
}

/// 外部平台公开歌单的解析结果。
class ExternalPlaylist {
  const ExternalPlaylist({
    required this.platform,
    required this.sourceUrl,
    required this.name,
    required this.tracks,
    required this.totalCount,
    this.coverUrl,
    this.isPartial = false,
    this.limitNote = '',
  });

  final ExternalPlatform platform;
  final String sourceUrl;
  final String name;
  final List<ExternalTrack> tracks;
  final int totalCount;
  final String? coverUrl;

  /// 平台网页只公开了部分曲目时为 true，例如酷狗只展示前 30 首。
  final bool isPartial;
  final String limitNote;

  /// 详情接口可能只返回部分曲目，但 trackIds 仍保留完整顺序。
  /// 返回尚未拿到详情的曲目 ID，供调用方补拉。
  static List<String> neteaseMissingTrackIds(dynamic payload) {
    final root = _decodedMap(payload);
    final playlist = readMap(root?['playlist']);
    if (playlist == null) return const [];

    final present = <String>{};
    for (final item in readList(playlist['tracks'])) {
      final id = _neteaseId(readMap(item));
      if (id != null) present.add(id);
    }

    final missing = <String>[];
    for (final item in readList(playlist['trackIds'])) {
      final map = readMap(item);
      final id = map == null ? _stringId(item) : _stringId(map['id']);
      if (id == null || present.contains(id) || missing.contains(id)) continue;
      missing.add(id);
    }
    return missing;
  }

  factory ExternalPlaylist.fromNeteasePayload(
    dynamic payload, {
    required String sourceUrl,
    List<dynamic> extraSongs = const [],
  }) {
    final root = _decodedMap(payload);
    final playlist = readMap(root?['playlist']);
    if (playlist == null) {
      throw const ExternalPlaylistException('网易云没有返回这个歌单，请确认链接有效，且歌单是公开歌单。');
    }

    final baseTracks = <MapEntry<String?, ExternalTrack>>[];
    for (final item in readList(playlist['tracks'])) {
      final map = readMap(item);
      final track = _neteaseTrack(map);
      if (track != null) baseTracks.add(MapEntry(_neteaseId(map), track));
    }
    final extraById = <String, ExternalTrack>{};
    for (final item in extraSongs) {
      final map = readMap(item);
      final track = _neteaseTrack(map);
      final id = _neteaseId(map);
      if (track != null && id != null) {
        extraById.putIfAbsent(id, () => track);
      }
    }

    final tracks = <ExternalTrack>[];
    final seenIds = <String>{};
    final seenFallback = <String>{};
    void add(ExternalTrack? track, String? id) {
      if (track == null) return;
      if (id != null) {
        if (!seenIds.add(id)) return;
      } else {
        final key = '${track.title}\u0000${track.artist}';
        if (!seenFallback.add(key)) return;
      }
      tracks.add(track);
    }

    final baseById = <String, ExternalTrack>{};
    for (final entry in baseTracks) {
      final id = entry.key;
      if (id != null) baseById.putIfAbsent(id, () => entry.value);
    }

    final trackIds = <String>[];
    for (final item in readList(playlist['trackIds'])) {
      final map = readMap(item);
      final id = map == null ? _stringId(item) : _stringId(map['id']);
      if (id != null && !trackIds.contains(id)) trackIds.add(id);
    }

    if (trackIds.isEmpty) {
      for (final entry in baseTracks) {
        add(entry.value, entry.key);
      }
      for (final entry in extraById.entries) {
        add(entry.value, entry.key);
      }
    } else {
      for (final id in trackIds) {
        add(baseById[id] ?? extraById[id], id);
      }
      for (final entry in baseTracks) {
        add(entry.value, entry.key);
      }
      for (final entry in extraById.entries) {
        add(entry.value, entry.key);
      }
    }

    if (tracks.isEmpty) {
      throw const ExternalPlaylistException('这个网易云歌单没有可读取的公开曲目，可能已下架或需要登录才能查看。');
    }

    final declared = readInt(playlist['trackCount'], tracks.length);
    final total = math.max(declared, math.max(trackIds.length, tracks.length));
    return ExternalPlaylist(
      platform: ExternalPlatform.netease,
      sourceUrl: sourceUrl,
      name: _fallbackName(readString(playlist['name']), '网易云歌单'),
      tracks: List.unmodifiable(tracks),
      totalCount: total,
      coverUrl: _httpsImage(readString(playlist['coverImgUrl'])),
      isPartial: tracks.length < total,
    );
  }

  factory ExternalPlaylist.fromQqPayload(dynamic payload, {required String sourceUrl}) {
    final root = _decodedMap(payload);
    final code = readInt(root?['code']);
    final list = readList(root?['cdlist']);
    final cdlist = list.isEmpty ? null : readMap(list.first);
    if (root == null || cdlist == null) {
      final message = readString(root?['msg'] ?? root?['message']).trim();
      throw ExternalPlaylistException(
        message.isEmpty
            ? 'QQ音乐没有返回这个歌单（错误码 $code），请确认歌单是公开的。'
            : 'QQ音乐没有返回这个歌单：$message',
      );
    }

    final tracks = <ExternalTrack>[];
    for (final item in readList(cdlist['songlist'])) {
      final map = readMap(item);
      if (map == null) continue;
      final title = readString(map['songname'] ?? map['name']).trim();
      if (title.isEmpty) continue;
      final artists = readList(map['singer'])
          .map((singer) => readString(readMap(singer)?['name']).trim())
          .where((name) => name.isNotEmpty);
      tracks.add(ExternalTrack(title: title, artist: artists.join(' / ')));
    }

    if (tracks.isEmpty) {
      throw const ExternalPlaylistException('这个QQ音乐歌单没有可读取的公开曲目，可能已下架或仅自己可见。');
    }

    final declared = readInt(cdlist['songnum'], tracks.length);
    return ExternalPlaylist(
      platform: ExternalPlatform.qqMusic,
      sourceUrl: sourceUrl,
      name: _fallbackName(readString(cdlist['dissname']), 'QQ音乐歌单'),
      tracks: List.unmodifiable(tracks),
      totalCount: declared < tracks.length ? tracks.length : declared,
      coverUrl: _httpsImage(
        readString(cdlist['logo'] ?? cdlist['cover'] ?? cdlist['imgurl']),
      ),
    );
  }

  factory ExternalPlaylist.fromKugouPage(
    String html, {
    required String sourceUrl,
    List<dynamic> apiSongs = const [],
    int apiTotal = 0,
  }) {
    final info = _extractJsonObject(html, 'var specialInfo');
    final rawSongs = _extractJsonArray(html, 'var data');
    if (rawSongs == null) {
      throw const ExternalPlaylistException('没有在酷狗页面里找到歌单曲目，请确认链接指向公开歌单。');
    }

    final pageTracks = <ExternalTrack>[];
    for (final item in rawSongs) {
      final track = _kugouTrack(readMap(item));
      if (track != null) pageTracks.add(track);
    }
    final apiTracks = <ExternalTrack>[];
    for (final item in apiSongs) {
      final track = _kugouTrack(readMap(item));
      if (track != null) apiTracks.add(track);
    }
    final tracks = apiTracks.isNotEmpty ? apiTracks : pageTracks;

    if (tracks.isEmpty) {
      throw const ExternalPlaylistException('这个酷狗歌单没有可读取的公开曲目，可能已下架或需要登录才能查看。');
    }

    final declared = readInt(info?['percount']);
    final total = math.max(math.max(declared, apiTotal), tracks.length);
    final partial = tracks.length < total;
    final pageLimited = html.contains('查看更多内容');
    return ExternalPlaylist(
      platform: ExternalPlatform.kugou,
      sourceUrl: sourceUrl,
      name: _fallbackName(readString(info?['name']), '酷狗歌单'),
      tracks: List.unmodifiable(tracks),
      totalCount: total,
      coverUrl: _httpsImage(readString(info?['image'])),
      isPartial: partial || (pageLimited && apiTracks.isEmpty),
      limitNote: partial && pageLimited && apiTracks.isEmpty
          ? '酷狗网页版只公开前 ${tracks.length} 首'
                '${total > tracks.length ? '（原歌单 $total 首）' : ''}，'
                '本次导入以这些曲目为准。'
          : '',
    );
  }
}

/// 已导入歌单：保存匹配到的咪咕曲目与未匹配清单。
class ImportedPlaylist {
  const ImportedPlaylist({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.platform,
    required this.importedAt,
    required this.totalTracks,
    required this.scannedTracks,
    required this.partial,
    required this.songs,
    required this.unmatchedTitles,
    this.coverUrl,
    this.limitNote = '',
  });

  final String id;
  final String name;
  final String sourceUrl;
  final ExternalPlatform platform;
  final String? coverUrl;
  final DateTime importedAt;
  final int totalTracks;
  final int scannedTracks;
  final bool partial;
  final String limitNote;
  final List<Song> songs;
  final List<String> unmatchedTitles;

  int get matchedCount => songs.length;
  int get unmatchedCount => unmatchedTitles.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'source_url': sourceUrl,
      'platform': platform.name,
      'cover_url': coverUrl,
      'imported_at': importedAt.toIso8601String(),
      'total_tracks': totalTracks,
      'scanned_tracks': scannedTracks,
      'partial': partial,
      'limit_note': limitNote,
      'songs': songs.map(_songToJson).toList(),
      'unmatched_titles': unmatchedTitles,
    };
  }

  static ImportedPlaylist? tryParse(dynamic payload) {
    final json = readMap(payload);
    if (json == null) return null;
    final id = readString(json['id']).trim();
    final name = readString(json['name']).trim();
    final platformName = readString(json['platform']).trim();
    ExternalPlatform? platform;
    for (final value in ExternalPlatform.values) {
      if (value.name == platformName) {
        platform = value;
        break;
      }
    }
    if (id.isEmpty || name.isEmpty || platform == null) return null;

    final songs = <Song>[];
    for (final item in readList(json['songs'])) {
      final map = readMap(item);
      if (map == null) continue;
      final song = _songFromJson(map);
      if (song.contentId.isNotEmpty) songs.add(song);
    }

    return ImportedPlaylist(
      id: id,
      name: name,
      sourceUrl: readString(json['source_url']),
      platform: platform,
      coverUrl: readString(json['cover_url']).isEmpty
          ? null
          : readString(json['cover_url']),
      importedAt: DateTime.tryParse(readString(json['imported_at'])) ?? DateTime.now(),
      totalTracks: readInt(json['total_tracks'], songs.length),
      scannedTracks: readInt(json['scanned_tracks'], songs.length),
      partial: json['partial'] == true,
      limitNote: readString(json['limit_note']),
      songs: List.unmodifiable(songs),
      unmatchedTitles: readStringList(json['unmatched_titles']),
    );
  }
}

Map<String, dynamic> _songToJson(Song song) {
  return {
    'content_id': song.contentId,
    'song_id': song.songId,
    'copyright_id': song.copyrightId,
    'name': song.name,
    'artists': song.artistNames,
    'album': song.album,
    'album_id': song.albumId,
    'duration': song.duration.inSeconds,
    'cover_url': song.coverUrl,
    'lyric_url': song.lyricUrl,
    'vip_only': song.isVipOnly,
    'resource_type': song.playbackResourceType,
  };
}

Song _songFromJson(Map<String, dynamic> json) {
  return Song(
    contentId: readString(json['content_id']),
    songId: readString(json['song_id']),
    copyrightId: readString(json['copyright_id']),
    name: readString(json['name'], '未知歌曲'),
    artistNames: readStringList(json['artists']),
    album: readString(json['album'], '未知专辑'),
    albumId: readString(json['album_id']),
    duration: Duration(seconds: readInt(json['duration'])),
    coverUrl: readString(json['cover_url']).isEmpty
        ? null
        : readString(json['cover_url']),
    lyricUrl: readString(json['lyric_url']).isEmpty
        ? null
        : readString(json['lyric_url']),
    isVipOnly: json['vip_only'] == true,
    playbackResourceType: readInt(json['resource_type'], 2),
  );
}

dynamic _decodeJson(dynamic payload) {
  if (payload is! String) return payload;
  final text = payload.trim();
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _decodedMap(dynamic payload) {
  return readMap(_decodeJson(payload));
}

String _fallbackName(String raw, String fallback) {
  final value = raw.trim();
  return value.isEmpty ? fallback : value;
}

String? _httpsImage(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('http://')) {
    return 'https://${value.substring('http://'.length)}';
  }
  if (value.startsWith('//')) return 'https:$value';
  return value;
}

ExternalTrack? _neteaseTrack(Map<String, dynamic>? map) {
  if (map == null) return null;
  final title = readString(map['name']).trim();
  if (title.isEmpty) return null;
  final artists = readList(map['ar'] ?? map['artists'])
      .map((artist) => readString(readMap(artist)?['name']).trim())
      .where((name) => name.isNotEmpty);
  return ExternalTrack(title: title, artist: artists.join(' / '));
}

String? _neteaseId(Map<String, dynamic>? map) => _stringId(map?['id']);

String? _stringId(dynamic value) {
  if (value is int) return value == 0 ? null : '$value';
  final text = readString(value).trim();
  return text.isEmpty || text == '0' ? null : text;
}

/// 酷狗移动接口只返回 `filename: "歌手 - 歌名"`，网页版则给出结构化字段。
ExternalTrack? _kugouTrack(Map<String, dynamic>? map) {
  if (map == null) return null;
  final title = readString(map['songname'] ?? map['audio_name']).trim();
  if (title.isNotEmpty) {
    var artist = readString(map['singername']).trim();
    if (artist.isEmpty) {
      artist = readList(map['authors'])
          .map((author) => readString(readMap(author)?['author_name']).trim())
          .where((name) => name.isNotEmpty)
          .join(' / ');
    }
    return ExternalTrack(title: title, artist: artist);
  }

  final filename = readString(map['filename']).trim();
  if (filename.isEmpty) return null;
  final separator = filename.indexOf(' - ');
  if (separator <= 0) return ExternalTrack(title: filename, artist: '');
  return ExternalTrack(
    title: filename.substring(separator + 3).trim(),
    artist: filename.substring(0, separator).trim(),
  );
}

/// 从 `var data = [...]` 这类内联脚本里取出完整的 JSON 数组。
List<dynamic>? _extractJsonArray(String html, String marker) {
  final markerIndex = html.indexOf(marker);
  if (markerIndex < 0) return null;
  final start = html.indexOf('[', markerIndex);
  if (start < 0) return null;
  final slice = _balancedSlice(html, start, '[', ']');
  if (slice == null) return null;
  final decoded = _decodeJson(slice);
  return decoded is List ? decoded : null;
}

Map<String, dynamic>? _extractJsonObject(String html, String marker) {
  final markerIndex = html.indexOf(marker);
  if (markerIndex < 0) return null;
  final start = html.indexOf('{', markerIndex);
  if (start < 0) return null;
  final slice = _balancedSlice(html, start, '{', '}');
  if (slice == null) return null;
  return _decodedMap(slice);
}

/// 括号配对时跳过 JSON 字符串内容，避免标题里的括号或分号提前结束。
String? _balancedSlice(String text, int start, String open, String close) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (inString) {
      if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == open) {
      depth++;
    } else if (char == close) {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}
