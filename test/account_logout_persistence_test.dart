import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _manualKey = 'migu_manual_cookies_v2';
const _pendingKey = 'migu_logout_pending_v1';
const _legacyManualKey = 'migu_manual_cookies_v1';
const _legacyJarKey = 'migu_cookie_jar_v1';

const _aCookie = 'uid=u-a; pacmtoken=pacm-a';
const _bCookie = 'uid=u-b; pacmtoken=pacm-b';

class _AppSession {
  _AppSession(this.storage, this.cookieStore, this.account);

  final FakeSecureCookieStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;
}

/// 模拟一次冷启动：Cookie 仓库、认证状态与票据都从同一份存储重新读取。
Future<_AppSession> _open(FakeSecureCookieStorage storage) async {
  final cookieStore = MiguCookieStore(secureStorage: storage);
  await cookieStore.init();
  final account = AccountProvider(
    cookieStore: cookieStore,
    authSessionStore: AuthSessionStore(storage: storage),
    passportTicketStore: PassportTicketStore(storage: storage),
  );
  await account.initialize();
  return _AppSession(storage, cookieStore, account);
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '等待异步窗口超时');
}

class _GatedStorage extends FakeSecureCookieStorage {
  String? _gateKey;
  Completer<void>? _gate;
  int gatedDeletes = 0;

  Completer<void> gateNextDelete(String key) {
    _gateKey = key;
    return _gate = Completer<void>();
  }

  @override
  Future<void> delete(String key) async {
    final gate = _gate;
    if (gate != null && key == _gateKey) {
      _gate = null;
      _gateKey = null;
      gatedDeletes++;
      await gate.future;
    }
    await super.delete(key);
  }
}

class _RecordingStorage extends FakeSecureCookieStorage {
  final List<String> operations = [];

