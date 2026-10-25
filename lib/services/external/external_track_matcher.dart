import '../../models/imported_playlist.dart';
import '../../models/song.dart';

/// 外部曲目与咪咕搜索结果的宽松匹配。
///
/// 歌名完全一致时优先；歌名只是包含关系时，必须同时有歌手重合，
/// 以免把同名的翻唱或伴奏误配成原曲。
class ExternalTrackMatcher {
  const ExternalTrackMatcher._();

  static Song? pickBest(ExternalTrack track, List<Song> candidates) {
    final targetTitle = normalizeTitle(track.title);
    if (targetTitle.isEmpty) return null;

    Song? best;
    var bestScore = 0;
    for (final song in candidates) {
      final candidateTitle = normalizeTitle(song.name);
      if (candidateTitle.isEmpty) continue;

      final exact = candidateTitle == targetTitle;
      final contains =
          !exact &&
          (candidateTitle.contains(targetTitle) ||
              targetTitle.contains(candidateTitle));
      if (!exact && !contains) continue;

      final artistMatch = artistsOverlap(track.artist, song.artistNames);
      if (!exact && !artistMatch) continue;

      var score = 0;
      if (exact) score += 4;
      if (contains) score += 1;
      if (artistMatch) score += 3;
      if (normalizeTitle(song.artist) == normalizeTitle(track.artist)) {
        score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = song;
      }
    }
    return best;
  }

  static String buildSearchQuery(ExternalTrack track) {
    final title = track.title
        .replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final artists = splitArtists(track.artist);
    final artist = artists.isEmpty ? '' : artists.first;
    final query = '$title $artist'.trim();
    return query.isEmpty ? track.title.trim() : query;
  }

  /// 去掉括号补充说明、说唱标记、标点与空白，只保留可比较的主体。
  static String normalizeTitle(String raw) {
    var text = _toHalfWidth(raw).toLowerCase();
    text = text.replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), ' ');
    text = text.replaceAll(RegExp(r'\s*(feat\.?|ft\.?|featuring)\s.*$'), ' ');
    text = text.replaceAll(
      RegExp(r'''[\s\-_.,，。、·!！?？"'“”‘’()（）\[\]【】《》<>/\\|:：;；+&~]+'''),
      '',
    );
    return text;
  }

  static bool artistsOverlap(String externalArtist, List<String> miguArtists) {
    final externalParts = splitArtists(externalArtist)
        .map(normalizeTitle)
        .where((part) => part.isNotEmpty);
    for (final miguArtist in miguArtists) {
      final candidate = normalizeTitle(miguArtist);
      if (candidate.isEmpty) continue;
      for (final part in externalParts) {
        if (part == candidate) return true;
        if (part.length >= 2 &&
            candidate.length >= 2 &&
            (part.contains(candidate) || candidate.contains(part))) {
          return true;
        }
      }
    }
    return false;
  }

  static List<String> splitArtists(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+feat\.?\s+', caseSensitive: false), ' / ')
        .split(RegExp(r'\s*(?:/|、|,|，|&|;|；|·)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static String _toHalfWidth(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
