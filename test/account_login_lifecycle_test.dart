import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

/// 登录请求由测试手动放行，能精确控制“网络返回”发生在退出/换号之前还是之后。
class _GatedPassportApi extends MiguPassportApi {
  _GatedPassportApi() : super(dio: dioWith(PassportStubAdapter()));

  final List<Completer<MiguLoginSession>> logins = [];

  @override
  Future<MiguLoginSession> loginWithSmsCode(
    String phone,
    String code, {
    String captcha = '',
  }) {
    final gate = Completer<MiguLoginSession>();
    logins.add(gate);
    return gate.future;
  }
}

/// 把官方导入卡在删除旧票据这一步，用来验证“导入还在路上时开始另一次登录”。
///
/// 也可以把某一次 Cookie 落盘挂起，用来撑开“内存已换、磁盘还没写”的窗口。
class _GatedStorage extends FakeSecureCookieStorage {
  Completer<void>? deleteGate;
  String? deleteGateKey;
  Completer<void>? writeGate;
  String? writeGateKey;

  @override
  Future<void> delete(String key) async {
    final gate = deleteGate;
    if (gate != null && deleteGateKey == key) {
      deleteGate = null;
      await gate.future;
    }
    await super.delete(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final gate = writeGate;
    if (gate != null && writeGateKey == key) {
      writeGate = null;
      writeGateKey = null;
      await gate.future;
    }
    await super.write(key, value);
  }
}

class _Counters {
  int established = 0;
  int lost = 0;
}

class _Harness {
  _Harness._(
    this.storage,
    this.cookieStore,
    this.passport,
    this.account,
    this.counters,
  );

  final _GatedStorage storage;
  final MiguCookieStore cookieStore;
  final _GatedPassportApi passport;
  final AccountProvider account;
  final _Counters counters;

  static Future<_Harness> create() async {
    final storage = _GatedStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final passport = _GatedPassportApi();
    final counters = _Counters();
    final (ledger, _) = testLedger();
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: passport,
      ledger: ledger,
      onSessionEstablished: () => counters.established++,
      onSessionLost: () => counters.lost++,
    );
    await account.initialize();
    return _Harness._(storage, cookieStore, passport, account, counters);
  }

  Future<AuthSession> storedSession() => AuthSessionStore(storage: storage).read();

  Future<String?> storedTicket() => PassportTicketStore(storage: storage).read();
}

MiguLoginSession _login(String tag) => MiguLoginSession(
  cookies: {'pacmtoken': 'pacm-$tag', 'uid': 'u-$tag'},
  maskedPhone: '138****000$tag',
  token: 'ticket-$tag',
);

const String _manualCookiesKey = 'migu_manual_cookies_v2';

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

