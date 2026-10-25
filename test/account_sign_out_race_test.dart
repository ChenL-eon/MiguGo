import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/session_keep_alive.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

const String _manualKey = 'migu_manual_cookies_v2';
const String _jarKey = 'migu_cookie_jar_v2';
const String _ticketKey = PassportTicketStore.defaultKey;
const String _authKey = AuthSessionStore.defaultKey;

const String _aCookie = 'uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a';
const String _bCookie = 'uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b';

/// 把指定的第一次安全存储删除挂起，模拟“退出已经发出删除，但存储还没完成”。
class _GatedStorage extends FakeSecureCookieStorage {
  Completer<void>? _deleteGate;
  String? _deleteGateKey;
  int gatedDeletes = 0;

  Completer<void> gateNextDelete(String key) {
    _deleteGateKey = key;
    return _deleteGate = Completer<void>();
  }

  @override
  Future<void> delete(String key) async {
    final gate = _deleteGate;
    if (gate != null && key == _deleteGateKey) {
      _deleteGate = null;
      _deleteGateKey = null;
      gatedDeletes++;
      await gate.future;
    }
    await super.delete(key);
  }
}

class _Harness {
  _Harness._(
    this.storage,
    this.cookieStore,
    this.account,
    this.ledger,
    this.keepAlive,
    this.events,
  );

  final _GatedStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;
  final SessionRejectLedger ledger;
  final SessionKeepAlive keepAlive;
  final List<String> events;

  int get lostCount => events.where((event) => event == 'lost').length;

  static Future<_Harness> create() async {
    final storage = _GatedStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    final events = <String>[];
    late final SessionKeepAlive keepAlive;
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
      onSessionEstablished: () {
        events.add('established');
        keepAlive.restart();
      },
      onSessionLost: () {
        events.add('lost');
        keepAlive.stop();
      },
    );
    // 测试期间不真的探测，只看保活是否仍挂在当前会话上。
    keepAlive = SessionKeepAlive(
      probe: () async => SessionProbe.unknown,
      sessionEpoch: () => account.credentialEpoch,
      minInterval: const Duration(hours: 4),
      maxInterval: const Duration(hours: 4),
    );
    await account.initialize();
    return _Harness._(storage, cookieStore, account, ledger, keepAlive, events);
  }
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

