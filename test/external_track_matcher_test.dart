import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/imported_playlist.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/services/external/external_track_matcher.dart';

Song _song(String name, List<String> artists) {
  return Song(
    contentId: 'content_$name',
    copyrightId: 'copyright_$name',
    name: name,
    artistNames: artists,
    album: '测试专辑',
    duration: const Duration(seconds: 210),
    isVipOnly: false,
  );
}

void main() {
  group('歌名归一化', () {
    test('去掉括号补充说明、说唱标记与标点', () {
      expect(ExternalTrackMatcher.normalizeTitle('七里香 (Live版)'), '七里香');
      expect(
        ExternalTrackMatcher.normalizeTitle('Love Story（Taylor’s Version）'),
        'lovestory',
      );
      expect(ExternalTrackMatcher.normalizeTitle('起风了 feat. 某某'), '起风了');
      expect(ExternalTrackMatcher.normalizeTitle('《演员》'), '演员');
    });

    test('全角字符按半角比较', () {
      expect(ExternalTrackMatcher.normalizeTitle('ＬＯＶＥ'), 'love');
    });
  });

  group('曲目匹配', () {
    test('同名时优先歌手一致的版本', () {
      final track = const ExternalTrack(title: '晴天', artist: '周杰伦');
      final candidates = [
        _song('晴天', const ['翻唱歌手']),
        _song('晴天', const ['周杰伦']),
      ];
      final match = ExternalTrackMatcher.pickBest(track, candidates);
      expect(match, isNotNull);
      expect(match!.artistNames, contains('周杰伦'));
    });

    test('歌名完全一致时即使歌手缺失也接受', () {
      final track = const ExternalTrack(title: '起风了', artist: '');
      final match = ExternalTrackMatcher.pickBest(track, [
        _song('起风了', const ['买辣椒也用券']),
      ]);
      expect(match, isNotNull);
    });

    test('歌名只是包含关系时必须歌手重合', () {
      final track = const ExternalTrack(title: '晴天', artist: '李四');
      expect(
        ExternalTrackMatcher.pickBest(track, [
          _song('晴天娃娃', const ['王五']),
        ]),
        isNull,
      );
      expect(
        ExternalTrackMatcher.pickBest(track, [
          _song('晴天娃娃', const ['李四']),
        ]),
        isNotNull,
      );
    });

    test('括号版本差异仍能匹配', () {
      final track = const ExternalTrack(title: '七里香 (Live)', artist: '周杰伦');
      final match = ExternalTrackMatcher.pickBest(track, [
        _song('七里香', const ['周杰伦']),
      ]);
      expect(match, isNotNull);
    });

    test('没有相近歌名时返回空', () {
      expect(
        ExternalTrackMatcher.pickBest(
          const ExternalTrack(title: '不存在的歌', artist: '某人'),
          [
            _song('晴天', const ['周杰伦']),
          ],
        ),
        isNull,
      );
    });
  });

  group('歌手与搜索词', () {
    test('多歌手的任意一人重合即视为匹配', () {
      expect(ExternalTrackMatcher.artistsOverlap('周杰伦 / 方文山', const ['周杰伦']), isTrue);
      expect(ExternalTrackMatcher.artistsOverlap('林俊杰', const ['周杰伦']), isFalse);
    });

    test('搜索词去掉括号并用第一位歌手', () {
      expect(
        ExternalTrackMatcher.buildSearchQuery(
          const ExternalTrack(title: '七里香 (Live版)', artist: '周杰伦 / 方文山'),
        ),
        '七里香 周杰伦',
      );
    });

    test('没有歌手时只用歌名搜索', () {
      expect(
        ExternalTrackMatcher.buildSearchQuery(
          const ExternalTrack(title: '纯音乐', artist: ''),
        ),
        '纯音乐',
      );
    });
  });
}
