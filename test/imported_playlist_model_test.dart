import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/external_playlist_urls.dart';
import 'package:migu_lele/models/imported_playlist.dart';
import 'package:migu_lele/models/song.dart';

void main() {
  group('导入歌单持久化', () {
    final importedAt = DateTime(2026, 10, 21, 15, 30);
    final song = Song(
      contentId: 'content_1',
      songId: 'song_1',
      copyrightId: 'copyright_1',
      name: '晴天',
      artistNames: const ['周杰伦'],
      album: '叶惠美',
      albumId: 'album_1',
      duration: const Duration(seconds: 269),
      coverUrl: 'https://d.musicapp.migu.cn/cover.jpg',
      lyricUrl: 'https://d.musicapp.migu.cn/lyric.lrc',
      isVipOnly: true,
      playbackResourceType: 4,
    );

    final playlist = ImportedPlaylist(
      id: 'netease_1',
      name: '华语流行',
      sourceUrl: 'https://music.163.com/playlist?id=1',
      platform: ExternalPlatform.netease,
      coverUrl: 'https://p1.music.126.net/cover.jpg',
      importedAt: importedAt,
      totalTracks: 60,
      scannedTracks: 50,
      partial: true,
      limitNote: '原歌单共 60 首，本次扫描了前 50 首。',
      songs: [song],
      unmatchedTitles: const ['没有收录的歌'],
    );

    test('序列化后再读回保持完整', () {
      final restored = ImportedPlaylist.tryParse(playlist.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, 'netease_1');
      expect(restored.name, '华语流行');
      expect(restored.sourceUrl, 'https://music.163.com/playlist?id=1');
      expect(restored.platform, ExternalPlatform.netease);
      expect(restored.coverUrl, 'https://p1.music.126.net/cover.jpg');
      expect(restored.importedAt, importedAt);
      expect(restored.totalTracks, 60);
      expect(restored.scannedTracks, 50);
      expect(restored.partial, isTrue);
      expect(restored.limitNote, contains('60 首'));
      expect(restored.unmatchedTitles, ['没有收录的歌']);
      expect(restored.matchedCount, 1);

      final restoredSong = restored.songs.single;
      expect(restoredSong.contentId, 'content_1');
      expect(restoredSong.songId, 'song_1');
      expect(restoredSong.copyrightId, 'copyright_1');
      expect(restoredSong.name, '晴天');
      expect(restoredSong.artistNames, ['周杰伦']);
      expect(restoredSong.album, '叶惠美');
      expect(restoredSong.albumId, 'album_1');
      expect(restoredSong.duration, const Duration(seconds: 269));
      expect(restoredSong.coverUrl, 'https://d.musicapp.migu.cn/cover.jpg');
      expect(restoredSong.lyricUrl, 'https://d.musicapp.migu.cn/lyric.lrc');
      expect(restoredSong.isVipOnly, isTrue);
      expect(restoredSong.playbackResourceType, 4);
    });

    test('缺少必要字段的记录会被忽略', () {
      expect(ImportedPlaylist.tryParse({'name': '没有 ID'}), isNull);
      expect(
        ImportedPlaylist.tryParse({'id': 'x', 'name': '平台未知', 'platform': 'unknown'}),
        isNull,
      );
      expect(ImportedPlaylist.tryParse('not a map'), isNull);
    });

    test('缺少 contentId 的歌曲不会被保存', () {
      final restored = ImportedPlaylist.tryParse({
        'id': 'qq_1',
        'name': '测试',
        'platform': 'qqMusic',
        'imported_at': importedAt.toIso8601String(),
        'songs': [
          {
            'name': '无内容 ID',
            'artists': ['某人'],
          },
          {
            'content_id': 'ok',
            'name': '正常歌曲',
            'artists': ['某人'],
          },
        ],
        'unmatched_titles': <String>[],
      });
      expect(restored, isNotNull);
      expect(restored!.songs, hasLength(1));
      expect(restored.songs.single.name, '正常歌曲');
    });
  });
}
