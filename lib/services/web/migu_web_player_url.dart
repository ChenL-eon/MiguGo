import '../../models/song.dart';

/// 咪咕官方网页播放器（v5 站点）的内嵌地址。
class MiguWebPlayerUrl {
  const MiguWebPlayerUrl._();

  static const String site = 'https://music.migu.cn/v5/';

  /// 搜索结果页是唯一直达某一首歌的入口：v5 是 hash 路由的单页应用，
  /// 既没有歌曲详情页，也不接受自动播放参数，地址形如
  /// `#/playlist?search=歌名&playlistType=ordinary`。
  static String forSong(Song song) => forKeyword(searchTextFor(song));

  static String forKeyword(String keyword) {
    final text = keyword.trim();
    return text.isEmpty
        ? site
        : '$site#/playlist?search=${Uri.encodeComponent(text)}'
              '&playlistType=ordinary';
  }

  /// 接口返回的歌名常带括注（如“孤勇者(《…》动画主题曲)”），
  /// 整串丢进搜索框反而找不到，只取括号前的主标题。
  static String searchTextFor(Song song) {
    final name = song.name.trim();
    if (name.isEmpty) return '';
    var cut = name.length;
    for (final mark in const ['(', '（', '[', '【', '(', '［']) {
      final index = name.indexOf(mark);
      if (index > 0 && index < cut) cut = index;
    }
    final head = name.substring(0, cut).trim();
    return head.isEmpty ? name : head;
  }
}
