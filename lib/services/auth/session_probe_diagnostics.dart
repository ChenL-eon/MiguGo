import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import 'session_probe.dart';
import 'session_reject_ledger.dart';

/// 一次登录态探测的元数据，用来判断 `checkPacMtoken` 的轮换是否真的续命。
///
/// 只记时间、触发点、返回码、是否轮换与 Cookie 的过期属性，外加本机所使用凭据的
/// **指纹**（不可还原的短哈希 + 长度）与写入通道；不含凭据值本身。
class SessionProbeRecord {
  const SessionProbeRecord({
    required this.at,
    required this.trigger,
    required this.verdict,
    this.officialStatus,
    this.officialCode = '',
    this.officialInfo = '',
    this.rotationHeader = false,
    this.rotated = false,
    this.expiryBefore,
    this.expiryFromResponse,
    this.expiryAfter,
    this.profileStatus,
    this.profileCode = '',
    this.credentialBefore = '无',
    this.credentialAfter,
    this.credentialSource = 'none',
    this.probeShared = false,
    this.credentialHeaderMatches,
    this.note = '',
  });

  final DateTime at;
  final String trigger;
  final SessionProbe verdict;
  final int? officialStatus;
  final String officialCode;
  final String officialInfo;
  final bool rotationHeader;
  final bool rotated;
  final DateTime? expiryBefore;
  final DateTime? expiryFromResponse;
  final DateTime? expiryAfter;
  final int? profileStatus;
  final String profileCode;

  /// 这次探测带出去的凭据指纹；[credentialAfter] 为 null 表示这一轮没走到写回。
  final String credentialBefore;
  final String? credentialAfter;

  /// 当前凭据最近一次由哪条通道写入本机（import / rotation / set-cookie / …）。
  final String credentialSource;

  /// 是否复用了一次已在飞的官方校验（同会话并发探测的单飞结果）。
  final bool probeShared;

  /// Cookie 头与裸 `pacmtoken` 头是否带出同一份凭据；null = 未检查。
  final bool? credentialHeaderMatches;
  final String note;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'trigger': trigger,
    'verdict': verdict.name,
    'officialStatus': officialStatus,
    'officialCode': officialCode,
    'officialInfo': officialInfo,
    'rotationHeader': rotationHeader,
    'rotated': rotated,
    'expiryBefore': expiryBefore?.toIso8601String(),
    'expiryFromResponse': expiryFromResponse?.toIso8601String(),
    'expiryAfter': expiryAfter?.toIso8601String(),
    'profileStatus': profileStatus,
    'profileCode': profileCode,
    'credentialBefore': credentialBefore,
    'credentialAfter': credentialAfter,
    'credentialSource': credentialSource,
    'probeShared': probeShared,
    'credentialHeaderMatches': credentialHeaderMatches,
    'note': note,
  };

  static SessionProbeRecord? fromJson(dynamic json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (at == null) return null;
    return SessionProbeRecord(
      at: at,
      trigger: json['trigger']?.toString() ?? '',
      verdict: SessionProbe.values.firstWhere(
        (item) => item.name == json['verdict']?.toString(),
        orElse: () => SessionProbe.unknown,
      ),
      officialStatus: int.tryParse(json['officialStatus']?.toString() ?? ''),
      officialCode: json['officialCode']?.toString() ?? '',
      officialInfo: json['officialInfo']?.toString() ?? '',
      rotationHeader: json['rotationHeader'] == true,
      rotated: json['rotated'] == true,
      expiryBefore: DateTime.tryParse(json['expiryBefore']?.toString() ?? ''),
      expiryFromResponse: DateTime.tryParse(
        json['expiryFromResponse']?.toString() ?? '',
      ),
      expiryAfter: DateTime.tryParse(json['expiryAfter']?.toString() ?? ''),
      profileStatus: int.tryParse(json['profileStatus']?.toString() ?? ''),
      profileCode: json['profileCode']?.toString() ?? '',
      credentialBefore: json['credentialBefore']?.toString() ?? '无',
      credentialAfter: json['credentialAfter']?.toString(),
      credentialSource: json['credentialSource']?.toString() ?? 'none',
      probeShared: json['probeShared'] == true,
      credentialHeaderMatches: json['credentialHeaderMatches'] is bool
          ? json['credentialHeaderMatches'] as bool
          : null,
      note: json['note']?.toString() ?? '',
    );
  }
}

