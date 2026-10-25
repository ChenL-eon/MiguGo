import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/services/web/migu_web_player_url.dart';

Song _song(String name) => Song(
  contentId: '600919000005413980',
  copyrightId: '6005663SX43',
  name: name,
  artistNames: const ['陈奕迅'],
  album: '孤勇者',
  duration: Duration.zero,
  isVipOnly: true,
);

void main() {
  group('内嵌官方网页播放器地址', () {
    test('v5 没有歌曲详情页，只能用搜索结果页直达', () {
      expect(
        MiguWebPlayerUrl.forSong(_song('孤勇者')),
        'https://music.migu.cn/v5/#/playlist?search=%E5%AD%A4%E5%8B%87%E8%80%85'
        '&playlistType=ordinary',
      );
    });

    test('接口歌名带括注，去掉后才能搜到', () {
      expect(MiguWebPlayerUrl.searchTextFor(_song('孤勇者(《英雄联盟：双城之战》主题曲)')), '孤勇者');
      expect(MiguWebPlayerUrl.searchTextFor(_song('回到你身边（让你知道）')), '回到你身边');
    });

    test('整串书名号歌名不会被截空', () {
      expect(MiguWebPlayerUrl.searchTextFor(_song('《拜青山》')), '《拜青山》');
    });

    test('歌名缺失时回落到站点首页', () {
      expect(MiguWebPlayerUrl.forSong(_song('  ')), MiguWebPlayerUrl.site);
    });
  });
}
