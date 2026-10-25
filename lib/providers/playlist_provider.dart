import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_music_api.dart';

/// 歌单详情状态：先加载首屏，再按需分页，避免一次性抓取整个歌单。
class PlaylistProvider extends ChangeNotifier {
  PlaylistProvider(this._api);

  final MiguMusicApi _api;

  PlaylistSummary? _playlist;
  List<Song> _songs = const [];
  String _playlistId = '';
  String? _error;
  String? _loadMoreError;
  bool _loading = false;
  bool _loadingMore = false;
  int _pageNo = 0;
  int _totalCount = 0;
  bool _hasMore = false;
  int _token = 0;

  PlaylistSummary? get playlist => _playlist;
  List<Song> get songs => _songs;
  String get playlistId => _playlistId;
  String? get error => _error;
  String? get loadMoreError => _loadMoreError;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  int get totalCount => _totalCount;
  bool get hasMore => _hasMore;

  Future<void> load(String id, {bool force = false}) async {
    if (id.isEmpty) {
      _error = '歌单 ID 无效。';
      _playlist = null;
      _songs = const [];
      notifyListeners();
      return;
    }
    if (!force && _playlistId == id && (_loading || _playlist != null)) {
      return;
    }

    final token = ++_token;
    _playlistId = id;
    _loading = true;
    _loadingMore = false;
    _error = null;
    _loadMoreError = null;
    _playlist = null;
    _songs = const [];
    _pageNo = 0;
    _totalCount = 0;
    _hasMore = false;
    notifyListeners();

    try {
      final results = await Future.wait<Object>([
        _api.fetchPlaylistInfo(id),
        _api.fetchPlaylistSongs(id, pageNo: 1),
      ]);
      if (token != _token) return;

      final playlist = results[0] as PlaylistSummary;
      final firstPage = results[1] as PlaylistSongsPage;
      _playlist = playlist;
      _songs = List<Song>.unmodifiable(firstPage.songs);
      _pageNo = firstPage.pageNo;
      _totalCount = firstPage.totalCount;
      _hasMore = firstPage.hasMore;
    } catch (error) {
      if (token != _token) return;
      _error = error is MiguApiException ? error.message : '歌单加载失败，请稍后重试。';
    } finally {
      if (token == _token) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _playlist == null) return;
    final token = _token;
    _loadingMore = true;
    _loadMoreError = null;
    notifyListeners();

    try {
      final page = await _api.fetchPlaylistSongs(_playlistId, pageNo: _pageNo + 1);
      if (token != _token) return;

      final known = _songs.map((song) => song.contentId).toSet();
      final appended = page.songs.where((song) => known.add(song.contentId)).toList();
      _songs = List<Song>.unmodifiable([..._songs, ...appended]);
      _pageNo = page.pageNo;
      _totalCount = page.totalCount;
      _hasMore = page.hasMore && appended.isNotEmpty;
    } catch (error) {
      if (token != _token) return;
      _loadMoreError = error is MiguApiException ? error.message : '加载更多失败，请重试。';
    } finally {
      if (token == _token) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() async {
    if (_playlistId.isEmpty) return;
    await load(_playlistId, force: true);
  }
}
