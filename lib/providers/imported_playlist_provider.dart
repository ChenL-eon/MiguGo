import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/external_playlist_urls.dart';
import '../models/imported_playlist.dart';
import '../models/song.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_music_api.dart';
import '../services/external/external_playlist_service.dart';
import '../services/external/external_track_matcher.dart';

enum ImportStage { idle, fetching, matching }

/// 外部歌单导入状态：读取公开曲目，逐首匹配咪咕曲库并保存结果。
class ImportedPlaylistProvider extends ChangeNotifier {
  /// [backoffWait] 与 [persistor] 是给测试留的接缝：退避不该真的等满几十秒，
  /// 保存失败也要能被演练出来，而不是只在日志里响一声。
  ImportedPlaylistProvider(
    this._external,
    this._api, {
    Future<void> Function(Duration delay)? backoffWait,
    Future<bool> Function(String payload)? persistor,
  }) : _backoffWait = backoffWait ?? _delayed,
       // 形参名要保持公开可读（persistor:），字段是私有的，不能用 this._persistor。
       // ignore: prefer_initializing_formals
       _persistor = persistor;

  static const int maxScanTracks = 500;
  static const int maxSavedPlaylists = 20;
  static const int _concurrency = 4;
  static const String _storageKey = 'imported_playlists_v1';

  /// 撞上限流后同一首最多再试的次数。
  static const int _maxRateLimitRetries = 2;

  /// 限流退避的基础时长，按尝试次数线性放大。
  static const Duration _backoffStep = Duration(seconds: 15);

  final ExternalPlaylistService _external;
  final MiguMusicApi _api;
  final Future<void> Function(Duration delay) _backoffWait;
  final Future<bool> Function(String payload)? _persistor;

  static Future<void> _delayed(Duration delay) => Future<void>.delayed(delay);

  SharedPreferences? _preferences;
  List<ImportedPlaylist> _playlists = const [];
  ImportedPlaylist? _lastImport;
  String? _error;
  bool _importing = false;
  bool _loaded = false;
  ImportStage _stage = ImportStage.idle;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String _progressLabel = '';
  int _token = 0;

  List<ImportedPlaylist> get playlists => _playlists;
  ImportedPlaylist? get lastImport => _lastImport;
  String? get error => _error;
  bool get importing => _importing;
  bool get loaded => _loaded;
  ImportStage get stage => _stage;
  int get progressCurrent => _progressCurrent;
  int get progressTotal => _progressTotal;
  String get progressLabel => _progressLabel;

