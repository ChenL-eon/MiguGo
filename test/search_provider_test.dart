import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/providers/search_provider.dart';
import 'package:migu_lele/providers/settings_provider.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMusicApi extends MiguMusicApi {
  _FakeMusicApi(this.pages);

  final Map<int, List<Song>> pages;
  final List<int> requestedPages = [];
  final Set<int> failPages = {};

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    int pageNo = 1,
    int pageSize = 30,
  }) async {
    requestedPages.add(pageNo);
    if (failPages.contains(pageNo)) {
      throw const MiguApiException('搜索服务暂时不可用。');
    }
    return pages[pageNo] ?? const [];
  }
}

List<Song> _songs(String prefix, int count) {
  return List.generate(
    count,
    (index) => Song(
      contentId: '${prefix}_$index',
      copyrightId: 'copyright_${prefix}_$index',
      name: '$prefix $index',
      artistNames: const ['测试歌手'],
      album: '测试专辑',
      duration: const Duration(seconds: 180),
      isVipOnly: false,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('第一页 20 首时显示可继续加载，加载后追加下一页', () async {
    final api = _FakeMusicApi({1: _songs('第一页', 20), 2: _songs('第二页', 5)});
    final settings = SettingsProvider();
    await settings.load();
    final provider = SearchProvider(api, settings);

    await provider.submit('周杰伦');

    expect(provider.songs.length, 20);
    expect(provider.songsHasMore, isTrue);
    expect(provider.songsLoadingMore, isFalse);

    await provider.loadMoreSongs();

    expect(provider.songs.length, 25);
    expect(provider.songsHasMore, isFalse);
    expect(provider.songsLoadingMore, isFalse);
    expect(api.requestedPages, [1, 2]);
  });

  test('加载更多失败时保留已有结果，重试后成功追加', () async {
    final api = _FakeMusicApi({1: _songs('第一页', 20), 2: _songs('第二页', 3)});
    api.failPages.add(2);
    final settings = SettingsProvider();
    await settings.load();
    final provider = SearchProvider(api, settings);

    await provider.submit('林俊杰');
    await provider.loadMoreSongs();

    expect(provider.songs.length, 20);
    expect(provider.songsLoadMoreError, '搜索服务暂时不可用。');
    expect(provider.songsHasMore, isTrue);

    api.failPages.clear();
    await provider.loadMoreSongs();

    expect(provider.songs.length, 23);
    expect(provider.songsLoadMoreError, isNull);
    expect(provider.songsHasMore, isFalse);
  });
}
