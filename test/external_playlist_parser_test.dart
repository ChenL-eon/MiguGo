import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/external_playlist_urls.dart';
import 'package:migu_lele/models/imported_playlist.dart';

void main() {
  group('网易云歌单解析', () {
    test('读取歌名、歌手与封面', () {
      final playlist = ExternalPlaylist.fromNeteasePayload({
        'code': 200,
        'playlist': {
          'name': '华语流行',
          'trackCount': 3,
          'coverImgUrl': 'https://p1.music.126.net/cover.jpg',
          'tracks': [
            {
              'name': '晴天',
              'ar': [
                {'name': '周杰伦'},
              ],
            },
            {
              'name': '演员',
              'ar': [
                {'name': '薛之谦'},
              ],
            },
            {
              'name': '起风了',
              'ar': [
                {'name': '买辣椒也用券'},
              ],
            },
          ],
        },
      }, sourceUrl: 'https://music.163.com/playlist?id=1');

      expect(playlist.platform, ExternalPlatform.netease);
      expect(playlist.name, '华语流行');
      expect(playlist.tracks, hasLength(3));
      expect(playlist.tracks[0].title, '晴天');
      expect(playlist.tracks[0].artist, '周杰伦');
      expect(playlist.totalCount, 3);
      expect(playlist.coverUrl, 'https://p1.music.126.net/cover.jpg');
      expect(playlist.isPartial, isFalse);
    });

    test('没有曲目时给出可读错误', () {
      expect(
        () => ExternalPlaylist.fromNeteasePayload({
          'code': 200,
          'playlist': {'name': '空歌单', 'tracks': <dynamic>[]},
        }, sourceUrl: 'https://music.163.com/playlist?id=1'),
        throwsA(
          isA<ExternalPlaylistException>().having(
            (error) => error.message,
            'message',
            contains('没有可读取的公开曲目'),
          ),
        ),
      );
    });

    test('没有歌单结构时提示确认公开状态', () {
      expect(
        () => ExternalPlaylist.fromNeteasePayload({
          'code': 404,
        }, sourceUrl: 'https://music.163.com/playlist?id=1'),
        throwsA(
          isA<ExternalPlaylistException>().having(
            (error) => error.message,
            'message',
            contains('公开歌单'),
          ),
        ),
      );
    });

    test('tracks 被截断时按 trackIds 顺序合并补拉曲目', () {
      final payload = {
        'code': 200,
        'playlist': {
          'name': '长歌单',
          'trackCount': 3,
          'trackIds': [
            {'id': 11},
            {'id': 12},
            {'id': 13},
          ],
          'tracks': [
            {
              'id': 12,
              'name': '第二首',
              'ar': [
                {'name': '歌手乙'},
              ],
            },
          ],
        },
      };

      expect(ExternalPlaylist.neteaseMissingTrackIds(payload), ['11', '13']);

      final playlist = ExternalPlaylist.fromNeteasePayload(
        payload,
        sourceUrl: 'https://music.163.com/playlist?id=3',
        extraSongs: [
          {
            'id': 11,
            'name': '第一首',
            'ar': [
              {'name': '歌手甲'},
            ],
          },
          {
            'id': 13,
            'name': '第三首',
            'ar': [
              {'name': '歌手丙'},
            ],
          },
        ],
      );

      expect(playlist.tracks.map((track) => track.title), ['第一首', '第二首', '第三首']);
      expect(playlist.tracks[0].artist, '歌手甲');
      expect(playlist.totalCount, 3);
      expect(playlist.isPartial, isFalse);
    });

    test('补拉仍缺曲目时标记为部分导入', () {
      final playlist = ExternalPlaylist.fromNeteasePayload({
        'playlist': {
          'name': '缺歌歌单',
          'trackCount': 10,
          'trackIds': [
            {'id': 1},
            {'id': 2},
          ],
          'tracks': [
            {'id': 1, 'name': '只有一首', 'ar': <dynamic>[]},
          ],
        },
      }, sourceUrl: 'https://music.163.com/playlist?id=4');

      expect(playlist.totalCount, 10);
      expect(playlist.tracks, hasLength(1));
      expect(playlist.isPartial, isTrue);
    });
  });

  group('QQ音乐歌单解析', () {
    test('读取 songname 与 singer 字段', () {
      final playlist = ExternalPlaylist.fromQqPayload({
        'code': 0,
        'cdlist': [
          {
            'dissname': '我的收藏',
            'songnum': 2,
            'logo': 'https://y.gtimg.cn/cover.jpg',
            'songlist': [
              {
                'songname': '七里香',
                'singer': [
                  {'name': '周杰伦'},
                ],
              },
              {
                'songname': '稻香',
                'singer': [
                  {'name': '周杰伦'},
                  {'name': '费玉清'},
                ],
              },
            ],
          },
        ],
      }, sourceUrl: 'https://y.qq.com/n/ryqq/playlist/2');

      expect(playlist.platform, ExternalPlatform.qqMusic);
      expect(playlist.name, '我的收藏');
      expect(playlist.tracks, hasLength(2));
      expect(playlist.tracks[1].title, '稻香');
      expect(playlist.tracks[1].artist, '周杰伦 / 费玉清');
      expect(playlist.totalCount, 2);
      expect(playlist.coverUrl, 'https://y.gtimg.cn/cover.jpg');
    });

    test('平台错误信息会原样展示', () {
      expect(
        () => ExternalPlaylist.fromQqPayload({
          'code': 0,
          'subcode': 1,
          'msg': 'invalid referer',
        }, sourceUrl: 'https://y.qq.com/n/ryqq/playlist/2'),
        throwsA(
          isA<ExternalPlaylistException>().having(
            (error) => error.message,
            'message',
            contains('invalid referer'),
          ),
        ),
      );
    });
  });

  group('酷狗歌单页解析', () {
    const html = '''
<html><head><title>歌单_精选集_乐库频道_酷狗网</title></head>
<body>
<script>
var specialInfo = {"id":0,"name":"\\u534e\\u8bed\\u7ecf\\u5178","class_name":"\\u6b4c\\u5355","image":"http:\\/\\/c1.kgimg.com\\/stdmusic\\/150\\/cover.jpg","nickname":"\\u80cc\\u5f71","percount":45};
var data=[{"songname":"\\u83ca\\u82b1\\u7206\\u6ee1\\u5c71","singername":"\\u9a6c\\u535a","authors":[{"author_name":"\\u9a6c\\u535a"}]},{"songname":"A]B [C","singername":"\\u6b4c\\u624b","authors":[]}];
</script>
<div>查看更多内容，请下载客户端</div>
</body></html>
''';

    test('从内联脚本提取曲目并标记公开限制', () {
      final playlist = ExternalPlaylist.fromKugouPage(
        html,
        sourceUrl: 'https://www.kugou.com/yy/special/single/x.html',
      );

      expect(playlist.platform, ExternalPlatform.kugou);
      expect(playlist.name, '华语经典');
      expect(playlist.tracks, hasLength(2));
      expect(playlist.tracks[0].title, '菊花爆满山');
      expect(playlist.tracks[0].artist, '马博');
      expect(playlist.tracks[1].title, 'A]B [C');
      expect(playlist.totalCount, 45);
      expect(playlist.coverUrl, startsWith('https://c1.kgimg.com/'));
      expect(playlist.isPartial, isTrue);
      expect(playlist.limitNote, contains('2 首'));
      expect(playlist.limitNote, contains('45'));
    });

    test('没有更多提示时不标记为部分导入', () {
      const page = '''
<script>
var specialInfo = {"name":"\\u6d4b\\u8bd5","image":"","percount":1};
var data=[{"songname":"\\u5c0f\\u661f\\u8fb0","singername":"\\u9648\\u6613\\u8baf"}];
</script>
''';
      final playlist = ExternalPlaylist.fromKugouPage(
        page,
        sourceUrl: 'https://www.kugou.com/yy/special/single/y.html',
      );
      expect(playlist.name, '测试');
      expect(playlist.isPartial, isFalse);
      expect(playlist.coverUrl, isNull);
      expect(playlist.tracks.single.title, '小星辰');
    });

    test('移动接口的 filename 优先于网页前 30 首', () {
      final playlist = ExternalPlaylist.fromKugouPage(
        '<script>var specialInfo = {"name":"完整歌单","percount":242};'
        'var data=[{"songname":"旧数据","singername":"旧歌手"}];</script>',
        sourceUrl: 'https://www.kugou.com/yy/special/single/9180602.html',
        apiTotal: 242,
        apiSongs: [
          {'filename': 'G.E.M.邓紫棋 - 唯一'},
          {'filename': '周杰伦 - 晴天'},
          for (var i = 0; i < 240; i++) {'filename': '歌手$i - 歌曲$i'},
        ],
      );

      expect(playlist.tracks, hasLength(242));
      expect(playlist.tracks.first.title, '唯一');
      expect(playlist.tracks.first.artist, 'G.E.M.邓紫棋');
      expect(playlist.tracks[1].title, '晴天');
      expect(playlist.tracks[1].artist, '周杰伦');
      expect(playlist.totalCount, 242);
      expect(playlist.isPartial, isFalse);
    });

    test('页面结构不匹配时报错', () {
      expect(
        () => ExternalPlaylist.fromKugouPage(
          '<html><body>没有脚本</body></html>',
          sourceUrl: 'https://www.kugou.com/yy/special/single/z.html',
        ),
        throwsA(isA<ExternalPlaylistException>()),
      );
    });
  });
}