  ImportedPlaylist? findById(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _preferences = await SharedPreferences.getInstance();
    final raw = _preferences?.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          final items = <ImportedPlaylist>[];
          for (final item in data) {
            final playlist = ImportedPlaylist.tryParse(item);
            if (playlist != null) items.add(playlist);
          }
          _playlists = List.unmodifiable(items.take(maxSavedPlaylists));
        }
      } catch (error) {
        debugPrint('读取已导入歌单失败：$error');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> importFromLink(String rawLink) async {
    if (_importing) {
      _error = '正在导入上一个歌单，请等它完成。';
      notifyListeners();
      return false;
    }

    final link = parseExternalPlaylistLink(rawLink);
    if (link == null) {
      _error = '无法识别这个链接。请粘贴网易云、QQ音乐或酷狗歌单的分享链接。';
      notifyListeners();
      return false;
    }

    final token = ++_token;
    _importing = true;
    _error = null;
    _lastImport = null;
    _stage = ImportStage.fetching;
    _progressCurrent = 0;
    _progressTotal = 0;
    _progressLabel = '正在读取${link.platform.label}歌单…';
    notifyListeners();

    try {
      final external = await _external.fetchPlaylist(link, maxTracks: maxScanTracks);
      if (token != _token) return false;

      final tracks = external.tracks.take(maxScanTracks).toList();
      if (tracks.isEmpty) {
        throw const ExternalPlaylistException('这个歌单没有可导入的曲目。');
      }

      _stage = ImportStage.matching;
      _progressLabel = '正在逐首匹配咪咕曲库…';
      _progressTotal = tracks.length;
      _progressCurrent = 0;
      notifyListeners();

      final matches = List<Song?>.filled(tracks.length, null);
      final unmatched = List<String?>.filled(tracks.length, null);
      final queryFailed = <int>{};
      String? searchError;
      var rateLimited = false;
      var cursor = 0;
      var completed = 0;

      Future<void> worker() async {
        while (true) {
          // 取消或被新一轮导入顶替后不再取新曲目；限流则整批停手，
          // 继续往下试只会把 429 撞得更久。
          if (rateLimited || token != _token) return;
          final index = cursor++;
          if (index >= tracks.length) return;
          final track = tracks[index];
          final query = ExternalTrackMatcher.buildSearchQuery(track);
          Object? requestError;
          for (var attempt = 0; ; attempt++) {
            try {
              final candidates = await _api.searchSongs(query, pageSize: 8);
              final match = ExternalTrackMatcher.pickBest(track, candidates);
              if (match == null) {
                unmatched[index] = track.title;
              } else {
                matches[index] = match;
              }
              break;
            } on MiguApiException catch (error) {
              requestError = error;
              final limited = error.kind == MiguErrorKind.rateLimited;
              if (limited && attempt < _maxRateLimitRetries) {
                await _backoffWait(_backoffStep * (attempt + 1));
                continue;
              }
              // 一首被限流，多半是这一批整体撞墙，不再往下试。
              rateLimited = limited;
              searchError ??= error.message;
              break;
            } catch (error) {
              debugPrint('匹配外部曲目失败：$error');
              requestError = error;
              searchError ??= '匹配咪咕曲库时返回了无法识别的数据。';
              break;
            }
          }
          // 请求本身失败 ≠ 咪咕曲库里没有这首歌，不能记成「未匹配」。
          if (requestError != null) queryFailed.add(index);
          completed++;
          if (token == _token) {
            _progressCurrent = completed;
            notifyListeners();
          }
        }
      }

      final workerCount = tracks.length < _concurrency ? tracks.length : _concurrency;
      await Future.wait(List.generate(workerCount, (_) => worker()));
      if (token != _token) return false;

      if (rateLimited) {
        throw const ExternalPlaylistException(
          '咪咕搜索接口访问过于频繁，本次导入已停止，请稍后再试。'
          '曲目越多越容易被限流，可以先导个小一点的歌单。',
        );
      }

      final songs = <Song>[];
      final seenContentIds = <String>{};
      for (final song in matches) {
        if (song == null) continue;
        if (seenContentIds.add(song.contentId)) songs.add(song);
      }

      if (songs.isEmpty) {
        if (searchError != null) {
          throw ExternalPlaylistException('匹配咪咕曲库失败：$searchError');
        }
        throw const ExternalPlaylistException(
          '没有在咪咕曲库匹配到这首歌单的歌曲。可以换一个歌单，'
          '或先在搜索页确认咪咕是否收录这些曲目。',
        );
      }

      final totalTracks = external.totalCount < external.tracks.length
          ? external.tracks.length
          : external.totalCount;
      final partial = external.isPartial || totalTracks > tracks.length;
      var limitNote = external.limitNote;
      if (limitNote.isEmpty && partial) {
        limitNote = '原歌单共 $totalTracks 首，本次匹配了前 ${tracks.length} 首。';
      }
      if (queryFailed.isNotEmpty) {
        final note =
            '另有 ${queryFailed.length} 首查询失败'
            '（咪咕接口没有答复，不代表曲库里没有），可以稍后重新导入。';
        limitNote = limitNote.isEmpty ? note : '$limitNote $note';
      }

      final imported = ImportedPlaylist(
        id:
            '${external.platform.name}_'
            '${DateTime.now().millisecondsSinceEpoch}',
        name: external.name,
        sourceUrl: external.sourceUrl.isEmpty
            ? link.url.toString()
            : external.sourceUrl,
        platform: external.platform,
        coverUrl: external.coverUrl,
        importedAt: DateTime.now(),
        totalTracks: totalTracks,
        scannedTracks: tracks.length,
        partial: partial,
        limitNote: limitNote,
        songs: List.unmodifiable(songs),
        unmatchedTitles: List.unmodifiable(unmatched.whereType<String>()),
      );

      _playlists = List.unmodifiable(
        <ImportedPlaylist>[
          imported,
          ..._playlists.where((item) => item.sourceUrl != imported.sourceUrl),
        ].take(maxSavedPlaylists),
      );
      final saved = await _persist();
      _lastImport = imported;
      if (token == _token && !saved) {
        // 内存里有歌单、重启就没有了：这必须说给用户听，不能只写日志。
        _error = '《${imported.name}》这次能用，但没能保存到本机，重启后会丢失。';
      }
      return true;
    } on ExternalPlaylistException catch (error) {
      if (token == _token) _error = error.message;
      return false;
    } catch (error) {
      debugPrint('导入外部歌单失败：$error');
      if (token == _token) _error = '导入歌单失败，请稍后重试。';
      return false;
    } finally {
      if (token == _token) {
        _importing = false;
        _stage = ImportStage.idle;
        _progressCurrent = 0;
        _progressTotal = 0;
        _progressLabel = '';
        notifyListeners();
      }
    }
  }

  /// 用户主动中止本次导入：进度与结果一起作废。
  ///
  /// 只做代际递增，不强杀已经在途的请求——在途回调回来时发现代际不匹配就不会
  /// 再写状态，因此取消后不会冒出一个「导入完成」，也不会留下半份歌单。
  void cancel() {
    if (!_importing) return;
    _token++;
    _importing = false;
    _error = null;
    _stage = ImportStage.idle;
    _progressCurrent = 0;
    _progressTotal = 0;
    _progressLabel = '';
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final next = _playlists.where((item) => item.id != id).toList();
    if (next.length == _playlists.length) return;
    _playlists = List.unmodifiable(next);
    if (_lastImport?.id == id) _lastImport = null;
    if (!await _persist()) {
      _error = '移除没能保存到本机，重启后这个歌单还会回来。';
    }
    notifyListeners();
  }

  /// 把当前歌单写进本机存储，返回是否真的落盘。
  Future<bool> _persist() async {
    try {
      final payload = jsonEncode(_playlists.map((item) => item.toJson()).toList());
      return await (_persistor ?? _writeToStorage)(payload);
    } catch (error) {
      debugPrint('保存已导入歌单失败：$error');
      return false;
    }
  }

  Future<bool> _writeToStorage(String payload) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    return preferences.setString(_storageKey, payload);
  }
}
