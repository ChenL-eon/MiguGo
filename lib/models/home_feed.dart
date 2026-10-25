import '../core/utils/json_read.dart';
import '../core/utils/migu_urls.dart';
import 'playlist.dart';
import 'song.dart';

/// 首页推送数据：咪咕每日推荐歌曲 + 推荐歌单。
class HomeFeed {
  const HomeFeed({required this.songs, required this.playlists, this.date});

  final List<Song> songs;
  final List<PlaylistSummary> playlists;
  final DateTime? date;

  static List<Song> songsFromDailyPayload(dynamic payload) {
    final recommend = readMap(readMap(readMap(payload)?['data'])?['recommendData']);
    final songs = <Song>[];
    final seen = <String>{};
    for (final item in readList(recommend?['data'])) {
      final map = readMap(item);
      if (map == null) continue;
      final song = Song.fromJson(map);
      if (song.contentId.isEmpty || song.name.isEmpty) continue;
      if (seen.add(song.contentId)) songs.add(song);
    }
    return songs;
  }

  static DateTime? dateFromDailyPayload(dynamic payload) {
    final recommend = readMap(readMap(readMap(payload)?['data'])?['recommendData']);
    final raw = readString(recommend?['time']).trim();
    return DateTime.tryParse(raw);
  }

  static List<PlaylistSummary> playlistsFromIndexPayload(dynamic payload) {
    final sections = readList(readMap(readMap(payload)?['data'])?['contents']);
    for (final rawSection in sections) {
      final section = readMap(rawSection);
      if (section == null) continue;
      if (readString(section['view']) != 'ZJ-SongList-Scroll') continue;

      final playlists = <PlaylistSummary>[];
      final seen = <String>{};
      for (final rawItem in readList(section['contents'])) {
        final item = readMap(rawItem);
        if (item == null) continue;
        final id = readString(item['resId']).trim();
        if (id.isEmpty || !seen.add(id)) continue;
        playlists.add(
          PlaylistSummary(
            id: id,
            name: readString(item['txt'], '推荐歌单').trim(),
            coverUrl: resolveMiguAssetUrl(readString(item['img'])),
          ),
        );
      }
      if (playlists.isNotEmpty) return playlists;
    }
    return const [];
  }
}
