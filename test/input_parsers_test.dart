import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/input_parsers.dart';

void main() {
  group('parsePlaylistId', () {
    test('纯数字歌单 ID', () {
      expect(parsePlaylistId('123456789'), '123456789');
      expect(parsePlaylistId('  123456  '), '123456');
    });

    test('从分享路径中提取', () {
      expect(
        parsePlaylistId('https://music.migu.cn/v3/music/playlist/987654321'),
        '987654321',
      );
      expect(
        parsePlaylistId('https://music.migu.cn/playlist?playlistId=12345678'),
        '12345678',
      );
    });

    test('从查询参数中提取', () {
      expect(
        parsePlaylistId('https://music.migu.cn/share?id=1234567&from=app'),
        '1234567',
      );
    });

    test('ID 长度不合适时使用数字兜底', () {
      expect(parsePlaylistId('歌单 987654321 分享'), '987654321');
    });

    test('无效输入返回 null', () {
      expect(parsePlaylistId(''), isNull);
      expect(parsePlaylistId('   '), isNull);
      expect(parsePlaylistId('没有数字'), isNull);
      expect(parsePlaylistId('1234'), isNull);
    });
  });
}
