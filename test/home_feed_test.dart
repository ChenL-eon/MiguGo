import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/home_feed.dart';

void main() {
  group('首页每日推荐', () {
    test('解析歌曲、去重并补全封面地址', () {
      final payload = {
        'code': '000000',
        'data': {
          'recommendData': {
            'time': '2026-10-21',
            'data': [
              {
                'contentId': 'content_1',
                'copyrightId': 'copyright_1',
                'songName': '晴天',
                'singerList': [
                  {'name': '周杰伦'},
                ],
                'album': '叶惠美',
                'duration': 269,
                'img1': '/covers/1.jpg',
                'restrictType': 0,
              },
              {'contentId': 'content_1', 'songName': '晴天（重复）'},
              {'contentId': '', 'songName': '没有内容 ID'},
              {
                'contentId': 'content_2',
                'songName': '稻香',
                'singerList': [
                  {'name': '周杰伦'},
                ],
                'album': '魔杰座',
                'duration': 223,
              },
            ],
          },
        },
      };

      final songs = HomeFeed.songsFromDailyPayload(payload);
      expect(songs, hasLength(2));
      expect(songs[0].contentId, 'content_1');
      expect(songs[0].name, '晴天');
      expect(songs[0].artist, '周杰伦');
      expect(songs[0].coverUrl, 'https://d.musicapp.migu.cn/covers/1.jpg');
      expect(songs[1].contentId, 'content_2');
      expect(HomeFeed.dateFromDailyPayload(payload), DateTime(2026, 10, 21));
    });

    test('缺少推荐结构时返回空列表', () {
      expect(HomeFeed.songsFromDailyPayload({'code': '000000'}), isEmpty);
      expect(HomeFeed.dateFromDailyPayload({'code': '000000'}), isNull);
    });
  });

  group('首页推荐歌单', () {
    test('只取滚动歌单栏目并去重', () {
      final payload = {
        'data': {
          'contents': [
            {
              'view': 'ZJ-Banner',
              'contents': [
                {'resId': 'banner', 'txt': '顶部广告'},
              ],
            },
            {
              'view': 'ZJ-SongList-Scroll',
              'contents': [
                {
                  'resId': 'playlist_1',
                  'txt': '华语流行',
                  'img': 'https://d.musicapp.migu.cn/cover_1.jpg',
                },
                {'resId': 'playlist_1', 'txt': '重复歌单', 'img': ''},
                {'resId': 'playlist_2', 'txt': '经典老歌', 'img': '/cover_2.jpg'},
              ],
            },
          ],
        },
      };

      final playlists = HomeFeed.playlistsFromIndexPayload(payload);
      expect(playlists, hasLength(2));
      expect(playlists[0].id, 'playlist_1');
      expect(playlists[0].name, '华语流行');
      expect(playlists[0].coverUrl, 'https://d.musicapp.migu.cn/cover_1.jpg');
      expect(playlists[1].id, 'playlist_2');
      expect(playlists[1].coverUrl, 'https://d.musicapp.migu.cn/cover_2.jpg');
    });

    test('没有滚动歌单栏目时返回空列表', () {
      expect(
        HomeFeed.playlistsFromIndexPayload({
          'data': {
            'contents': [
              {'view': 'ZJ-Banner'},
            ],
          },
        }),
        isEmpty,
      );
    });
  });
}