/// 登录探测的滚动记录：只保存在本机偏好里，供调试版导出分析。
///
/// 记录本身不含任何凭据，因此不需要放进安全存储；正式版默认不写。
class SessionProbeDiagnostics {
  SessionProbeDiagnostics({
    this.preferences,
    bool? enabled,
    this.maxEntries = 300,
  }) : _enabled = enabled ?? kDebugMode;

  static final SessionProbeDiagnostics instance = SessionProbeDiagnostics();

  static const String storageKey = 'migu_session_probe_diag_v1';

  /// 换票（只有调试入口会主动发起）的结果也写进同一份滚动记录，靠这个 trigger
  /// 与探测区分。这张票换没换到新凭据，光看探测那条读不出来。
  static const String renewalTrigger = 'renewal';

  final SharedPreferences? preferences;
  final bool _enabled;
  final int maxEntries;

  final List<SessionProbeRecord> _records = [];
  Future<void> _queue = Future<void>.value();
  bool _loaded = false;

  bool get enabled => _enabled;

  Future<void> record(SessionProbeRecord record) {
    if (!_enabled) return Future<void>.value();
    final task = _queue.then((_) async {
      await _ensureLoaded();
      _records.add(
        SessionProbeRecord(
          at: record.at,
          trigger: record.trigger,
          verdict: record.verdict,
          officialStatus: record.officialStatus,
          officialCode: _cleanCode(record.officialCode),
          officialInfo: SessionRejectLedger.sanitizeInfo(record.officialInfo),
          rotationHeader: record.rotationHeader,
          rotated: record.rotated,
          expiryBefore: record.expiryBefore,
          expiryFromResponse: record.expiryFromResponse,
          expiryAfter: record.expiryAfter,
          profileStatus: record.profileStatus,
          profileCode: _cleanCode(record.profileCode),
          credentialBefore: _cleanTag(record.credentialBefore),
          credentialAfter: record.credentialAfter == null
              ? null
              : _cleanTag(record.credentialAfter!),
          credentialSource: _cleanTag(record.credentialSource),
          probeShared: record.probeShared,
          credentialHeaderMatches: record.credentialHeaderMatches,
          note: SessionRejectLedger.sanitizeInfo(record.note),
        ),
      );
      if (_records.length > maxEntries) {
        _records.removeRange(0, _records.length - maxEntries);
      }
      await _persist();
    });
    _queue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<List<SessionProbeRecord>> load() async {
    await _ensureLoaded();
    return List<SessionProbeRecord>.unmodifiable(_records);
  }

  Future<String> exportText({DateTime? now}) async {
    final records = await load();
    final buffer = StringBuffer()
      ..writeln('MiguGo 登录探测记录 · v${AppConstants.appVersion}')
      ..writeln(
        '生成 ${_stamp(now ?? DateTime.now())} · 共 ${records.length} 条'
        '（最近 $maxEntries 次，仅记录元数据，不含凭据）',
      );
    for (final record in records) {
      buffer
        ..writeln()
        ..writeln(
          '${_stamp(record.at)}  ${record.trigger}  →  ${record.verdict.name}',
        );
      if (record.trigger == renewalTrigger) {
        // 有码就报码；没码时把回包形态顶上去，否则这一行只剩一个 HTTP 200，
        // 分不清是咪咕认不下这张票据，还是请求根本没走到它面前。
        final codePart = record.officialCode.isEmpty
            ? (record.officialInfo.isEmpty
                  ? ''
                  : ', 回包 ${record.officialInfo}')
            : ', 票据码 ${record.officialCode}';
        buffer.writeln(
          '  续期: 本机已换新凭据=${record.rotated ? '是' : '否'}'
          '${record.officialStatus == null ? '' : ', HTTP ${record.officialStatus}'}'
          '$codePart',
        );
        if (record.note.isNotEmpty) {
          buffer.writeln('  结果: ${record.note}');
        }
        continue;
      }
      final matchPart = record.credentialHeaderMatches == null
          ? ''
          : ', Cookie 与请求头一致='
                '${record.credentialHeaderMatches! ? '是' : '否'}';
      buffer
        ..writeln(
          '  官方: ${_http(record.officialStatus)}, '
          'code=${record.officialCode.isEmpty ? '空' : record.officialCode}'
          '${record.officialInfo.isEmpty ? '' : ', info=${record.officialInfo}'}',
        )
        ..writeln(
          '  轮换: 响应头=${record.rotationHeader ? '有' : '无'}, '
          '本地已更换=${record.rotated ? '是' : '否'}'
          '${record.probeShared ? ', 复用了一次在飞探测' : ''}',
        )
        ..writeln(
          '  过期: 探测前=${_expiry(record.expiryBefore)}, '
          '响应中=${_expiry(record.expiryFromResponse)}, '
          '写回后=${_expiry(record.expiryAfter)}',
        )
        ..writeln(
          '  凭证: 探测前=${record.credentialBefore}, '
          '写回后=${record.credentialAfter ?? '未走到写回'}, '
          '来源=${record.credentialSource}$matchPart',
        );
      if (record.profileStatus != null || record.profileCode.isNotEmpty) {
        buffer.writeln(
          '  资料: ${_http(record.profileStatus)}, '
          'code=${record.profileCode.isEmpty ? '空' : record.profileCode}',
        );
      }
      if (record.note.isNotEmpty) {
        buffer.writeln('  备注: ${record.note}');
      }
    }
    return buffer.toString().trimRight();
  }

  Future<void> clear() {
    final task = _queue.then((_) async {
      _records.clear();
      _loaded = true;
      final prefs = preferences ?? await _prefs();
      await prefs?.remove(storageKey);
    });
    _queue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = preferences ?? await _prefs();
    final raw = prefs?.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        final record = SessionProbeRecord.fromJson(item);
        if (record != null) _records.add(record);
      }
      if (_records.length > maxEntries) {
        _records.removeRange(0, _records.length - maxEntries);
      }
    } catch (_) {
      // 旧版本或损坏的记录直接丢弃，不能影响探测本身。
      _records.clear();
    }
  }

  Future<void> _persist() async {
    final prefs = preferences ?? await _prefs();
    await prefs?.setString(
      storageKey,
      jsonEncode([for (final record in _records) record.toJson()]),
    );
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static String _cleanCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length > 32 ||
        trimmed.contains(RegExp(r'[\s;=]')) ||
        trimmed.contains('/')) {
      return '（已省略）';
    }
    return trimmed;
  }

  /// 本机自造的短标记（凭据指纹、写入通道）走这条：允许 `/-_`，长度受限。
  ///
  /// 这些值来自本机散列与固定枚举，不是服务端文案，因此不复用 [_cleanCode]
  /// ——那个会把指纹里的 `/` 当非法字符，整段省略掉。
  static String _cleanTag(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '无';
    if (trimmed.length > 40 ||
        !RegExp(r'^[0-9A-Za-z_\-/]+$').hasMatch(trimmed)) {
      return '（已省略）';
    }
    return trimmed;
  }

  static String _http(int? status) => status == null ? '未调用' : 'HTTP $status';

  static String _expiry(DateTime? value) =>
      value == null ? '无' : _stamp(value.toLocal());

  static String _stamp(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
