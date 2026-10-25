import '../core/utils/formatters.dart';
import '../core/utils/json_read.dart';
import '../core/utils/migu_urls.dart';
import 'song.dart';

/// 歌单元信息，同时兼容搜索结果与歌单详情两种返回结构。
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    this.coverUrl,
    this.description = '',
    this.ownerName = '',
    this.songCount = 0,
    this.playCountLabel = '',
    this.tags = const [],
  });

  final String id;
  final String name;
  final String? coverUrl;
  final String description;
  final String ownerName;
  final int songCount;
  final String playCountLabel;
  final List<String> tags;

  factory PlaylistSummary.fromSearchJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: readString(json['id'] ?? json['musicListId'] ?? json['playlistId']),
      name: readString(json['name'] ?? json['title'], '未命名歌单'),
      coverUrl: resolveMiguAssetUrl(readString(json['musicListPicUrl'] ?? json['img'])),
      songCount: readInt(json['musicNum'] ?? json['songNum']),
      playCountLabel: compactNumber(readString(json['playNumDesc'] ?? json['playNum'])),
      tags: readStringList(json['ts'] ?? json['tags']),
    );
  }

  factory PlaylistSummary.fromInfoJson(Map<String, dynamic> json) {
    final imgItem = readMap(json['imgItem']);
    final opNumItem = readMap(json['opNumItem']);
    final tags = readList(json['tags'])
        .map((item) => readString(readMap(item)?['tagName']))
        .where((name) => name.isNotEmpty)
        .toList();

    return PlaylistSummary(
      id: readString(json['musicListId'] ?? json['id']),
      name: readString(json['title'] ?? json['name'], '未命名歌单'),
      coverUrl: resolveMiguAssetUrl(
        readString(
          json['originalImgUrl'] ??
              imgItem?['img'] ??
              imgItem?['webpImg'] ??
              json['musicListPicUrl'],
        ),
      ),
      description: readString(json['summary'] ?? json['description']).trim(),
      ownerName: readString(json['ownerName'] ?? json['userName']).trim(),
      songCount: readInt(json['musicNum'] ?? json['songNum']),
      playCountLabel: readString(opNumItem?['playNumDesc'] ?? json['playNumDesc']),
      tags: tags,
    );
  }
}

/// 歌单歌曲分页结果。
class PlaylistSongsPage {
  const PlaylistSongsPage({
    required this.songs,
    required this.totalCount,
    required this.pageNo,
    required this.pageSize,
  });

  final List<Song> songs;
  final int totalCount;
  final int pageNo;
  final int pageSize;

  bool get hasMore => songs.isNotEmpty && pageNo * pageSize < totalCount;
}
