import '../core/utils/json_read.dart';
import '../core/utils/migu_urls.dart';
import 'playlist.dart';

/// 登录账号的歌单概览：我喜欢、自建歌单与收藏歌单。
///
/// 只读接口：不新建、不收藏，也不改动账号里的任何内容。
class AccountLibrary {
  const AccountLibrary({
    this.favoritePlaylist,
    this.createdPlaylists = const [],
    this.collectedPlaylists = const [],
  });

  /// 「喜欢的音乐」这个歌曲列表；账号没有收藏单曲时为空。
  final PlaylistSummary? favoritePlaylist;
  final List<PlaylistSummary> createdPlaylists;
  final List<PlaylistSummary> collectedPlaylists;

  bool get isEmpty =>
      favoritePlaylist == null &&
      createdPlaylists.isEmpty &&
      collectedPlaylists.isEmpty;

  /// [json] 为 `pc/user/home-page/v2.0` 响应的 `data` 节点。
  factory AccountLibrary.fromHomePageJson(Map<String, dynamic> json) {
    final data = readMap(json['data']) ?? json;
    return AccountLibrary(
      favoritePlaylist: _favoriteFrom(readList(data['userPrivateItems'])),
      createdPlaylists: _playlistsFrom(
        readMap(data['myCreatedMusicLists'])?['createdMusicLists'],
      ),
      collectedPlaylists: _playlistsFrom(
        readMap(data['myCollectedMusicLists'])?['collectMusicLists'],
      ),
    );
  }

  /// 「喜欢的音乐」混在个人入口里，靠 actionUrl 里的 musicListId 识别。
  static PlaylistSummary? _favoriteFrom(List<dynamic> items) {
    Map<String, dynamic>? matched;
    for (final raw in items) {
      final item = readMap(raw);
      if (item == null) continue;
      final actionUrl = readString(item['actionUrl']);
      if (_playlistIdFrom(actionUrl) == null) continue;
      matched = item;
      if (actionUrl.contains('favorite')) break;
    }
    if (matched == null) return null;

    final id = _playlistIdFrom(readString(matched['actionUrl']));
    if (id == null) return null;
    final title = readString(matched['title']).trim();
    return PlaylistSummary(
      id: id,
      name: title.isEmpty ? '我喜欢的音乐' : title,
      coverUrl: resolveMiguAssetUrl(readString(matched['picUrl'])),
      songCount: _songCountFrom(readString(matched['subTitle'])),
    );
  }

  static List<PlaylistSummary> _playlistsFrom(dynamic raw) {
    final seen = <String>{};
    final playlists = <PlaylistSummary>[];
    for (final item in readList(raw)) {
      final map = readMap(item);
      if (map == null) continue;
      final playlist = PlaylistSummary.fromInfoJson(map);
      if (playlist.id.isEmpty || !seen.add(playlist.id)) continue;
      playlists.add(playlist);
    }
    return List<PlaylistSummary>.unmodifiable(playlists);
  }

  static String? _playlistIdFrom(String actionUrl) {
    final match = RegExp(r'(?:musicListId|playlistId)=(\d+)').firstMatch(actionUrl);
    return match?.group(1);
  }

  /// 「喜欢的音乐」条目的副标题形如「12首」；不是这个格式就当未知。
  static int _songCountFrom(String subtitle) {
    final match = RegExp(r'(\d+)\s*首').firstMatch(subtitle);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
