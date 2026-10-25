import 'package:flutter/foundation.dart';

import '../models/home_feed.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_music_api.dart';

/// 首页推送状态：保留上一次成功数据，刷新失败时不清空页面。
class HomeProvider extends ChangeNotifier {
  HomeProvider(this._api);

  final MiguMusicApi _api;

  HomeFeed? _feed;
  bool _loading = false;
  String? _error;
  int _token = 0;

  HomeFeed? get feed => _feed;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!force && _feed != null) return;

    final token = ++_token;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final feed = await _api.fetchHomeFeed();
      if (token != _token) return;
      _feed = feed;
    } catch (error) {
      if (token != _token) return;
      _error = error is MiguApiException ? error.message : '今日推荐加载失败，请稍后重试。';
    } finally {
      if (token == _token) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => load(force: true);
}
