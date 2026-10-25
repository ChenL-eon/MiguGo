import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/external_playlist_urls.dart';
import 'package:migu_lele/models/imported_playlist.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/providers/imported_playlist_provider.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/external/external_playlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeExternalService extends ExternalPlaylistService {
  _FakeExternalService({this.playlist, this.error});

  final ExternalPlaylist? playlist;
  final Object? error;

  @override
  Future<ExternalPlaylist> fetchPlaylist(
    ExternalPlaylistLink link, {
    int maxTracks = 0,
  }) async {
    if (error != null) throw error!;
    return playlist!;
  }
}

class _FakeMusicApi extends MiguMusicApi {
  final Map<String, List<Song>> results = {};
  final List<String> queries = [];
  bool failSearches = false;

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    int pageNo = 1,
    int pageSize = 30,
  }) async {
    queries.add(keyword);
    if (failSearches) {
      throw const MiguApiException('搜索服务暂时不可用。');
    }
    return results[keyword] ?? const [];
  }
}

Song _song(String name) {
  return Song(
    contentId: 'content_$name',
    copyrightId: 'copyright_$name',
    name: name,
    artistNames: const ['周杰伦'],
    album: '测试专辑',
    duration: const Duration(seconds: 200),
    isVipOnly: false,
  );
}

ExternalPlaylist _externalPlaylist() {
  return const ExternalPlaylist(
    platform: ExternalPlatform.netease,
    sourceUrl: 'https://music.163.com/playlist?id=1',
    name: '测试歌单',
    tracks: [
      ExternalTrack(title: '晴天', artist: '周杰伦'),
      ExternalTrack(title: '稻香', artist: '周杰伦'),
      ExternalTrack(title: '不存在的歌', artist: '某人'),
    ],
    totalCount: 3,
    coverUrl: 'https://p1.music.126.net/cover.jpg',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('导入时逐首匹配、保持顺序并持久化', () async {
    final service = _FakeExternalService(playlist: _externalPlaylist());
    final api = _FakeMusicApi();
    api.results['晴天 周杰伦'] = [_song('晴天')];
    api.results['稻香 周杰伦'] = [_song('稻香')];

    final provider = ImportedPlaylistProvider(service, api);
    await provider.load();
    final ok = await provider.importFromLink('https://music.163.com/playlist?id=1');

    expect(ok, isTrue);
    expect(provider.error, isNull);
    expect(provider.importing, isFalse);
    expect(provider.playlists, hasLength(1));

    final imported = provider.playlists.single;
    expect(imported.name, '测试歌单');
    expect(imported.platform, ExternalPlatform.netease);
    expect(imported.songs.map((song) => song.name), ['晴天', '稻香']);
    expect(imported.unmatchedTitles, ['不存在的歌']);
    expect(imported.scannedTracks, 3);
    expect(imported.totalTracks, 3);
    expect(imported.partial, isFalse);
    expect(provider.lastImport?.id, imported.id);

    final restored = ImportedPlaylistProvider(service, api);
    await restored.load();
    expect(restored.playlists, hasLength(1));
    expect(restored.playlists.single.songs, hasLength(2));
    expect(restored.playlists.single.unmatchedTitles, ['不存在的歌']);
  });

  test('读取外部歌单失败时保留可读错误', () async {
    final provider = ImportedPlaylistProvider(
      _FakeExternalService(error: const ExternalPlaylistException('网易云拒绝读取这个歌单。')),
      _FakeMusicApi(),
    );
    await provider.load();
    final ok = await provider.importFromLink('https://music.163.com/playlist?id=1');

    expect(ok, isFalse);
    expect(provider.error, '网易云拒绝读取这个歌单。');
    expect(provider.importing, isFalse);
    expect(provider.playlists, isEmpty);
  });

  test('咪咕搜索全部失败时不会保存空歌单', () async {
    final api = _FakeMusicApi()..failSearches = true;
    final provider = ImportedPlaylistProvider(
      _FakeExternalService(playlist: _externalPlaylist()),
      api,
    );
    await provider.load();
    final ok = await provider.importFromLink('https://music.163.com/playlist?id=1');

    expect(ok, isFalse);
    expect(provider.error, contains('匹配咪咕曲库失败'));
    expect(provider.playlists, isEmpty);
  });

  test('无法识别的链接直接提示', () async {
    final provider = ImportedPlaylistProvider(
      _FakeExternalService(playlist: _externalPlaylist()),
      _FakeMusicApi(),
    );
    await provider.load();
    final ok = await provider.importFromLink('随便一段没有链接的文字');

    expect(ok, isFalse);
    expect(provider.error, contains('无法识别这个链接'));
  });

  test('移除导入结果会同步写入本机存储', () async {
    final service = _FakeExternalService(playlist: _externalPlaylist());
    final api = _FakeMusicApi();
    api.results['晴天 周杰伦'] = [_song('晴天')];
    api.results['稻香 周杰伦'] = [_song('稻香')];

    final provider = ImportedPlaylistProvider(service, api);
    await provider.load();
    await provider.importFromLink('https://music.163.com/playlist?id=1');
    final id = provider.playlists.single.id;

    await provider.remove(id);
    expect(provider.playlists, isEmpty);
    expect(provider.lastImport, isNull);

    final restored = ImportedPlaylistProvider(service, api);
    await restored.load();
    expect(restored.playlists, isEmpty);
  });
}