/// 按重启路径重新读取安全存储；调用前应先取走需要断言的原始磁盘值，
/// 因为 initialize 会在没有 Cookie 时顺手清掉孤立票据。
Future<(MiguCookieStore, AccountProvider)> _reopen(_Harness h) async {
  final cookieStore = MiguCookieStore(secureStorage: h.storage);
  await cookieStore.init();
  final (ledger, _) = testLedger();
  final account = AccountProvider(
    cookieStore: cookieStore,
    authSessionStore: AuthSessionStore(storage: h.storage),
    passportTicketStore: PassportTicketStore(storage: h.storage),
    passportApi: _GatedPassportApi(),
    ledger: ledger,
  );
  await account.initialize();
  return (cookieStore, account);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('登录请求生命周期与退出/换号竞态', () {
    test('登录请求挂起期间退出，随后旧请求成功也不重建会话', () async {
      final h = await _Harness.create();
      final login = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.passport.logins, hasLength(1));

      await h.account.signOut();
      h.passport.logins.single.complete(_login('a'));
      final result = await login;
      await _flush();

      expect(result, isNull);
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(h.cookieStore.credentials.uid, isNull);
      expect(await h.storedTicket(), isNull);
      expect((await h.storedSession()).status, AuthStatus.none);
      expect(h.counters.established, 0);
      expect(h.counters.lost, 1);
    });

    test('A 挂起时开始登录 B，A 先返回也不得建立会话', () async {
      final h = await _Harness.create();
      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.passport.logins, hasLength(2));

      h.passport.logins[0].complete(_login('a'));
      final aResult = await a;
      await _flush();

      expect(aResult, isNull);
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(h.cookieStore.credentials.uid, isNull);
      expect(await h.storedTicket(), isNull);
      expect((await h.storedSession()).status, AuthStatus.none);
      expect(h.counters.established, 0);

      h.passport.logins[1].complete(_login('b'));
      final bResult = await b;
      await _flush();

      expect(bResult, '138****000b');
      expect(h.account.status, AuthStatus.verified);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.cookieStore.credentials.uid, 'u-b');
      expect(await h.storedTicket(), 'ticket-b');
      expect((await h.storedSession()).status, AuthStatus.verified);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 0);
    });

    test('B 先建立会话后 A 才成功返回，A 不覆盖 B', () async {
      final h = await _Harness.create();
      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');

      h.passport.logins[1].complete(_login('b'));
      await b;
      await _flush();
      expect(h.counters.established, 1);
      expect(h.account.status, AuthStatus.verified);

      h.passport.logins[0].complete(_login('a'));
      final aResult = await a;
      await _flush();

      expect(aResult, isNull);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.cookieStore.credentials.uid, 'u-b');
      expect(await h.storedTicket(), 'ticket-b');
      expect(h.account.status, AuthStatus.verified);
      expect((await h.storedSession()).status, AuthStatus.verified);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 0);
    });

    test('B 建立后 A 请求失败，不误伤 B 的会话', () async {
      final h = await _Harness.create();
      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');

      h.passport.logins[1].complete(_login('b'));
      await b;
      await _flush();

      h.passport.logins[0].completeError(const MiguLoginException('登录失败'));
      await expectLater(a, throwsA(isA<MiguLoginException>()));
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.cookieStore.credentials.uid, 'u-b');
      expect(await h.storedTicket(), 'ticket-b');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 0);
    });

    test('正常登录仍建立会话、落盘并触发一次建立回调', () async {
      final h = await _Harness.create();
      final login = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      final result = await login;
      await _flush();

      expect(result, '138****000a');
      expect(h.account.hasLogin, isTrue);
      expect(h.account.status, AuthStatus.verified);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-a');
      expect(h.cookieStore.credentials.uid, 'u-a');
      expect(await h.storedTicket(), 'ticket-a');
      expect((await h.storedSession()).status, AuthStatus.verified);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 0);
    });

    test('A 挂起时完成官方导入，A 返回后不覆盖导入结果', () async {
      final h = await _Harness.create();
      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');

      await h.account.importLoginCookie('uid=u-c; pacmtoken=pacm-c; mg_auth_sid=s-c');
      expect(h.counters.established, 1);

      h.passport.logins.single.complete(_login('a'));
      final aResult = await a;
      await _flush();

      expect(aResult, isNull);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-c');
      expect(h.cookieStore.credentials.uid, 'u-c');
      expect(h.cookieStore.loginSnapshot['mg_auth_sid'], 's-c');
      expect(await h.storedTicket(), isNull);
      expect(h.account.status, AuthStatus.unverified);
      expect((await h.storedSession()).status, AuthStatus.unverified);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 0);
    });

    test('官方导入异步写入期间开始登录 B，导入收尾不建立旧会话', () async {
      final h = await _Harness.create();
      final deleteGate = Completer<void>();
      h.storage
        ..deleteGate = deleteGate
        ..deleteGateKey = PassportTicketStore.defaultKey;

      final importing = h.account.importLoginCookie(
        'uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a',
      );
      await _pumpUntil(() => h.storage.deleteGate == null);

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.passport.logins, hasLength(1));

      deleteGate.complete();
      await importing;
      await _flush();

      // B 已经发起，导入的收尾不能再把 A 的凭据和会话建立回调带回来。
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await h.storedTicket(), isNull);
      expect(h.counters.established, 0);

      h.passport.logins.single.complete(_login('b'));
      await b;
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 1);
    });

    test('A 的 Cookie 落盘期间开始登录 B，B 失败后不残留 A 的凭据', () async {
      final h = await _Harness.create();
      final cookieWriteGate = Completer<void>();
      h.storage
        ..writeGate = cookieWriteGate
        ..writeGateKey = _manualCookiesKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      await _pumpUntil(() => h.storage.writeGate == null);

      // A 的凭据已经写进内存，安全存储的写入还停着。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-a');
      expect(h.cookieStore.credentials.uid, 'u-a');
      expect(h.storage.values[_manualCookiesKey], isNull);

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.passport.logins, hasLength(2));

      cookieWriteGate.complete();
      final aResult = await a;
      await _flush();

      // A 已被 B 作废：即使它的 Cookie 写入已经完成，也不能建立会话或恢复保活。
      expect(aResult, isNull);
      expect(h.counters.established, 0);

      h.passport.logins[1].completeError(const MiguLoginException('登录失败'));
      await expectLater(b, throwsA(isA<MiguLoginException>()));
      await _flush();

      // 重启后重新读一遍安全存储，确认 A 的凭据不会被重新采纳。
      final reopenedStore = MiguCookieStore(secureStorage: h.storage);
      await reopenedStore.init();
      final (reopenedLedger, _) = testLedger();
      final reopened = AccountProvider(
        cookieStore: reopenedStore,
        authSessionStore: AuthSessionStore(storage: h.storage),
        passportTicketStore: PassportTicketStore(storage: h.storage),
        passportApi: _GatedPassportApi(),
        ledger: reopenedLedger,
      );
      await reopened.initialize();

      expect(
        (
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          hasLogin: h.account.hasLogin,
          status: h.account.status,
          header: h.cookieStore.cookieHeaderFor(
            Uri.parse('https://music.migu.cn/v3/api/play'),
          ),
          diskCookies: h.storage.values[_manualCookiesKey],
          ticket: await h.storedTicket(),
          storedStatus: (await h.storedSession()).status,
          established: h.counters.established,
          lost: h.counters.lost,
          reopenedPacmtoken: reopenedStore.credentials.pacmtoken,
          reopenedUid: reopenedStore.credentials.uid,
          reopenedHasLogin: reopened.hasLogin,
          reopenedStatus: reopened.status,
        ),
        (
          memoryPacmtoken: null,
          memoryUid: null,
          hasLogin: false,
          status: AuthStatus.none,
          header: null,
          diskCookies: null,
          ticket: null,
          storedStatus: AuthStatus.none,
          established: 0,
          lost: 0,
          reopenedPacmtoken: null,
          reopenedUid: null,
          reopenedHasLogin: false,
          reopenedStatus: AuthStatus.none,
        ),
      );
    });

    test('A 的 Cookie 落盘期间 B 已建立新凭据，A 的收尾不删除 B', () async {
      final h = await _Harness.create();
      final cookieWriteGate = Completer<void>();
      h.storage
        ..writeGate = cookieWriteGate
        ..writeGateKey = _manualCookiesKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      await _pumpUntil(() => h.storage.writeGate == null);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-a');

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins[1].complete(_login('b'));
      // B 的落盘排在 A 那次之后；先确认内存已换成 B，再放行 A。
      await _pumpUntil(() => h.cookieStore.credentials.pacmtoken == 'pacm-b');

      cookieWriteGate.complete();
      final aResult = await a;
      final bResult = await b;
      await _flush();

      expect(
        (
          aResult: aResult,
          bResult: bResult,
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          snapshot: h.cookieStore.loginSnapshot.toString(),
          diskHasB: h.storage.values[_manualCookiesKey]?.contains('"pacm-b"'),
          diskHasA: h.storage.values[_manualCookiesKey]?.contains('"pacm-a"') ?? false,
          ticket: await h.storedTicket(),
          storedStatus: (await h.storedSession()).status,
          status: h.account.status,
          established: h.counters.established,
          lost: h.counters.lost,
        ),
        (
          aResult: null,
          bResult: '138****000b',
          memoryPacmtoken: 'pacm-b',
          memoryUid: 'u-b',
          snapshot: '{pacmtoken: pacm-b, uid: u-b}',
          diskHasB: true,
          diskHasA: false,
          ticket: 'ticket-b',
          storedStatus: AuthStatus.verified,
          status: AuthStatus.verified,
          established: 1,
          lost: 0,
        ),
      );
    });
  });

  group('票据提交阶段被作废（R2）', () {
    test('A 的票据落盘期间 B 作废并失败，不留下 A 的会话、Cookie 或票据', () async {
      final h = await _Harness.create();
      final ticketWriteGate = Completer<void>();
      h.storage
        ..writeGate = ticketWriteGate
        ..writeGateKey = PassportTicketStore.defaultKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      // 等到安全存储真正停在票据写入上，而不是只让 Future 开始跑。
      await _pumpUntil(() => h.storage.writeGate == null);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-a');

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.passport.logins, hasLength(2));

      ticketWriteGate.complete();
      final aResult = await a;
      await _flush();

      h.passport.logins[1].completeError(const MiguLoginException('登录失败'));
      await expectLater(b, throwsA(isA<MiguLoginException>()));
      await _flush();

      final diskCookies = h.storage.values[_manualCookiesKey];
      final diskTicket = h.storage.values[PassportTicketStore.defaultKey];
      final diskStatus = (await h.storedSession()).status;
      final (reopenedCookies, reopened) = await _reopen(h);
      final reopenedTicket = await PassportTicketStore(storage: h.storage).read();

      expect(
        (
          aResult: aResult,
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          header: h.cookieStore.cookieHeaderFor(
            Uri.parse('https://music.migu.cn/v3/api/play'),
          ),
          hasLogin: h.account.hasLogin,
          status: h.account.status,
          diskCookies: diskCookies,
          diskTicket: diskTicket,
          diskStatus: diskStatus,
          established: h.counters.established,
          lost: h.counters.lost,
          reopenedHasLogin: reopened.hasLogin,
          reopenedPacmtoken: reopenedCookies.credentials.pacmtoken,
          reopenedUid: reopenedCookies.credentials.uid,
          reopenedStatus: reopened.status,
          reopenedTicket: reopenedTicket,
        ),
        (
          aResult: null,
          memoryPacmtoken: null,
          memoryUid: null,
          header: null,
          hasLogin: false,
          status: AuthStatus.none,
          diskCookies: null,
          diskTicket: null,
          diskStatus: AuthStatus.none,
          established: 0,
          lost: 0,
          reopenedHasLogin: false,
          reopenedPacmtoken: null,
          reopenedUid: null,
          reopenedStatus: AuthStatus.none,
          reopenedTicket: null,
        ),
      );
    });
  });

  group('票据写入与删除的顺序（R3）', () {
    test('A 的票据落盘期间退出，退出完成后存储里没有 A 的票据', () async {
      final h = await _Harness.create();
      final ticketWriteGate = Completer<void>();
      h.storage
        ..writeGate = ticketWriteGate
        ..writeGateKey = PassportTicketStore.defaultKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      await _pumpUntil(() => h.storage.writeGate == null);

      final signOut = h.account.signOut();
      await _flush();

      ticketWriteGate.complete();
      final aResult = await a;
      await signOut;
      await _flush();

      final diskCookies = h.storage.values[_manualCookiesKey];
      final diskTicket = h.storage.values[PassportTicketStore.defaultKey];
      final diskAuth = h.storage.values[AuthSessionStore.defaultKey];
      final (reopenedCookies, reopened) = await _reopen(h);

      expect(
        (
          aResult: aResult,
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          header: h.cookieStore.cookieHeaderFor(
            Uri.parse('https://music.migu.cn/v3/api/play'),
          ),
          hasLogin: h.account.hasLogin,
          status: h.account.status,
          diskCookies: diskCookies,
          diskTicket: diskTicket,
          diskAuth: diskAuth,
          established: h.counters.established,
          lost: h.counters.lost,
          reopenedHasLogin: reopened.hasLogin,
          reopenedPacmtoken: reopenedCookies.credentials.pacmtoken,
          reopenedStatus: reopened.status,
        ),
        (
          aResult: null,
          memoryPacmtoken: null,
          memoryUid: null,
          header: null,
          hasLogin: false,
          status: AuthStatus.none,
          diskCookies: null,
          diskTicket: null,
          diskAuth: null,
          established: 0,
          lost: 1,
          reopenedHasLogin: false,
          reopenedPacmtoken: null,
          reopenedStatus: AuthStatus.none,
        ),
      );
    });

    test('A 的票据落盘期间 B 登录成功，最终保留 B 的票据', () async {
      final h = await _Harness.create();
      final ticketWriteGate = Completer<void>();
      h.storage
        ..writeGate = ticketWriteGate
        ..writeGateKey = PassportTicketStore.defaultKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      await _pumpUntil(() => h.storage.writeGate == null);

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins[1].complete(_login('b'));
      await _flush();

      ticketWriteGate.complete();
      final aResult = await a;
      final bResult = await b;
      await _flush();

      final diskCookies = h.storage.values[_manualCookiesKey];
      final diskTicket = h.storage.values[PassportTicketStore.defaultKey];
      final diskStatus = (await h.storedSession()).status;
      final (reopenedCookies, reopened) = await _reopen(h);
      final reopenedTicket = await PassportTicketStore(storage: h.storage).read();

      expect(
        (
          aResult: aResult,
          bResult: bResult,
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          diskHasB: diskCookies?.contains('"pacm-b"'),
          diskHasA: diskCookies?.contains('"pacm-a"') ?? false,
          diskTicket: diskTicket,
          diskStatus: diskStatus,
          status: h.account.status,
          established: h.counters.established,
          lost: h.counters.lost,
          reopenedPacmtoken: reopenedCookies.credentials.pacmtoken,
          reopenedUid: reopenedCookies.credentials.uid,
          reopenedStatus: reopened.status,
          reopenedTicket: reopenedTicket,
        ),
        (
          aResult: null,
          bResult: '138****000b',
          memoryPacmtoken: 'pacm-b',
          memoryUid: 'u-b',
          diskHasB: true,
          diskHasA: false,
          diskTicket: 'ticket-b',
          diskStatus: AuthStatus.verified,
          status: AuthStatus.verified,
          established: 1,
          lost: 0,
          reopenedPacmtoken: 'pacm-b',
          reopenedUid: 'u-b',
          reopenedStatus: AuthStatus.unverified,
          reopenedTicket: 'ticket-b',
        ),
      );
    });

    test('A 的票据落盘期间 B 登录失败，A 的票据与 Cookie 都不能留下', () async {
      final h = await _Harness.create();
      final ticketWriteGate = Completer<void>();
      h.storage
        ..writeGate = ticketWriteGate
        ..writeGateKey = PassportTicketStore.defaultKey;

      final a = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins.single.complete(_login('a'));
      await _pumpUntil(() => h.storage.writeGate == null);

      final b = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      h.passport.logins[1].completeError(const MiguLoginException('登录失败'));
      await expectLater(b, throwsA(isA<MiguLoginException>()));

      ticketWriteGate.complete();
      final aResult = await a;
      await _flush();

      final diskCookies = h.storage.values[_manualCookiesKey];
      final diskTicket = h.storage.values[PassportTicketStore.defaultKey];
      final diskStatus = (await h.storedSession()).status;
      final (reopenedCookies, reopened) = await _reopen(h);
      final reopenedTicket = await PassportTicketStore(storage: h.storage).read();

      expect(
        (
          aResult: aResult,
          memoryPacmtoken: h.cookieStore.credentials.pacmtoken,
          memoryUid: h.cookieStore.credentials.uid,
          header: h.cookieStore.cookieHeaderFor(
            Uri.parse('https://music.migu.cn/v3/api/play'),
          ),
          hasLogin: h.account.hasLogin,
          status: h.account.status,
          diskCookies: diskCookies,
          diskTicket: diskTicket,
          diskStatus: diskStatus,
          established: h.counters.established,
          lost: h.counters.lost,
          reopenedHasLogin: reopened.hasLogin,
          reopenedPacmtoken: reopenedCookies.credentials.pacmtoken,
          reopenedStatus: reopened.status,
          reopenedTicket: reopenedTicket,
        ),
        (
          aResult: null,
          memoryPacmtoken: null,
          memoryUid: null,
          header: null,
          hasLogin: false,
          status: AuthStatus.none,
          diskCookies: null,
          diskTicket: null,
          diskStatus: AuthStatus.none,
          established: 0,
          lost: 0,
          reopenedHasLogin: false,
          reopenedPacmtoken: null,
          reopenedStatus: AuthStatus.none,
          reopenedTicket: null,
        ),
      );
    });
  });
}