Map<String, dynamic>? _storedCookies(_Harness h) {
  final raw = h.storage.values[_manualKey];
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

Map<String, dynamic>? _storedAuth(_Harness h) {
  final raw = h.storage.values[_authKey];
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

void _expectLoggedInAsB(_Harness h) {
  expect(h.account.hasLogin, isTrue);
  expect(h.account.status, AuthStatus.unverified);
  expect(h.cookieStore.credentials.uid, 'u-b');
  expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');

  final stored = _storedCookies(h);
  expect(stored, isNotNull);
  expect(stored?['uid'], 'u-b');
  expect(stored?['pacmtoken'], 'pacm-b');
  expect(stored?['mg_auth_sid'], 's-b');

  final auth = _storedAuth(h);
  expect(auth, isNotNull, reason: 'B 登录后的认证状态不应被旧退出删掉');
  expect(auth?['status'], 'unverified');
}

void _expectCleanSignedOut(_Harness h) {
  expect(h.account.hasLogin, isFalse);
  expect(h.account.status, AuthStatus.none);
  expect(h.cookieStore.credentials.uid, isNull);
  expect(h.cookieStore.credentials.pacmtoken, isNull);
  expect(h.storage.values[_manualKey], isNull);
  expect(h.storage.values[_jarKey], isNull);
  expect(h.storage.values[_authKey], isNull);
  expect(h.storage.values[_ticketKey], isNull);
  expect(h.keepAlive.isArmed, isFalse);
}

Future<(MiguCookieStore, AccountProvider)> _reopen(_Harness h) async {
  final cookieStore = MiguCookieStore(secureStorage: h.storage);
  await cookieStore.init();
  final account = AccountProvider(
    cookieStore: cookieStore,
    authSessionStore: AuthSessionStore(storage: h.storage),
    passportTicketStore: PassportTicketStore(storage: h.storage),
    ledger: h.ledger,
  );
  await account.initialize();
  return (cookieStore, account);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('退出登录与并发登录竞态（R4）', () {
    test('退出卡在 Cookie 删除、B 排队等写入时，放行后 B 的凭据与状态保留', () async {
      final h = await _Harness.create();
      addTearDown(h.keepAlive.dispose);
      await h.account.importLoginCookie(_aCookie);
      expect(h.events, ['established']);
      expect(h.keepAlive.isArmed, isTrue);

      final gate = h.storage.gateNextDelete(_manualKey);
      final signOutDone = h.account.signOut();
      await _pumpUntil(() => h.storage.gatedDeletes == 1);
      expect(h.account.hasLogin, isFalse);

      var bDone = false;
      final importB = h.account.importLoginCookie(_bCookie);
      unawaited(importB.then((_) => bDone = true));
      await _flush();
      // 退出占着 Cookie 写队列，B 的登录此时不可能已经完成。
      expect(bDone, isFalse);
      expect(h.account.hasLogin, isTrue);

      gate.complete();
      await signOutDone;
      await importB;
      await _flush();

      _expectLoggedInAsB(h);
      expect(h.events, ['established', 'lost', 'established']);
      expect(h.lostCount, 1);
      expect(h.keepAlive.isArmed, isTrue);

      final (reopenedCookies, reopened) = await _reopen(h);
      expect(reopened.hasLogin, isTrue);
      expect(reopened.status, AuthStatus.unverified);
      expect(reopenedCookies.credentials.uid, 'u-b');
      expect(reopenedCookies.credentials.pacmtoken, 'pacm-b');
    });

    test('退出卡在票据删除时 B 排队登录，放行后旧退出不再回调或删 B 的状态', () async {
      final h = await _Harness.create();
      addTearDown(h.keepAlive.dispose);
      await h.account.importLoginCookie(_aCookie);

      final gate = h.storage.gateNextDelete(_ticketKey);
      final signOutDone = h.account.signOut();
      await _pumpUntil(() => h.storage.gatedDeletes == 1);

      var bDone = false;
      final importB = h.account.importLoginCookie(_bCookie);
      unawaited(importB.then((_) => bDone = true));
      await _flush();
      // 票据清理现在与 Cookie 清理一样串行：旧退出还挂在存储删除上时，
      // B 的登录排在它后面，不会抢先完成。
      expect(bDone, isFalse);

      gate.complete();
      await signOutDone;
      await importB;
      await _flush();

      // 一次性列出旧退出可能改坏的四处：回调、保活、内存、认证状态落盘。
      expect(
        (
          events: h.events.join('|'),
          lost: h.lostCount,
          armed: h.keepAlive.isArmed,
          auth: _storedAuth(h)?['status'],
        ),
        (
          events: 'established|lost|established',
          lost: 1,
          armed: true,
          auth: 'unverified',
        ),
      );
      _expectLoggedInAsB(h);
      expect(h.keepAlive.isArmed, isTrue);
      expect(h.storage.values[_ticketKey], isNull);

      final (reopenedCookies, reopened) = await _reopen(h);
      expect(reopened.hasLogin, isTrue);
      expect(reopened.status, AuthStatus.unverified);
      expect(reopenedCookies.credentials.uid, 'u-b');
      expect(reopenedCookies.credentials.pacmtoken, 'pacm-b');
    });

    test('正常退出在第一个 await 前就复位状态、保活与回调', () async {
      final h = await _Harness.create();
      addTearDown(h.keepAlive.dispose);
      await h.account.importLoginCookie(_aCookie);

      final signOutDone = h.account.signOut();
      // 还没等任何存储操作完成，界面与会话就应该已经按“未登录”处理。
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.keepAlive.isArmed, isFalse);
      expect(h.events, ['established', 'lost']);

      await signOutDone;
      await _flush();

      _expectCleanSignedOut(h);
      expect(h.events, ['established', 'lost']);
      expect(h.lostCount, 1);

      final (reopenedCookies, reopened) = await _reopen(h);
      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
      expect(reopenedCookies.credentials.uid, isNull);
    });

    test('退出期间新登录失败，旧会话仍被清干净', () async {
      final h = await _Harness.create();
      addTearDown(h.keepAlive.dispose);
      await h.account.importLoginCookie(_aCookie);

      final gate = h.storage.gateNextDelete(_ticketKey);
      final signOutDone = h.account.signOut();
      await _pumpUntil(() => h.storage.gatedDeletes == 1);

      var importFailed = false;
      final badImport = h.account.importLoginCookie('not-a-cookie');
      unawaited(
        badImport.then<void>((_) {}, onError: (Object _) => importFailed = true),
      );
      await _flush();
      // 导入要先排到旧退出的票据删除之后，此时还没有机会解析出格式错误。
      expect(importFailed, isFalse);

      gate.complete();
      await signOutDone;
      await expectLater(badImport, throwsFormatException);
      await _flush();

      _expectCleanSignedOut(h);
      expect(h.events, ['established', 'lost']);
      expect(h.lostCount, 1);

      final (reopenedCookies, reopened) = await _reopen(h);
      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
      expect(reopenedCookies.credentials.uid, isNull);
    });

    test('连续两次退出不会留下中间态', () async {
      final h = await _Harness.create();
      addTearDown(h.keepAlive.dispose);
      await h.account.importLoginCookie(_aCookie);

      final first = h.account.signOut();
      final second = h.account.signOut();
      await first;
      await second;
      await _flush();

      _expectCleanSignedOut(h);
      expect(h.events, ['established', 'lost', 'lost']);
      expect(h.lostCount, 2);

      final (reopenedCookies, reopened) = await _reopen(h);
      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
      expect(reopenedCookies.credentials.uid, isNull);
    });
  });
}
