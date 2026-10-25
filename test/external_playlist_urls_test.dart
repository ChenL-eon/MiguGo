import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/external_playlist_urls.dart';

void main() {
  group('外部歌单链接解析', () {
    test('网易云完整歌单链接', () {
      final link = parseExternalPlaylistLink(
        'https://music.163.com/playlist?id=3778678&userid=1',
      );
      expect(link, isNotNull);
      expect(link!.platform, ExternalPlatform.netease);
      expect(link.id, '3778678');
      expect(link.needsResolution, isFalse);
      expect(link.platform.label, '网易云音乐');
    });

    test('网易云短链接需要先跟随跳转', () {
      final link = parseExternalPlaylistLink('https://163cn.tv/abcXYZ');
      expect(link, isNotNull);
      expect(link!.platform, ExternalPlatform.netease);
      expect(link.id, isNull);
      expect(link.needsResolution, isTrue);
    });

    test('分享文案里夹带链接也能识别', () {
      final link = parseExternalPlaylistLink(
        '分享歌单 https://music.163.com/#/playlist?id=24381616 来自网易云音乐',
      );
      expect(link, isNotNull);
      expect(link!.platform, ExternalPlatform.netease);
      expect(link.id, '24381616');
    });

    test('QQ音乐歌单页与分享链接', () {
      final full = parseExternalPlaylistLink(
        'https://y.qq.com/n/ryqq/playlist/7719884207',
      );
      expect(full, isNotNull);
      expect(full!.platform, ExternalPlatform.qqMusic);
      expect(full.id, '7719884207');

      final detail = parseExternalPlaylistLink(
        'https://i.y.qq.com/n2/m/share/details/taoge.html?id=7719884207',
      );
      expect(detail?.platform, ExternalPlatform.qqMusic);
      expect(detail?.id, '7719884207');

      final short = parseExternalPlaylistLink(
        'https://c6.y.qq.com/base/fcgi-bin/u?__=abc123',
      );
      expect(short?.platform, ExternalPlatform.qqMusic);
      expect(short?.needsResolution, isTrue);
    });

    test('酷狗分享页与集合 ID', () {
      final collection = parseExternalPlaylistLink(
        'https://www.kugou.com/yy/special/single/'
        'collection_3_372515335_27_0.html',
      );
      expect(collection, isNotNull);
      expect(collection!.platform, ExternalPlatform.kugou);
      expect(collection.id, 'collection_3_372515335_27_0');
      expect(collection.needsResolution, isFalse);

      final numeric = parseExternalPlaylistLink(
        'https://www.kugou.com/yy/special/single/1234567.html',
      );
      expect(numeric?.id, '1234567');

      final plist = parseExternalPlaylistLink(
        'https://m.kugou.com/plist/list/1234567?specialid=1234567',
      );
      expect(plist?.id, '1234567');
    });

    test('链接末尾的中文标点会被忽略', () {
      final link = parseExternalPlaylistLink(
        'https://music.163.com/playlist?id=3778678，',
      );
      expect(link?.id, '3778678');
    });

    test('不支持的平台与空文本返回空', () {
      expect(parseExternalPlaylistLink(''), isNull);
      expect(parseExternalPlaylistLink('没有链接'), isNull);
      expect(parseExternalPlaylistLink('https://example.com/playlist/123456'), isNull);
    });
  });
}
