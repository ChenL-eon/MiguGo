import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_music_api.dart';
import 'settings_provider.dart';

enum SearchTab { songs, playlists }

/// 搜索页状态：单曲与歌单按需加载并缓存当前关键词的结果。
class SearchProvider extends ChangeNotifier {
  SearchProvider(this._api, this._settings);

  final MiguMusicApi _api;
  final SettingsProvider _settings;

  SearchTab _activeTab = SearchTab.songs;
  String _query = '';
  String _songsQuery = '';
  String _playlistsQuery = '';

  /// 咪咕搜索接口即使请求更大的 pageSize 也只返回 20 条，分页依赖 pageNo。
  static const int searchPageSize = 20;

  List<Song> _songs = const [];
  List<PlaylistSummary> _playlists = const [];
  bool _songsLoading = false;
  bool _playlistsLoading = false;
  bool _songsLoadingMore = false;
  bool _songsHasMore = false;
  int _songsPage = 0;
  String? _songsError;
  String? _songsLoadMoreError;
  String? _playlistsError;
  int _songsToken = 0;
  int _playlistsToken = 0;

  SearchTab get activeTab => _activeTab;
  String get query => _query;
  List<Song> get songs => _songs;
  List<PlaylistSummary> get playlists => _playlists;
  bool get songsLoading => _songsLoading;
  bool get playlistsLoading => _playlistsLoading;
  bool get songsLoadingMore => _songsLoadingMore;
  bool get songsHasMore => _songsHasMore;
  int get songsPage => _songsPage;
  String? get songsError => _songsError;
  String? get songsLoadMoreError => _songsLoadMoreError;
  String? get playlistsError => _playlistsError;
  bool get hasSearched => _songsQuery.isNotEmpty || _playlistsQuery.isNotEmpty;

  Future<void> submit(String text, {SearchTab? tab}) async {
    final nextQuery = text.trim();
    if (tab != null) _activeTab = tab;
    if (nextQuery.isEmpty) {
      clear();
      return;
    }
    _query = nextQuery;
    notifyListeners();
    unawaited(_settings.addSearchHistory(nextQuery));
    await _loadActiveTab(force: true);
  }

  Future<void> setTab(SearchTab tab) async {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
    if (_query.isNotEmpty) {
      await _loadActiveTab();
    }
  }

  Future<void> retry() async {
    if (_query.isEmpty) return;
    await _loadActiveTab(force: true);
  }

  void clear() {
    _songsToken++;
    _playlistsToken++;
    _query = '';
    _songsQuery = '';
    _playlistsQuery = '';
    _songs = const [];
    _playlists = const [];
    _songsLoading = false;
    _playlistsLoading = false;
    _songsLoadingMore = false;
    _songsHasMore = false;
    _songsPage = 0;
    _songsError = null;
    _songsLoadMoreError = null;
    _playlistsError = null;
    notifyListeners();
  }

  Future<void> _loadActiveTab({bool force = false}) async {
    if (_activeTab == SearchTab.songs) {
      if (!force && (_songsQuery == _query || _songsLoading)) {
        return;
      }
      await _searchSongs(_query);
    } else {
      if (!force && (_playlistsQuery == _query || _playlistsLoading)) {
        return;
      }
      await _searchPlaylists(_query);
    }
  }

  Future<void> _searchSongs(String text) async {
    final token = ++_songsToken;
    _songsLoading = true;
    _songsLoadingMore = false;
    _songsHasMore = false;
    _songsPage = 0;
    _songsError = null;
    _songsLoadMoreError = null;
    notifyListeners();
    try {
      final result = await _api.searchSongs(text, pageNo: 1, pageSize: searchPageSize);
      if (token != _songsToken) return;
      _songs = result;
      _songsQuery = text;
      _songsPage = 1;
      _songsHasMore = result.length >= searchPageSize;
    } catch (error) {
      if (token != _songsToken) return;
      _songsError = _messageFor(error);
    } finally {
      if (token == _songsToken) {
        _songsLoading = false;
        notifyListeners();
      }
    }
  }

  /// 追加下一页单曲；失败只影响“加载更多”，不会清空已有结果。
  Future<void> loadMoreSongs() async {
    if (_songsLoading || _songsLoadingMore || !_songsHasMore || _songsQuery.isEmpty) {
      return;
    }
    final token = _songsToken;
    final text = _songsQuery;
    final nextPage = _songsPage + 1;
    _songsLoadingMore = true;
    _songsLoadMoreError = null;
    notifyListeners();
    try {
      final result = await _api.searchSongs(
        text,
        pageNo: nextPage,
        pageSize: searchPageSize,
      );
      if (token != _songsToken) return;
      final seen = _songs.map((song) => song.contentId).toSet();
      final fresh = result.where((song) => seen.add(song.contentId)).toList();
      _songs = [..._songs, ...fresh];
      _songsPage = nextPage;
      _songsHasMore = result.length >= searchPageSize && fresh.isNotEmpty;
    } catch (error) {
      if (token != _songsToken) return;
      _songsLoadMoreError = _messageFor(error);
    } finally {
      if (token == _songsToken) {
        _songsLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// 桌面端页码翻页：用目标页结果替换当前列表。
  Future<void> goToSongsPage(int pageNo) async {
    if (pageNo < 1 ||
        _songsQuery.isEmpty ||
        _songsLoading ||
        _songsLoadingMore ||
        pageNo == _songsPage) {
      return;
    }
    final token = ++_songsToken;
    _songsLoading = true;
    _songsError = null;
    _songsLoadMoreError = null;
    notifyListeners();
    try {
      final result = await _api.searchSongs(
        _songsQuery,
        pageNo: pageNo,
        pageSize: searchPageSize,
      );
      if (token != _songsToken) return;
      _songs = result;
      _songsPage = pageNo;
      _songsHasMore = result.length >= searchPageSize;
    } catch (error) {
      if (token != _songsToken) return;
      _songsError = _messageFor(error);
    } finally {
      if (token == _songsToken) {
        _songsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _searchPlaylists(String text) async {
    final token = ++_playlistsToken;
    _playlistsLoading = true;
    _playlistsError = null;
    notifyListeners();
    try {
      final result = await _api.searchPlaylists(text, pageSize: 20);
      if (token != _playlistsToken) return;
      _playlists = result;
      _playlistsQuery = text;
    } catch (error) {
      if (token != _playlistsToken) return;
      _playlistsError = _messageFor(error);
    } finally {
      if (token == _playlistsToken) {
        _playlistsLoading = false;
        notifyListeners();
      }
    }
  }

  String _messageFor(Object error) {
    if (error is MiguApiException) return error.message;
    return '搜索失败，请稍后重试。';
  }
}