  @override
  Future<void> write(String key, String value) async {
    operations.add('write:$key');
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    operations.add('delete:$key');
    await super.delete(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<_AppSession> signedIn(
    FakeSecureCookieStorage storage, {
    String cookie = _aCookie,
  }) async {
    final session = await _open(storage);
    await session.account.importLoginCookie(cookie);
    expect(session.account.hasLogin, isTrue);
    return session;
  }

  group('R5 退出意图与旧 Cookie 恢复', () {
    test('A. 退出时旧 Cookie 删不掉：本次运行退出，重启也不恢复旧账号', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_manualKey);
      await first.account.signOut();

      // 本次运行：内存已经退出，但旧记录确实还留在磁盘上。
      expect(first.account.hasLogin, isFalse);
      expect(first.cookieStore.hasImportedLogin, isFalse);
      expect(first.cookieStore.credentials.uid, isNull);
      expect(first.account.storageWarning, isNotNull);
      expect(storage.values[_manualKey], contains('pacm-a'));

      // 重启：只要退出意图已经落盘，旧 Cookie 就不能再被采用。
      final reopened = await _open(storage);
      expect(reopened.cookieStore.hasImportedLogin, isFalse);
      expect(reopened.account.hasLogin, isFalse);
      expect(reopened.account.status, AuthStatus.none);
      expect(
        reopened.cookieStore.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        isNull,
      );
      expect(reopened.account.storageWarning, isNotNull);
      expect(storage.values[_pendingKey], 'pending');
      expect(first.account.storageWarning, contains('已记录退出'));
    });

    test('B. 删除暂时失败：重启阻止采用旧账号，存储恢复后继续清理', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_manualKey);
      await first.account.signOut();
      expect(storage.values[_manualKey], contains('pacm-a'));

      // 第一次重启时存储仍删不掉：退出仍然生效，不能把旧账号读回来。
      final blocked = await _open(storage);
      expect(blocked.account.hasLogin, isFalse);
      expect(blocked.account.status, AuthStatus.none);
      expect(blocked.account.storageWarning, isNotNull);
      expect(blocked.cookieStore.credentials.uid, isNull);
      expect(storage.values[_manualKey], contains('pacm-a'));
      expect(storage.values[_pendingKey], 'pending');

      // 存储恢复后再次启动：启动清理继续执行，旧记录与退出标记都消失。
      storage.failDeleteKeys.clear();
      final cleaned = await _open(storage);
      expect(cleaned.account.hasLogin, isFalse);
      expect(cleaned.account.status, AuthStatus.none);
      expect(cleaned.account.storageWarning, isNull);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], isNull);
    });

    test('C. 正常退出仍按原样清空，重启保持未登录', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      await first.account.signOut();

      expect(first.account.hasLogin, isFalse);
      expect(first.account.storageWarning, isNull);
      expect(storage.values, isEmpty);

      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isFalse);
      expect(reopened.account.status, AuthStatus.none);
      expect(reopened.cookieStore.credentials.uid, isNull);
      expect(storage.values, isEmpty);
    });

    test('D. 退出意图先于旧 Cookie 删除写入安全存储', () async {
      final storage = _RecordingStorage();
      final first = await signedIn(storage);
      storage.operations.clear();

      await first.account.signOut();

      final markerWrite = storage.operations.indexOf('write:$_pendingKey');
      final manualDelete = storage.operations.indexOf('delete:$_manualKey');
      expect(markerWrite, isNonNegative, reason: '必须先记录退出意图再删旧凭据');
      expect(manualDelete, isNonNegative);
      expect(markerWrite, lessThan(manualDelete));
    });

    test('E. 退出卡在旧 Cookie 删除时新登录排队，重启只恢复新账号', () async {
      final storage = _GatedStorage();
      final first = await signedIn(storage);

      final gate = storage.gateNextDelete(_manualKey);
      final signOutDone = first.account.signOut();
      await _pumpUntil(() => storage.gatedDeletes == 1);
      expect(first.account.hasLogin, isFalse);

      var loginDone = false;
      final loginB = first.account.importLoginCookie(_bCookie);
      unawaited(loginB.then((_) => loginDone = true));
      await _flush();
      // 退出占着 Cookie 队列，B 的落盘只能排在旧删除之后。
      expect(loginDone, isFalse);
      expect(first.account.hasLogin, isTrue);

      gate.complete();
      await signOutDone;
      await loginB;
      await _flush();

      expect(first.cookieStore.credentials.uid, 'u-b');
      expect(storage.values[_manualKey], contains('pacm-b'));
      expect(storage.values[_pendingKey], isNull);

      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isTrue);
      expect(reopened.account.status, AuthStatus.unverified);
      expect(reopened.cookieStore.credentials.uid, 'u-b');
      expect(reopened.cookieStore.credentials.pacmtoken, 'pacm-b');
    });

    test('F. 退出清理失败后直接重新登录：新登录接管退出记录', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_manualKey);
      await first.account.signOut();
      expect(storage.values[_pendingKey], 'pending');
      expect(storage.values[_manualKey], contains('pacm-a'));

      storage.failDeleteKeys.clear();
      await first.account.importLoginCookie(_bCookie);

      expect(storage.values[_pendingKey], isNull);
      expect(storage.values[_manualKey], contains('pacm-b'));

      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isTrue);
      expect(reopened.account.status, AuthStatus.unverified);
      expect(reopened.cookieStore.credentials.uid, 'u-b');
      expect(reopened.cookieStore.credentials.pacmtoken, 'pacm-b');
    });

    test('G. 退出意图写不进且旧 Cookie 也删不掉：如实提示重启可能恢复旧账号', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failWriteKeys.add(_pendingKey);
      storage.failDeleteKeys.add(_manualKey);
      await first.account.signOut();

      expect(first.account.hasLogin, isFalse);
      expect(storage.values[_pendingKey], isNull);
      expect(storage.values[_manualKey], contains('pacm-a'));
      expect(first.account.storageWarning, contains('重启后可能恢复旧账号'));

      // 标记没落盘、删除又失败时，重启无法知道这次退出未完成；
      // 这个用例锁住“必须如实提示”的边界，而不是假装已经安全。
      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isTrue);
      expect(reopened.cookieStore.credentials.uid, 'u-a');
    });

    test('H. 凭据已删但退出记录删不掉：保持退出意图并在下次启动继续清理', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_pendingKey);
      await first.account.signOut();

      expect(first.account.hasLogin, isFalse);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], 'pending');
      expect(first.account.storageWarning, contains('退出记录未能清除'));

      storage.failDeleteKeys.clear();
      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isFalse);
      expect(reopened.account.status, AuthStatus.none);
      expect(reopened.account.storageWarning, isNull);
      expect(storage.values[_pendingKey], isNull);
    });

    test('I. 退出意图已落盘：启动时即使删除仍失败也不采用旧 Cookie', () async {
      final storage = FakeSecureCookieStorage();
      storage.values[_manualKey] = jsonEncode({
        'uid': 'u-old',
        'pacmtoken': 'pacm-old',
      });
      storage.values[_pendingKey] = 'pending';
      storage.failDeleteKeys.add(_manualKey);

      final blocked = await _open(storage);
      expect(blocked.cookieStore.hasImportedLogin, isFalse);
      expect(blocked.account.hasLogin, isFalse);
      expect(blocked.account.status, AuthStatus.none);
      expect(blocked.cookieStore.credentials.uid, isNull);
      expect(blocked.account.storageWarning, isNotNull);
      expect(storage.values[_pendingKey], 'pending');

      storage.failDeleteKeys.clear();
      final cleaned = await _open(storage);
      expect(cleaned.account.hasLogin, isFalse);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], isNull);
    });

    test('J. 退出意图优先于旧版明文迁移，明文里的旧账号不会被迁回', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'uid': 'u-legacy', 'pacmtoken': 'pacm-legacy'}),
      });
      final storage = FakeSecureCookieStorage();
      storage.values[_pendingKey] = 'pending';

      final session = await _open(storage);

      expect(session.cookieStore.hasImportedLogin, isFalse);
      expect(session.account.hasLogin, isFalse);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyManualKey), isNull);
      expect(prefs.getString(_legacyJarKey), isNull);
      expect(session.account.storageWarning, isNull);
    });

    test('K. 已标记为 active 的退出记录：启动采用新凭据并清掉记录', () async {
      final storage = FakeSecureCookieStorage();
      storage.values[_manualKey] = jsonEncode({'uid': 'u-b', 'pacmtoken': 'pacm-b'});
      storage.values[_pendingKey] = 'active';

      final session = await _open(storage);

      expect(session.account.hasLogin, isTrue);
      expect(session.account.status, AuthStatus.unverified);
      expect(session.cookieStore.credentials.uid, 'u-b');
      expect(storage.values[_pendingKey], isNull);
    });

    test('L. 退出记录删不掉时新登录写 active：重启仍采用新账号', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_pendingKey);
      await first.account.signOut();
      expect(storage.values[_pendingKey], 'pending');
      expect(storage.values[_manualKey], isNull);

      // 登录时仍删不掉旧标记，但可以把它改写成 active。
      await first.account.importLoginCookie(_bCookie);
      expect(storage.values[_pendingKey], 'active');
      expect(storage.values[_manualKey], contains('pacm-b'));

      storage.failDeleteKeys.clear();
      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isTrue);
      expect(reopened.cookieStore.credentials.uid, 'u-b');
      expect(storage.values[_pendingKey], isNull);
    });

    test('M. 退出标记既删不掉也写不进时，启动保守拒绝采用新 Cookie', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      storage.failDeleteKeys.add(_pendingKey);
      await first.account.signOut();
      expect(storage.values[_pendingKey], 'pending');

      // 新凭据写得进去，但旧退出标记既删不掉也改不成 active。
      storage.failWriteKeys.add(_pendingKey);
      await first.account.importLoginCookie(_bCookie);
      expect(storage.values[_pendingKey], 'pending');
      expect(storage.values[_manualKey], contains('pacm-b'));

      // 无法确认新登录已经接管时，启动宁可拒绝采用，也不冒险恢复旧账号。
      final blocked = await _open(storage);
      expect(blocked.account.hasLogin, isFalse);
      expect(blocked.account.status, AuthStatus.none);
      expect(blocked.account.storageWarning, isNotNull);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], 'pending');

      storage.failDeleteKeys.clear();
      storage.failWriteKeys.clear();
      final cleaned = await _open(storage);
      expect(cleaned.account.hasLogin, isFalse);
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_pendingKey], isNull);
    });

    test('N. 已有一条普通存储警告时，退出最严重的失败提示仍要覆盖显示', () async {
      final storage = FakeSecureCookieStorage();
      final first = await signedIn(storage);

      // 先制造一条普通警告，同时保留磁盘上的旧账号 A。
      storage.failWriteKeys.add(_manualKey);
      await first.account.importLoginCookie(_bCookie);
      expect(first.account.storageWarning, isNotNull);
      expect(first.account.storageWarning, isNot(contains('重启后可能恢复旧账号')));
      expect(storage.values[_manualKey], contains('pacm-a'));

      // 退出时标记写不进、旧 Cookie 也删不掉：这是最需要如实告知的情形。
      storage.failWriteKeys.add(_pendingKey);
      storage.failDeleteKeys.add(_manualKey);
      await first.account.signOut();

      expect(first.account.hasLogin, isFalse);
      expect(first.account.storageWarning, contains('重启后可能恢复旧账号'));

      final reopened = await _open(storage);
      expect(reopened.account.hasLogin, isTrue);
      expect(reopened.cookieStore.credentials.uid, 'u-a');
    });
  });
}
