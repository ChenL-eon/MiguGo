import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/web_login_cookies.dart';
import 'secure_cookie_storage.dart';

/// 本地 Cookie 仓库。
///
/// - 登录保存下来的会话 Cookie 作为凭据：原生登录只落 `pacmtoken`，
///   通行证票据另存于 `PassportTicketStore`；官方页面登录可能带
///   `uid` / `msisdn` 与网页会话 id；
/// - 服务端通过 Set-Cookie 下发的 Cookie 优先于手动快照，并处理
///   Domain / Path / Secure / Max-Age / Expires 与删除语义；
/// - 凭据保存在系统安全存储中，不写入日志或普通偏好设置。
class MiguCookieStore {
  MiguCookieStore({SecureCookieStorage? secureStorage, SharedPreferences? preferences})
    : _secureStorage = secureStorage ?? FlutterSecureCookieStorage(),
      // ignore: prefer_initializing_formals
      _preferences = preferences;

  static final MiguCookieStore instance = MiguCookieStore();

  static const String _secureManualCookiesKey = 'migu_manual_cookies_v2';
  static const String _secureCookieJarKey = 'migu_cookie_jar_v2';
  static const String _legacyManualCookiesKey = 'migu_manual_cookies_v1';
  static const String _legacyCookieJarKey = 'migu_cookie_jar_v1';
  static const String _logoutMarkerKey = 'migu_logout_pending_v1';
  static const String _logoutMarkerPending = 'pending';
  static const String _logoutMarkerActive = 'active';
  static final RegExp _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final Random _webSyncRandom = Random.secure();

  final SecureCookieStorage _secureStorage;
  final Map<String, String> _manualCookies = {};
  final Map<String, _JarCookie> _jar = {};
  final Map<String, _ManagedName> _serverManaged = {};
  Future<void> _persistQueue = Future<void>.value();

  /// 登录凭据的修订号：每次整体替换、清理或定向改写时同步 +1。
  /// 只用于让被作废的登录确认“现在这份凭据还是不是我写的那份”。
  int _credentialRevision = 0;

  /// 当前登录会话的网页同步代际。官方播放器 profile 里保存同一枚值，
  /// 回收时只有对得上才允许写回，退出或换号后旧 profile 会被判定作废。
  String? _webSyncToken;

  /// 退出意图是否尚未落实：为真时启动先清理旧凭据，绝不直接采用它们。
  bool _logoutIntentPending = false;

  SharedPreferences? _preferences;
  bool _initialized = false;
  String? _storageWarning;

  bool get hasImportedLogin => _manualCookies.isNotEmpty;

  /// 当前登录会话的网页同步代际；未登录时为 null。
  String? get webSyncToken => _webSyncToken;

  int get importedCookieCount => _manualCookies.length;

  /// 本地是否保存了咪咕音乐网页登录会话 Cookie（`mg_auth_sid` 等）。
  ///
  /// 只有通行证或浏览器统计类 Cookie 时，VIP 播放一定拿不到链接；
  /// 界面与错误提示需要区分“没登录”和“登录了但凭证不完整”。
  bool get hasWebSessionCookie {
    for (final name in _manualCookies.keys) {
      if (WebLoginCookieSet.isWebSessionCookieName(name)) return true;
    }
    for (final cookie in _jar.values) {
      if (WebLoginCookieSet.isWebSessionCookieName(cookie.name)) return true;
    }
    return false;
  }

  /// 播放接口需要的账号凭据，按官方同名请求头发送。
  ///
  /// 服务端会轮换 `pacmtoken`，因此 Cookie 罐里的值优先于手动导入的快照。
  ({String? uid, String? pacmtoken, String? msisdn}) get credentials => (
    uid: _firstCookieValue(const ['mg_auth_uid', 'uid']),
    pacmtoken: _firstCookieValue(const ['mg_auth_pacmtoken', 'pacmtoken']),
    msisdn: _firstCookieValue(const ['mg_auth_msisdn', 'msisdn']),
  );

  /// 安全存储不可用或迁移失败时的说明；界面需要明确告知用户。
  String? get storageWarning => _storageWarning;

  Future<void> init() async {
    if (_initialized) return;
    _preferences ??= await SharedPreferences.getInstance();
    await _restoreSecureState();
    _initialized = true;
  }

