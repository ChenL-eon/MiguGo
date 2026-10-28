import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update_service.dart';

/// 版本检查的状态：结论留在本机，重启后仍能看到上次查到了什么。
class UpdateProvider extends ChangeNotifier {
  UpdateProvider(this._service);

  static const String _resultKey = 'migu_update_check_result_v1';
  static const String _autoCheckKey = 'migu_auto_check_updates_v1';

  /// 启动检查的最短间隔：反复开关应用不该去敲 GitHub 的限流。
  static const Duration _minInterval = Duration(hours: 12);

  final AppUpdateService _service;

  UpdateCheckResult? _last;
  DateTime? _checkedAt;
  String? _failure;
  bool _autoCheck = true;
  bool _checking = false;

  UpdateCheckResult? get last => _last;
  DateTime? get checkedAt => _checkedAt;
  String? get failure => _failure;
  bool get autoCheck => _autoCheck;
  bool get checking => _checking;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _autoCheck = preferences.getBool(_autoCheckKey) ?? true;
    final raw = preferences.getString(_resultKey);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        _checkedAt = DateTime.fromMillisecondsSinceEpoch(saved['at'] as int);
        _last = UpdateCheckResult(
          status: UpdateCheckStatus.values.byName(saved['status'] as String),
          latestVersion: saved['version'] as String?,
        );
      } on Object {
        // 记录读坏了就当作没查过，别让关于页因此打不开。
        _checkedAt = null;
        _last = null;
      }
    }
    notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    if (_autoCheck == value) return;
    _autoCheck = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoCheckKey, value);
  }

  /// 启动时的那一次：关了开关或刚查过就不必再请求。
  Future<void> checkOnStartup() async {
    if (!_autoCheck) return;
    final at = _checkedAt;
    if (at != null && DateTime.now().difference(at) < _minInterval) return;
    await check();
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    _failure = null;
    notifyListeners();
    final result = await _service.check();
    _checking = false;
    // 失败不覆盖上一次的好结果，只在界面上说明这次没查到。
    if (result.status == UpdateCheckStatus.failed) {
      _failure = result.failure;
    } else {
      _last = result;
      _checkedAt = DateTime.now();
      await _persist();
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final result = _last;
    final at = _checkedAt;
    if (result == null || at == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _resultKey,
      jsonEncode({
        'status': result.status.name,
        'version': result.latestVersion,
        'at': at.millisecondsSinceEpoch,
      }),
    );
  }
}
