import 'dart:async';

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
  _FakeExternalService(this.playlist);

  final ExternalPlaylist playlist;

  @override
  Future<ExternalPlaylist> fetchPlaylist(
    ExternalPlaylistLink link, {
    int maxTracks = 0,
  }) async {
    return playlist;
  }
}

class _FakeMusicApi extends MiguMusicApi {
  final Map<String, List<Song>> results = {};
  final List<String> queries = [];

  /// 命中这些关键词时抛出的错误，用来模拟限流与一次性失败。
  final Map<String, Object> failures = {};

  /// 每次搜索都会先经过这里；测试用它把某次搜索卡在闸门上。
  Future<void> Function(String keyword)? onSearch;

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    int pageNo = 1,
    int pageSize = 30,
  }) async {
    queries.add(keyword);
    await onSearch?.call(keyword);
    final failure = failures[keyword];
    if (failure != null) throw failure;
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

ExternalPlaylist _playlistWith(List<String> titles) {
  return ExternalPlaylist(
    platform: ExternalPlatform.netease,
    sourceUrl: 'https://music.163.com/playlist?id=1',
    name: '测试歌单',
    tracks: [for (final title in titles) ExternalTrack(title: title, artist: '周杰伦')],
    totalCount: titles.length,
    coverUrl: 'https://p1.music.126.net/cover.jpg',
  );
}

const String _link = 'https://music.163.com/playlist?id=1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('外部歌单导入的限流与取消', () {
    test('咪咕限流时说清是被限流，并且退避后停手而不是一路试完', () async {
      final api = _FakeMusicApi();
      for (var i = 0; i < 30; i++) {
        api.failures['歌$i 周杰伦'] = const MiguApiException(
          '访问过于频繁，请稍后再试。',
          kind: MiguErrorKind.rateLimited,
        );
      }
      final backoffs = <Duration>[];
      final provider = ImportedPlaylistProvider(
        _FakeExternalService(_playlistWith([for (var i = 0; i < 30; i++) '歌$i'])),
        api,
        backoffWait: (delay) async {
          backoffs.add(delay);
        },
      );
      await provider.load();

      final ok = await provider.importFromLink(_link);

      expect(ok, isFalse);
      expect(provider.error, contains('频繁'), reason: '限流要能看出来，不是「没匹配到」');
      expect(provider.playlists, isEmpty);
      expect(backoffs, isNotEmpty, reason: '撞限流要先退避再重试');
      expect(backoffs.first, greaterThanOrEqualTo(const Duration(seconds: 5)));
      expect(api.queries.length, lessThan(20), reason: '退避后仍限流就该停掉整批，不该把 30 首全试一遍');
    });

    test('单首查询失败不算「咪咕没有这首歌」', () async {
      final api = _FakeMusicApi();
      api.results['晴天 周杰伦'] = [_song('晴天')];
      api.failures['稻香 周杰伦'] = const MiguApiException('咪咕接口暂时不可用。');
      final provider = ImportedPlaylistProvider(
        _FakeExternalService(_playlistWith(['晴天', '稻香', '不存在的歌'])),
        api,
      );
      await provider.load();

      final ok = await provider.importFromLink(_link);

      expect(ok, isTrue);
      final imported = provider.playlists.single;
      expect(imported.songs.map((song) => song.name), ['晴天']);
      expect(imported.unmatchedTitles, ['不存在的歌'], reason: '查询失败的曲目不能被记成库里没有');
      expect(imported.limitNote, contains('查询失败'));
    });

    test('取消后在途结果不写入本机歌单', () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      final api = _FakeMusicApi()
        ..results['晴天 周杰伦'] = [_song('晴天')]
        ..results['稻香 周杰伦'] = [_song('稻香')]
        ..onSearch = (keyword) async {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
        };
      final provider = ImportedPlaylistProvider(
        _FakeExternalService(_playlistWith(['晴天', '稻香'])),
        api,
      );
      await provider.load();

      final running = provider.importFromLink(_link);
      await entered.future;
      provider.cancel();

      expect(provider.importing, isFalse);
      expect(provider.error, isNull, reason: '用户自己取消的不算失败');

      gate.complete();
      final ok = await running;

      expect(ok, isFalse);
      expect(provider.playlists, isEmpty);
      expect(provider.lastImport, isNull);
    });

    test('结果没能落盘时要明确说出来', () async {
      final api = _FakeMusicApi()..results['晴天 周杰伦'] = [_song('晴天')];
      final provider = ImportedPlaylistProvider(
        _FakeExternalService(_playlistWith(['晴天'])),
        api,
        persistor: (_) async => false,
      );
      await provider.load();

      final ok = await provider.importFromLink(_link);

      expect(ok, isTrue, reason: '本次会话里歌单仍然可用');
      expect(provider.error, contains('没能保存'));
      expect(provider.lastImport?.songs, hasLength(1));
    });
  });
}