  /// 返回可发送给目标地址的 Cookie 请求头，非咪咕域名一律不附加。
  ///
  /// 服务端下发的当前值优先；手动快照在服务端没有可用同名字段时兜底，
  /// 因此服务端轮换会覆盖旧值，而一次删除不会让登录凭据从此不再发送。
  String? cookieHeaderFor(Uri uri) {
    if (!isMiguHost(uri.host)) return null;

    if (_purgeExpired()) _scheduleJarPersist();

    final requestHost = uri.host.toLowerCase();
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    final secureRequest = uri.scheme == 'https' || uri.scheme == 'wss';
    final jarCookies =
        _jar.values
            .where(
              (cookie) =>
                  cookie.matchesHost(requestHost) &&
                  _pathMatches(requestPath, cookie.path) &&
                  (!cookie.secure || secureRequest),
            )
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));

    final pairs = <String>[];
    final sentNames = <String>{};
    for (final cookie in jarCookies) {
      pairs.add('${cookie.name}=${cookie.value}');
      sentNames.add(cookie.name);
    }
    for (final entry in _manualCookies.entries) {
      if (sentNames.contains(entry.key)) continue;
      // 服务端接管过某个名称，不代表它现在还持有值：一次 `Max-Age=0` 就会
      // 把罐子里的条目删掉。只有罐子里确实还有可用值时才压住手动快照，
      // 否则凭据会被永久抑制，表现为登录状态突然失效且只能重新导入。
      if (_isServerManaged(entry.key, requestHost) &&
          _jarHasValue(entry.key, requestHost)) {
        continue;
      }
      pairs.add('${entry.key}=${entry.value}');
    }

    if (pairs.isEmpty) return null;
    return pairs.join('; ');
  }

  /// 保存官方登录窗口读到的 Cookie 请求头，例如 `uid=...; token=...`。
  ///
  /// 整体写入会清空旧的服务端会话与本地快照，避免不同账号的 Cookie 混用。
  Future<int> importLoginCookies(String raw) async {
    final parsed = _parseCookieHeader(raw);

    _manualCookies
      ..clear()
      ..addAll(parsed);
    _jar.clear();
    _serverManaged.clear();
    _credentialRevision++;
    _startWebSyncSession();

    await _enqueuePersist(() async {
      final manualSaved = await _persistManualCookies();
      final jarSaved = await _persistJar();
      if (manualSaved && jarSaved) await _releaseLogoutIntent();
    });
    return _manualCookies.length;
  }

  /// 写入原生登录换来的会话凭据，并返回实际写入的完整快照与当时的修订号。
  ///
  /// 和手动导入一样先清空旧快照与旧的服务端会话：切换账号时不能留下上一份
  /// `pacmtoken`，否则两个账号的凭据会同时发出去。
  ///
  /// 快照用于调用方在登录被作废后按条件撤回：只有当前凭据仍是这一份时才清除。
  Future<({Map<String, String> snapshot, int revision})> applyNativeLoginSession(
    Map<String, String> cookies,
  ) async {
    final clean = _normalizeLoginCookies(cookies);

    _manualCookies
      ..clear()
      ..addAll(clean);
    _jar.clear();
    _serverManaged.clear();
    final revision = ++_credentialRevision;
    _startWebSyncSession();

    await _enqueuePersist(() async {
      final manualSaved = await _persistManualCookies();
      final jarSaved = await _persistJar();
      if (manualSaved && jarSaved) await _releaseLogoutIntent();
    });
    return (snapshot: Map<String, String>.unmodifiable(clean), revision: revision);
  }

  /// 手动快照的原样副本，供内嵌官方播放器沿用同一会话。
  Map<String, String> get loginSnapshot =>
      Map<String, String>.unmodifiable(_manualCookies);

  /// 清除本机保存的登录凭据与服务端会话快照；退出登录与切换账号都走这里。
  ///
  /// 咪咕没有登出接口，这一步只动本机，服务端那份 token 在它自己眼里仍然有效。
  /// 删除前先把退出意图写进安全存储：即使旧凭据这次删不掉，重启也不能把它们
  /// 当成登录状态读回来。
  Future<void> clearLoginCookies() async {
    _manualCookies.clear();
    _jar.clear();
    _serverManaged.clear();
    _logoutIntentPending = true;
    _credentialRevision++;
    _webSyncToken = null;
    await _enqueuePersist(() async {
      await _persistLogout();
    });
  }

  /// 仅当当前凭据仍是 [snapshot]（且修订号未变）时清除，返回撤回落盘是否完成。
  ///
  /// 比较与内存修改在同一个同步段内完成，不会给新登录留下插队窗口：
  /// - 新登录若已经换成别的凭据，修订号或快照不同，这里保持原样；
  /// - 新登录若在这之后才写入，它的落盘排在这次删除之后，最终仍是新凭据。
  ///
  /// 返回 false 表示要么没命中这份快照，要么删除/退出记录没有全部落盘；
  /// 无论哪种情况，内存都已不再是这份凭据，失败细节记录在 [storageWarning]。
  /// 这只能撤回被作废的那一份凭据，不代表能恢复它此前覆盖掉的账号。
  Future<bool> clearLoginCookiesIfUnchanged({
    required Map<String, String> snapshot,
    required int revision,
  }) {
    if (revision != _credentialRevision || !mapEquals(_manualCookies, snapshot)) {
      return Future<bool>.value(false);
    }
    _manualCookies.clear();
    _jar.clear();
    _serverManaged.clear();
    // 先记下退出意图：新登录的落盘排在这次清理后面，由它接管或清除标记。
    _logoutIntentPending = true;
    _credentialRevision++;
    _webSyncToken = null;
    var durable = false;
    return _enqueuePersist(() async {
      durable = await _persistLogout(staleCleanup: true);
    }).then((_) => durable);
  }

  /// 用续期换到的新凭据覆盖同名值，其余 Cookie 保持原样。
  ///
  /// 罐子里服务端轮换留下的同名旧值必须一起作废，否则它仍会优先于新快照
  /// 发出去；官方播放器同步来的 `mg_auth_sid` 等与会话无关的条目不受影响。
  Future<int> applyRenewedCredentials(Map<String, String> cookies) async {
    if (!_initialized) return 0;
    var changed = 0;
    cookies.forEach((name, value) {
      final cookieName = name.trim();
      final cookieValue = value.trim();
      if (cookieName.isEmpty || cookieValue.isEmpty) return;
      if (!_cookieName.hasMatch(cookieName)) return;
      if (_manualCookies[cookieName] != cookieValue) {
        _manualCookies[cookieName] = cookieValue;
        changed++;
      }
      final before = _jar.length;
      _jar.removeWhere((_, cookie) => cookie.name == cookieName);
      changed += before - _jar.length;
    });
    if (changed > 0) {
      _credentialRevision++;
      await _enqueuePersist(() async {
        await _persistManualCookies();
        await _persistJar();
      });
    }
    return changed;
  }

  /// 用网页侧刷新出来的值更新手动快照，不清空其余 Cookie。
  ///
  /// 只接受登录相关的名称（官方会话名、`mg_auth_*`）或快照里已有的名称，
  /// 避免把网页上的统计与设备 Cookie 混进凭据。返回实际变更的条数。
  ///
  /// [webSyncToken] 必须是当前登录会话的代际：官方播放器 profile 可能还带着
  /// 退出前或上一个账号的 Cookie，代际对不上时一律不写，不能让旧会话复活。
  Future<int> refreshLoginCookies(
    Map<String, String> updates, {
    String? webSyncToken,
  }) async {
    if (!_initialized) return 0;
    if (webSyncToken == null || webSyncToken != _webSyncToken || !hasImportedLogin) {
      return 0;
    }
    var changed = 0;
    updates.forEach((name, value) {
      if (value.isEmpty) return;
      final known = _manualCookies.containsKey(name);
      if (!known && !WebLoginCookieSet.looksLikeAuthCookieName(name)) return;
      if (_manualCookies[name] == value) return;
      _manualCookies[name] = value;
      changed++;
    });
    if (changed > 0) {
      _credentialRevision++;
      await _enqueuePersist(_persistManualCookies);
    }
    return changed;
  }

  /// 记录服务端下发的 Cookie，并按标准语义更新本地会话。
  Future<void> capture(Response<dynamic> response) async {
    if (!_initialized) return;

    final values = response.headers.map['set-cookie'];
    if (values == null || values.isEmpty) return;

    final uri = response.requestOptions.uri;
    if (!isMiguHost(uri.host)) return;

    var changed = false;
    for (final header in values) {
      for (final part in _splitCombinedSetCookie(header)) {
        final parsed = _parseSetCookie(part, uri);
        if (parsed == null) continue;

        final managed = _ManagedName(
          domain: parsed.domain,
          hostOnly: parsed.hostOnly,
          name: parsed.name,
        );
        _serverManaged[managed.key] = managed;

        if (parsed.deleted) {
          _jar.remove(parsed.key);
        } else {
          _jar[parsed.key] = parsed.cookie!;
        }
        changed = true;
      }
    }

    if (changed) await _enqueuePersist(_persistJar);
  }

  Future<void> _restoreSecureState() async {
    String? marker;
    try {
      marker = await _secureStorage.read(_logoutMarkerKey);
    } on SecureCookieStorageException {
      _fallbackToLegacyAfterReadFailure();
      return;
    }

    if (marker == _logoutMarkerActive) {
      _logoutIntentPending = false;
      await _tryDeleteSecure(_logoutMarkerKey);
      await _restoreStoredCredentials();
      return;
    }
    if (marker != null && marker.isNotEmpty) {
      // 认不出的值也按“退出未完成”处理：宁可要求重新登录，
      // 也不能恢复一份可能已经被用户作废的账号。
      await _completePendingLogout();
      return;
    }

    await _restoreStoredCredentials();
  }

  Future<void> _restoreStoredCredentials() async {
    String? manualRaw;
    String? jarRaw;
    try {
      manualRaw = await _secureStorage.read(_secureManualCookiesKey);
      jarRaw = await _secureStorage.read(_secureCookieJarKey);
    } on SecureCookieStorageException {
      _fallbackToLegacyAfterReadFailure();
      return;
    }

    // 安全存储里已经放着这一份，偏好里的旧明文就纯属残留：只有迁移当场成功才会删，
    // 一次断电或写回校验失手就能让它永久留在明文存储里。这里补一次收尾清理。
    if (manualRaw != null && manualRaw.isNotEmpty) {
      await _removeLegacyPlaintext(_legacyManualCookiesKey);
    }
    if (jarRaw != null && jarRaw.isNotEmpty) {
      await _removeLegacyPlaintext(_legacyCookieJarKey);
    }

    manualRaw ??= await _migrateLegacyValue(
      legacyKey: _legacyManualCookiesKey,
      secureKey: _secureManualCookiesKey,
      label: '登录 Cookie',
    );
    jarRaw ??= await _migrateLegacyValue(
      legacyKey: _legacyCookieJarKey,
      secureKey: _secureCookieJarKey,
      label: '会话 Cookie',
    );

    _restoreManualCookies(manualRaw);
    _restoreJar(jarRaw);
    if (hasImportedLogin) {
      _startWebSyncSession();
    } else {
      _webSyncToken = null;
    }
  }

  /// 上次退出已经把意图写进安全存储，但旧凭据尚未确认删除。
  ///
  /// 只要清理没完成，本次运行就不恢复任何凭据；删除全部成功后才清标记。
  Future<void> _completePendingLogout() async {
    _logoutIntentPending = true;
    if (!await _deleteStoredCredentials()) {
      _setStorageWarning(
        '系统安全存储不可用，旧登录凭据仍可能留在磁盘上；'
        '已阻止本次运行恢复旧账号，下次启动会继续清理。',
      );
      return;
    }
    if (!await _tryDeleteSecure(_logoutMarkerKey)) {
      _setStorageWarning(
        '系统安全存储不可用，退出记录未能清除；'
        '旧登录凭据已删除，下次启动会再次尝试清理。',
      );
      return;
    }
    _logoutIntentPending = false;
  }

  void _fallbackToLegacyAfterReadFailure() {
    _setStorageWarning(
      '系统安全存储不可用，登录信息本次运行结束后不会保留。'
      '本次仅临时读取旧版明文记录，未写回明文。',
    );
    _restoreLegacyIntoMemory();
    if (hasImportedLogin) {
      _startWebSyncSession();
    }
  }

  /// 安全存储已经有这一份时，把偏好里的旧明文键清掉。
  ///
  /// 只在确认安全存储读得到内容之后调用：读不通时那份明文是唯一还能用的凭据，
  /// 删了用户就得重新登录一次。
  Future<void> _removeLegacyPlaintext(String legacyKey) async {
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.remove(legacyKey);
  }

  Future<String?> _migrateLegacyValue({
    required String legacyKey,
    required String secureKey,
    required String label,
  }) async {
    final raw = _preferences?.getString(legacyKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      await _secureStorage.write(secureKey, raw);
      final readBack = await _secureStorage.read(secureKey);
      if (readBack == raw) {
        await _preferences?.remove(legacyKey);
        return raw;
      }
    } on SecureCookieStorageException {
      // 迁移失败时保留旧数据，并明确提示，不做静默明文回退。
    }

    _setStorageWarning(
      '旧版$label已读取，但迁移到系统安全存储失败；旧数据仍保留，'
      '本次运行可继续使用，后续会再次尝试迁移。',
    );
    return raw;
  }

  void _restoreLegacyIntoMemory() {
    _restoreManualCookies(_preferences?.getString(_legacyManualCookiesKey));
    _restoreJar(_preferences?.getString(_legacyCookieJarKey));
  }

  void _restoreManualCookies(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        data.forEach((key, value) {
          final name = key.toString();
          final cookieValue = value?.toString() ?? '';
          if (_cookieName.hasMatch(name) && cookieValue.isNotEmpty) {
            _manualCookies[name] = cookieValue;
          }
        });
      }
    } catch (_) {
      debugPrint('本地登录 Cookie 记录无法解析，已忽略。');
    }
  }

  void _restoreJar(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is List) {
        _restoreLegacyJar(data);
      } else if (data is Map) {
        final cookies = data['cookies'];
        if (cookies is List) _restoreLegacyJar(cookies);
        final managed = data['managed'];
        if (managed is List) {
          for (final item in managed) {
            final map = item is Map ? item : null;
            if (map == null) continue;
            final entry = _ManagedName.fromJson(map);
            if (entry == null) continue;
            _serverManaged[entry.key] = entry;
          }
        }
      }
    } catch (_) {
      debugPrint('本地会话 Cookie 记录无法解析，已忽略。');
    }
  }

  void _restoreLegacyJar(List<dynamic> data) {
    for (final item in data) {
      final map = item is Map ? item : null;
      if (map == null) continue;
      final cookie = _JarCookie.fromJson(map);
      if (cookie == null) continue;
      _jar[cookie.key] = cookie;
    }
  }

  Map<String, String> _parseCookieHeader(String raw) {
    var normalized = raw.trim();
    normalized = normalized.replaceFirst(
      RegExp(r'^cookie\s*:\s*', caseSensitive: false),
      '',
    );
    if (normalized.isEmpty) {
      throw const FormatException('Cookie 内容为空');
    }

    final parsed = <String, String>{};
    for (final segment in normalized.split(RegExp(r'[;\r\n]+'))) {
      final pair = segment.trim();
      if (pair.isEmpty) continue;
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        throw const FormatException('Cookie 格式不正确，应类似 name=value; name2=value2');
      }
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (!_cookieName.hasMatch(name) ||
          value.contains(';') ||
          value.contains('\n') ||
          value.contains('\r')) {
        throw const FormatException('Cookie 中包含不支持的字符');
      }
      parsed[name] = value;
    }

    if (parsed.isEmpty) {
      throw const FormatException('未解析到有效的 Cookie');
    }
    return parsed;
  }

  _ParsedSetCookie? _parseSetCookie(String header, Uri uri) {
    final segments = header.split(';');
    if (segments.isEmpty) return null;

    final pair = segments.first.trim();
    final separator = pair.indexOf('=');
    if (separator <= 0) return null;

    final name = pair.substring(0, separator).trim();
    var value = pair.substring(separator + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (!_cookieName.hasMatch(name) ||
        value.contains(';') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return null;
    }

    var domain = uri.host.toLowerCase();
    var hostOnly = true;
    var path = _defaultPath(uri);
    var secure = false;
    var deleted = false;
    var maxAgeSeen = false;
    DateTime? expiresAt;

    for (final segment in segments.skip(1)) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      final key = (eq >= 0 ? trimmed.substring(0, eq) : trimmed).trim().toLowerCase();
      final attrValue = eq >= 0 ? trimmed.substring(eq + 1).trim() : '';

      if (key == 'domain') {
        final candidate = attrValue.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
        if (candidate.isEmpty) continue;
        if (!isMiguHost(candidate) ||
            !_hostMatchesDomain(uri.host, candidate, hostOnly: false)) {
          return null;
        }
        domain = candidate;
        hostOnly = false;
      } else if (key == 'path') {
        if (attrValue.startsWith('/')) path = attrValue;
      } else if (key == 'max-age') {
        final seconds = int.tryParse(attrValue);
        if (seconds == null) continue;
        maxAgeSeen = true;
        if (seconds <= 0) {
          deleted = true;
          expiresAt = null;
        } else {
          deleted = false;
          expiresAt = DateTime.now().add(Duration(seconds: seconds));
        }
      } else if (key == 'expires') {
        if (maxAgeSeen) continue;
        try {
          final parsed = HttpDate.parse(attrValue);
          expiresAt = parsed;
          deleted = !parsed.isAfter(DateTime.now());
        } catch (_) {
          // 无法识别的过期时间按会话 Cookie 处理。
        }
      } else if (key == 'secure') {
        secure = true;
      }
    }

    final cookie = _JarCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      hostOnly: hostOnly,
      secure: secure,
      expiresAt: expiresAt,
    );
    return _ParsedSetCookie(
      name: name,
      domain: domain,
      hostOnly: hostOnly,
      path: path,
      deleted: deleted,
      cookie: deleted ? null : cookie,
    );
  }

  bool _purgeExpired() {
    final now = DateTime.now();
    final before = _jar.length;
    _jar.removeWhere(
      (_, cookie) => cookie.expiresAt != null && cookie.expiresAt!.isBefore(now),
    );
    return _jar.length != before;
  }

  bool _isServerManaged(String name, String host) {
    for (final managed in _serverManaged.values) {
      if (managed.name == name && managed.matchesHost(host)) return true;
    }
    return false;
  }

  /// 罐子里是否仍有对该域名生效、且值非空的 Cookie。
  bool _jarHasValue(String name, String host) {
    for (final cookie in _jar.values) {
      if (cookie.name != name || cookie.value.isEmpty) continue;
      if (cookie.matchesHost(host)) return true;
    }
    return false;
  }

  String? _firstCookieValue(List<String> names) {
    if (_purgeExpired()) _scheduleJarPersist();
    for (final name in names) {
      for (final cookie in _jar.values) {
        if (cookie.name == name && cookie.value.isNotEmpty) return cookie.value;
      }
      final manual = _manualCookies[name];
      if (manual != null && manual.isNotEmpty) return manual;
    }
    return null;
  }

  void _scheduleJarPersist() {
    unawaited(_enqueuePersist(_persistJar));
  }

  void _startWebSyncSession() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_webSyncRandom.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    _webSyncToken = buffer.toString();
  }

  Future<void> _enqueuePersist(Future<void> Function() task) {
    final result = _persistQueue.then((_) => task());
    _persistQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Map<String, String> _normalizeLoginCookies(Map<String, String> cookies) {
    final clean = <String, String>{};
    cookies.forEach((name, value) {
      final cookieName = name.trim();
      final cookieValue = value.trim();
      if (cookieValue.isEmpty) return;
      if (!_cookieName.hasMatch(cookieName)) {
        throw const FormatException('登录凭据名称不合法。');
      }
      if (cookieValue.contains(';') ||
          cookieValue.contains('\n') ||
          cookieValue.contains('\r')) {
        throw const FormatException('登录凭据内容不合法。');
      }
      clean[cookieName] = cookieValue;
    });
    if (clean.isEmpty) {
      throw const FormatException('登录结果里没有可用的凭据。');
    }
    return clean;
  }

  /// 退出落盘：先记录意图，再删旧凭据，全部删掉后才清掉意图。
  ///
  /// 返回 true 只代表退出意图与两份凭据都已在磁盘上处理干净；
  /// 任何一步失败都保持意图并返回 false，绝不把“内存已清空”当成“磁盘已撤回”。
  Future<bool> _persistLogout({bool staleCleanup = false}) async {
    final markerWritten = await _tryWriteSecure(_logoutMarkerKey, _logoutMarkerPending);
    final credentialsRemoved = await _deleteStoredCredentials();
    final markerRemoved =
        credentialsRemoved && await _tryDeleteSecure(_logoutMarkerKey);
    if (credentialsRemoved && markerRemoved) {
      _logoutIntentPending = false;
      return true;
    }

    _logoutIntentPending = true;
    if (!credentialsRemoved) {
      _setStorageWarning(
        staleCleanup
            ? markerWritten
                  ? '系统安全存储不可用，已作废的旧登录凭据未能从磁盘撤回；'
                        '已记录退出，重启后不会恢复旧账号。'
                  : '系统安全存储不可用，已作废的旧登录凭据未能从磁盘撤回，'
                        '退出记录也未能保存；重启后可能恢复这次被作废的旧账号。'
            : markerWritten
            ? '系统安全存储不可用，旧登录凭据未能从磁盘删除；'
                  '已记录退出，重启后不会恢复旧账号。'
            : '系统安全存储不可用，旧登录凭据未能从磁盘删除，'
                  '退出记录也未能保存；重启后可能恢复旧账号。',
        replaceExisting: true,
      );
      return false;
    }
    _setStorageWarning(
      staleCleanup
          ? '系统安全存储不可用，退出记录未能清除；'
                '已作废的旧登录凭据已撤回，下次启动会再次尝试清理。'
          : '系统安全存储不可用，退出记录未能清除；'
                '旧登录凭据已删除，下次启动会再次尝试清理。',
      replaceExisting: true,
    );
    return false;
  }

  /// 新登录凭据已确认落盘，接管上一次未完成的退出。
  ///
  /// 能删标记就删；删不掉就改写成 active，让下次启动知道新登录已经生效。
  /// 两者都失败时必须保持 pending，宁可要求重新登录也不能误采用旧账号。
  Future<void> _releaseLogoutIntent() async {
    if (!_logoutIntentPending) return;
    if (await _tryDeleteSecure(_logoutMarkerKey)) {
      _logoutIntentPending = false;
      return;
    }
    if (await _tryWriteSecure(_logoutMarkerKey, _logoutMarkerActive)) {
      _logoutIntentPending = false;
      return;
    }
    _setStorageWarning(
      '系统安全存储不可用，新登录凭据已写入，但退出记录未能更新；'
      '重启后可能需要重新登录。',
      replaceExisting: true,
    );
  }

  /// 删除安全存储与旧版明文里的全部登录凭据；只有全部成功才算清理完成。
  Future<bool> _deleteStoredCredentials() async {
    final manualRemoved = await _tryDeleteSecure(_secureManualCookiesKey);
    final jarRemoved = await _tryDeleteSecure(_secureCookieJarKey);
    final legacyRemoved = await _deleteLegacyPlaintext();
    return manualRemoved && jarRemoved && legacyRemoved;
  }

  Future<bool> _deleteLegacyPlaintext() async {
    final preferences = _preferences;
    if (preferences == null) return true;
    try {
      await preferences.remove(_legacyManualCookiesKey);
      await preferences.remove(_legacyCookieJarKey);
      return preferences.getString(_legacyManualCookiesKey) == null &&
          preferences.getString(_legacyCookieJarKey) == null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryDeleteSecure(String key) async {
    try {
      await _secureStorage.delete(key);
      return true;
    } on SecureCookieStorageException {
      return false;
    }
  }

  Future<bool> _tryWriteSecure(String key, String value) async {
    try {
      await _secureStorage.write(key, value);
      return true;
    } on SecureCookieStorageException {
      return false;
    }
  }

  Future<bool> _persistManualCookies() async {
    if (_manualCookies.isEmpty) {
      return _writeSecure(_secureManualCookiesKey, null);
    }
    return _writeSecure(_secureManualCookiesKey, jsonEncode(_manualCookies));
  }

  Future<bool> _persistJar() async {
    if (_jar.isEmpty && _serverManaged.isEmpty) {
      return _writeSecure(_secureCookieJarKey, null);
    }
    final payload = jsonEncode({
      'version': 2,
      'cookies': _jar.values.map((cookie) => cookie.toJson()).toList(),
      'managed': _serverManaged.values.map((managed) => managed.toJson()).toList(),
    });
    return _writeSecure(_secureCookieJarKey, payload);
  }

  Future<bool> _writeSecure(String key, String? value) async {
    try {
      if (value == null) {
        await _secureStorage.delete(key);
      } else {
        await _secureStorage.write(key, value);
      }
      return true;
    } on SecureCookieStorageException {
      _setStorageWarning('系统安全存储不可用，登录信息仅在本次运行内有效，重启后需要重新导入。');
      return false;
    }
  }

  void _setStorageWarning(String message, {bool replaceExisting = false}) {
    if (_storageWarning != null && !replaceExisting) return;
    _storageWarning = message;
    debugPrint('登录凭据安全存储不可用，已停止写入明文，界面将提示用户。');
  }

  Iterable<String> _splitCombinedSetCookie(String header) {
    // Dio 通常已把多条 Set-Cookie 放入 List；这里仅处理极少数合并返回的情况。
    return header.split(RegExp(r',(?=[^;,]+=[^;,]+;?)')).map((e) => e.trim());
  }
}

class _ParsedSetCookie {
  const _ParsedSetCookie({
    required this.name,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.deleted,
    this.cookie,
  });

  final String name;
  final String domain;
  final bool hostOnly;
  final String path;
  final bool deleted;
  final _JarCookie? cookie;

  String get key => '${domain.toLowerCase()}|$path|$name';
}

class _JarCookie {
  const _JarCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expiresAt;

  String get key => '${domain.toLowerCase()}|$path|$name';

  bool matchesHost(String host) => _hostMatchesDomain(host, domain, hostOnly: hostOnly);

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'hostOnly': hostOnly,
    'secure': secure,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  static _JarCookie? fromJson(Map<dynamic, dynamic> map) {
    final name = map['name']?.toString() ?? '';
    final value = map['value']?.toString() ?? '';
    final domain = map['domain']?.toString() ?? '';
    if (name.isEmpty ||
        value.isEmpty ||
        domain.isEmpty ||
        !RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name)) {
      return null;
    }
    final path = map['path']?.toString() ?? '/';
    return _JarCookie(
      name: name,
      value: value,
      domain: domain,
      path: path.startsWith('/') ? path : '/',
      hostOnly: map['hostOnly'] is bool ? map['hostOnly'] as bool : true,
      secure: map['secure'] is bool ? map['secure'] as bool : false,
      expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
    );
  }
}

class _ManagedName {
  const _ManagedName({
    required this.domain,
    required this.hostOnly,
    required this.name,
  });

  final String domain;
  final bool hostOnly;
  final String name;

  String get key => '${domain.toLowerCase()}|$hostOnly|$name';

  bool matchesHost(String host) => _hostMatchesDomain(host, domain, hostOnly: hostOnly);

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'hostOnly': hostOnly,
    'name': name,
  };

  static _ManagedName? fromJson(Map<dynamic, dynamic> map) {
    final domain = map['domain']?.toString() ?? '';
    final name = map['name']?.toString() ?? '';
    if (domain.isEmpty || name.isEmpty) return null;
    return _ManagedName(
      domain: domain,
      hostOnly: map['hostOnly'] is bool ? map['hostOnly'] as bool : true,
      name: name,
    );
  }
}

/// 这个主机名是不是咪咕自己的域。
///
/// 本机凭据（Cookie 与 uid/pacmtoken/msisdn 请求头）只能发往咪咕域，判断必须严格：
/// `evil-migu.cn` 这类后缀相邻的域名不算，别拿 `endsWith('migu.cn')` 当门槛。
bool isMiguHost(String host) {
  final value = host.toLowerCase();
  return value == 'migu.cn' || value.endsWith('.migu.cn');
}

bool _hostMatchesDomain(String host, String domain, {required bool hostOnly}) {
  final target = domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  if (target.isEmpty) return false;
  final value = host.toLowerCase();
  if (value == target) return true;
  return !hostOnly && value.endsWith('.$target');
}

bool _pathMatches(String requestPath, String cookiePath) {
  if (requestPath == cookiePath) return true;
  if (!requestPath.startsWith(cookiePath)) return false;
  if (cookiePath.endsWith('/')) return true;
  return requestPath.length > cookiePath.length &&
      requestPath[cookiePath.length] == '/';
}

String _defaultPath(Uri uri) {
  final path = uri.path;
  if (path.isEmpty || !path.startsWith('/')) return '/';
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return path.substring(0, lastSlash);
}
