import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次「咪咕拒绝本机凭据」的证据。
///
/// 只记接口在哪、服务端回了什么编码，绝不记 Cookie、Token、手机号等任何凭据内容：
/// 项目没有日志文件，界面是唯一的取证出口，而这条记录会留在偏好里跨重启可见。
class SessionRejectRecord {
  const SessionRejectRecord({
    required this.at,
    required this.host,
    required this.path,
    required this.loginScoped,
    this.status,
    this.code = '',
    this.info = '',
  });

  final DateTime at;
  final String host;
  final String path;

  /// 这个接口本身就要求登录。公开接口回 401 只是那条资源拿不到，不能当失效证据。
  final bool loginScoped;
  final int? status;
  final String code;
  final String info;

  /// 给人看的一行结论，供状态说明与自动退出提示直接引用。
  String get summary {
    final parts = <String>[
      '${_two(at.hour)}:${_two(at.minute)}',
      '$host$path',
      if (status != null) 'HTTP $status',
      if (code.isNotEmpty) '编码 $code',
      if (info.isNotEmpty) info,
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'host': host,
    'path': path,
    'loginScoped': loginScoped,
    'status': status,
    'code': code,
    'info': info,
  };

  static SessionRejectRecord? fromJson(dynamic json) {
    if (json is! Map) return null;
    final host = json['host']?.toString() ?? '';
    final path = json['path']?.toString() ?? '';
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (host.isEmpty || path.isEmpty || at == null) return null;
    return SessionRejectRecord(
      at: at,
      host: host,
      path: path,
      loginScoped: json['loginScoped'] == true,
      status: int.tryParse(json['status']?.toString() ?? ''),
      code: json['code']?.toString() ?? '',
      info: json['info']?.toString() ?? '',
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// 本机保存的「凭据被拒」账本：最近一次证据、最近一条指向登录态的证据 + 连续被拒次数。
///
/// 里面没有任何凭据，因此放在普通偏好存储而不是安全存储里；退出登录与重新验证
/// 成功都会把计数清零，避免把上一次会话的失败算到新凭据头上。
class SessionRejectLedger {
  SessionRejectLedger({
    SharedPreferences? prefs,
    DateTime Function()? clock,
    this.confirmGap = const Duration(minutes: 30),
    this.strikeWindow = const Duration(hours: 24),
  }) : _preferences = prefs,
       _clock = clock ?? DateTime.now;

  static const String _recordKey = 'migu_last_session_reject_v1';
  static const String _accountRecordKey = 'migu_last_account_reject_v1';
  static const String _strikesKey = 'migu_session_reject_strikes_v1';
  static const String _strikeAtKey = 'migu_session_reject_strike_at_v1';

  static final SessionRejectLedger instance = SessionRejectLedger();

  SharedPreferences? _preferences;
  final DateTime Function() _clock;

  /// 两次计入的账号接口拒绝至少要隔这么久。
  ///
  /// 一次登录后的批量请求里，多个接口会同时因为同一个原因被拒，那是一波失败，
  /// 不是两次独立取证；只有隔了一阵之后再次被拒，才说明这份凭据确实不被接受。
  final Duration confirmGap;

  /// 两次拒绝最多隔这么久仍算同一次判定。
  ///
  /// 计数会跨重启保留；若没有上限，几周前的一次拒绝会和新启动时的第一次拒绝
  /// 凑成“两次独立取证”，表现为刚打开应用就被自动退出。超过这个窗口的旧账
  /// 一律作废，新的第一次拒绝只降级状态、保留凭据。
  final Duration strikeWindow;

  SessionRejectRecord? _last;
  SessionRejectRecord? _lastAccount;
  int _strikes = 0;
  DateTime? _lastStrikeAt;

  SessionRejectRecord? get last => _last;

  /// 最近一次「要求登录的账号接口」被拒。
  ///
  /// 一次账号请求之后往往紧跟着歌词、封面这类公开请求，它们的失败会盖掉 [last]；
  /// 界面要说清凭据为什么不工作，得引用那条真正指向登录态的证据。
  SessionRejectRecord? get lastAccount => _lastAccount;

  int get strikes => _strikes;

  Future<void> init() async {
    _preferences ??= await SharedPreferences.getInstance();
    _last = _readRecord(_recordKey);
    _lastAccount = _readRecord(_accountRecordKey);
    _strikes = _preferences!.getInt(_strikesKey) ?? 0;
    final loadedAt = DateTime.tryParse(
      _preferences!.getString(_strikeAtKey) ?? '',
    );
    if (loadedAt != null && _clock().difference(loadedAt) > strikeWindow) {
      // 上次的拒绝已经太久远，不能拿来和这次启动凑成两次取证。
      _strikes = 0;
      _lastStrikeAt = null;
      unawaited(_persistStrikes());
    } else {
      _lastStrikeAt = loadedAt;
    }
  }

  SessionRejectRecord? _readRecord(String key) {
    final raw = _preferences!.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SessionRejectRecord.fromJson(jsonDecode(raw));
    } catch (_) {
      debugPrint('上次会话被拒记录无法解析，已忽略。');
      return null;
    }
  }

  /// 记下一条拒绝证据，返回当前计入的次数。
  ///
  /// [loginScoped] 说的是这次拒绝能不能当作本机凭据失效的证据：要求登录的账号接口
  /// 回 401 能；歌词、封面、公开搜索回 401，或账号接口回 403（分不清 Cookie 失效
  /// 还是这首歌没有权限）都不能。为假时只进 [last] 留个痕迹，既不改计数也不占
  /// [lastAccount]，免得一次偶发的资源失败把界面说明的原因带偏。
  int note({
    required Uri uri,
    required bool loginScoped,
    int? status,
    String code = '',
    String info = '',
  }) {
    final now = _clock();
    final record = SessionRejectRecord(
      at: now,
      host: uri.host,
      path: uri.path.isEmpty ? '/' : uri.path,
      loginScoped: loginScoped,
      status: status,
      code: code.trim(),
      info: sanitizeInfo(info),
    );
    _last = record;
    unawaited(_persistRecord(record, _recordKey));
    if (!loginScoped) return _strikes;
    _lastAccount = record;
    unawaited(_persistRecord(record, _accountRecordKey));
    var previous = _lastStrikeAt;
    if (previous != null && now.difference(previous) > strikeWindow) {
      _strikes = 0;
      _lastStrikeAt = null;
      previous = null;
      unawaited(_persistStrikes());
    }
    if (previous != null && now.difference(previous) < confirmGap) {
      return _strikes;
    }
    _strikes += 1;
    _lastStrikeAt = now;
    unawaited(_persistStrikes());
    return _strikes;
  }

  /// 只清计数，保留证据：凭据重新被接受、或用户主动退登时用它。
  void resetStrikes() {
    _strikes = 0;
    _lastStrikeAt = null;
    unawaited(_persistStrikes());
  }

  /// 证据与计数一起清，用于重新登录与确认退登之后。
  void clear() {
    _last = null;
    _lastAccount = null;
    _strikes = 0;
    _lastStrikeAt = null;
    final prefs = _preferences;
    if (prefs == null) return;
    unawaited(prefs.remove(_recordKey));
    unawaited(prefs.remove(_accountRecordKey));
    unawaited(prefs.remove(_strikesKey));
    unawaited(prefs.remove(_strikeAtKey));
  }

  /// 服务端文案有可能夹带请求内容本身，因此入库前先过滤再截断。
  static String sanitizeInfo(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (_suspectPattern.hasMatch(trimmed)) {
      return '（服务端文案含疑似凭据内容，已省略）';
    }
    return trimmed.length <= 48 ? trimmed : '${trimmed.substring(0, 48)}…';
  }

  static final RegExp _suspectPattern = RegExp(
    r'[=;]|https?://|[A-Za-z0-9+/]{20,}={0,2}',
  );

  Future<void> _persistRecord(SessionRejectRecord record, String key) async {
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.setString(key, jsonEncode(record.toJson()));
  }

  Future<void> _persistStrikes() async {
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.setInt(_strikesKey, _strikes);
    final at = _lastStrikeAt;
    if (at == null) {
      await prefs.remove(_strikeAtKey);
    } else {
      await prefs.setString(_strikeAtKey, at.toIso8601String());
    }
  }
}
