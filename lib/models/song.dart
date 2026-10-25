import '../core/constants/app_constants.dart';
import '../core/utils/json_read.dart';
import '../core/utils/migu_urls.dart';

/// 歌曲元数据。音频本身只以在线流的形式交给播放器，不在本地落盘。
class Song {
  const Song({
    required this.contentId,
    required this.copyrightId,
    required this.name,
    required this.artistNames,
    required this.album,
    required this.duration,
    required this.isVipOnly,
    this.songId = '',
    this.albumId = '',
    this.coverUrl,
    this.coverUrlLarge,
    this.lyricUrl,
    this.playbackResourceType = AppConstants.playbackResourceType,
  });

  final String contentId;
  final String songId;
  final String copyrightId;
  final String name;
  final List<String> artistNames;
  final String album;
  final String albumId;
  final Duration duration;
  final String? coverUrl;

  /// 同一张封面的高分辨率地址，供播放页这类大图位置使用。
  ///
  /// 咪咕接口用 img1/img2/img3 返回 200/400/800 三档，列表缩略图继续用
  /// [coverUrl] 的最小档省流量，只有整屏封面才值得拉大图。
  final String? coverUrlLarge;
  final String? lyricUrl;
  final bool isVipOnly;
  final int playbackResourceType;

  String get artist {
    if (artistNames.isEmpty) return '未知歌手';
    return artistNames.join(' / ');
  }

  bool get hasLyric => lyricUrl != null && lyricUrl!.isNotEmpty;

  factory Song.fromJson(Map<String, dynamic> json) {
    final singerList = readList(json['singerList']);
    final artists = singerList
        .map((item) => readString(readMap(item)?['name']))
        .where((name) => name.isNotEmpty)
        .toList();
    if (artists.isEmpty) {
      final fallback = readString(
        json['singerName'] ?? json['artistName'] ?? json['singer'],
      );
      if (fallback.isNotEmpty) artists.addAll(fallback.split('/'));
    }

    final formats = readList(json['audioFormats']);
    Map<String, dynamic>? pqFormat;
    for (final item in formats) {
      final format = readMap(item);
      if (format == null) continue;
      if (readString(format['formatType']).toUpperCase() == 'PQ') {
        pqFormat = format;
        break;
      }
    }

    final pqTags = <String>{
      ...readStringList(pqFormat?['showTagsNew']),
      ...readStringList(pqFormat?['showTags']),
    }.map((tag) => tag.toLowerCase());
    final vipOnly =
        readInt(json['restrictType']) == 1 ||
        pqTags.any((tag) => tag == 'vip' || tag == 'tl-vip');

    final ext = readMap(json['ext']);
    final lyricUrl = resolveMiguAssetUrl(
      readString(json['lrcUrl'] ?? ext?['lrcUrl'] ?? json['lyricUrl']),
    );

    final cover = resolveMiguAssetUrl(
      readString(
        json['img1'] ??
            json['img2'] ??
            json['img3'] ??
            json['albumPic'] ??
            json['cover'],
      ),
    );
    final coverLarge =
        resolveMiguAssetUrl(readString(json['img3'] ?? json['img2'] ?? json['img1'])) ??
        cover;

    final contentId = readString(
      json['contentId'] ?? json['copyrightId'] ?? json['songId'],
    );

    return Song(
      contentId: contentId,
      songId: readString(json['songId']),
      copyrightId: readString(json['copyrightId']),
      name: readString(json['songName'] ?? json['name'], '未知歌曲').trim(),
      artistNames: artists,
      album: readString(json['album'] ?? json['albumName'], '未知专辑').trim(),
      albumId: readString(json['albumId']),
      duration: Duration(seconds: readInt(json['duration'])),
      coverUrl: cover,
      coverUrlLarge: coverLarge,
      lyricUrl: lyricUrl,
      isVipOnly: vipOnly,
      playbackResourceType: readInt(
        pqFormat?['resourceType'],
        AppConstants.playbackResourceType,
      ),
    );
  }
}
