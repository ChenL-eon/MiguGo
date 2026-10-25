import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/playlist.dart';
import 'package:migu_lele/models/song.dart';

void main() {
  group('Song.fromJson', () {
    test('解析基础信息与相对封面地址', () {
      final song = Song.fromJson({
        'contentId': '600000000001',
        'songId': '100001',
        'copyrightId': '900001',
        'songName': '晴天',
        'singerList': [
          {'name': '周杰伦'},
          {'name': '测试合唱'},
        ],
        'album': '叶惠美',
        'duration': 269,
        'img1': '/data/pic/cover.jpg',
        'lrcUrl': 'https://d.musicapp.migu.cn/lyric.lrc',
        'restrictType': 0,
        'audioFormats': [
          {
            'formatType': 'PQ',
            'resourceType': 2,
            'showTagsNew': ['HQ'],
          },
        ],
      });

      expect(song.contentId, '600000000001');
      expect(song.name, '晴天');
      expect(song.artist, '周杰伦 / 测试合唱');
      expect(song.album, '叶惠美');
      expect(song.duration, const Duration(seconds: 269));
      expect(song.coverUrl, 'https://d.musicapp.migu.cn/data/pic/cover.jpg');
      expect(song.lyricUrl, 'https://d.musicapp.migu.cn/lyric.lrc');
      expect(song.hasLyric, isTrue);
      expect(song.isVipOnly, isFalse);
      expect(song.playbackResourceType, 2);
    });

    test('将 http 封面与歌词地址升级为 https', () {
      final song = Song.fromJson({
        'contentId': '4',
        'songName': 'HTTPS',
        'img1': 'http://d.musicapp.migu.cn/data/pic/old.jpg',
        'lrcUrl': 'http://d.musicapp.migu.cn/data/lyric/old.lrc',
      });

      expect(song.coverUrl, 'https://d.musicapp.migu.cn/data/pic/old.jpg');
      expect(song.lyricUrl, 'https://d.musicapp.migu.cn/data/lyric/old.lrc');
      expect(song.hasLyric, isTrue);
    });

    test('封面同时保留最小档与最大档', () {
      final song = Song.fromJson({
        'contentId': '5',
        'songName': '三档封面',
        'img1': '/data/pic/cover_200.jpg',
        'img2': '/data/pic/cover_400.jpg',
        'img3': '/data/pic/cover_800.jpg',
      });

      // 列表缩略图继续用最小档省流量，整屏播放页用最大档才不糊。
      expect(song.coverUrl, 'https://d.musicapp.migu.cn/data/pic/cover_200.jpg');
      expect(song.coverUrlLarge, 'https://d.musicapp.migu.cn/data/pic/cover_800.jpg');
    });

    test('只给一档时大图地址退回同一张', () {
      final song = Song.fromJson({
        'contentId': '6',
        'songName': '单档封面',
        'img1': '/data/pic/only_200.jpg',
      });

      expect(song.coverUrlLarge, song.coverUrl);
    });

    test('restrictType 为 1 时标记 VIP', () {
      final song = Song.fromJson({
        'contentId': '1',
        'songName': '受限歌曲',
        'restrictType': 1,
      });

      expect(song.isVipOnly, isTrue);
      expect(song.artist, '未知歌手');
      expect(song.album, '未知专辑');
    });

    test('音质标签含 vip / tl-vip 时标记 VIP', () {
      final vip = Song.fromJson({
        'contentId': '2',
        'songName': 'VIP 歌曲',
        'audioFormats': [
          {
            'formatType': 'PQ',
            'showTagsNew': ['vip'],
          },
        ],
      });
      final trialVip = Song.fromJson({
        'contentId': '3',
        'songName': '试用 VIP',
        'audioFormats': [
          {
            'formatType': 'PQ',
            'showTags': ['TL-VIP'],
          },
        ],
      });

      expect(vip.isVipOnly, isTrue);
      expect(trialVip.isVipOnly, isTrue);
    });
  });

  group('PlaylistSummary', () {
    test('解析歌单详情结构与标签', () {
      final playlist = PlaylistSummary.fromInfoJson({
        'musicListId': '123456789',
        'title': '华语流行',
        'imgItem': {'img': '/data/pic/list.jpg'},
        'summary': '歌单简介',
        'ownerName': '测试用户',
        'musicNum': 42,
        'opNumItem': {'playNumDesc': '12.5万'},
        'tags': [
          {'tagName': '流行'},
          {'tagName': '华语'},
        ],
      });

      expect(playlist.id, '123456789');
      expect(playlist.name, '华语流行');
      expect(playlist.coverUrl, 'https://d.musicapp.migu.cn/data/pic/list.jpg');
      expect(playlist.ownerName, '测试用户');
      expect(playlist.songCount, 42);
      expect(playlist.playCountLabel, '12.5万');
      expect(playlist.tags, ['流行', '华语']);
    });

    test('搜索结果字段兜底', () {
      final playlist = PlaylistSummary.fromSearchJson({
        'id': '987654321',
        'name': '夜间歌单',
        'musicNum': 8,
        'playNumDesc': '1000',
      });

      expect(playlist.name, '夜间歌单');
      expect(playlist.songCount, 8);
      expect(playlist.playCountLabel, '1000');
    });
  });
}
