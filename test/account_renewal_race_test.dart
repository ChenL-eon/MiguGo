import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

/// 可以在指定写入/删除上挂起的安全存储，用来把异步窗口撑开。
class _GatedSecureStorage extends FakeSecureCookieStorage {
  Completer<void>? writeGate;
  String? writeGateMarker;
  Completer<void>? deleteGate;
  String? deleteGateKey;

  @override
  Future<void> write(String key, String value) async {
    final gate = writeGate;
    if (gate != null && writeGateMarker != null && value.contains(writeGateMarker!)) {
      writeGate = null;
      await gate.future;
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    final gate = deleteGate;
    if (gate != null && deleteGateKey == key) {
      deleteGate = null;
      await gate.future;
    }
    await super.delete(key);
  }
}

/// 续期请求由测试手动放行；登录仍走写死的通行证桩。
class _GatedPassportApi extends MiguPassportApi {
  _GatedPassportApi(Dio dio) : super(dio: dio);

  final List<Completer<MiguLoginSession>> renewals = [];

  @override
  Future<MiguLoginSession> renewSession(String ticket) {
    final gate = Completer<MiguLoginSession>();
    renewals.add(gate);
    return gate.future;
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
    this.ledger,
    this.counters,
  );

  final _GatedSecureStorage storage;
  final MiguCookieStore cookieStore;
  final _GatedPassportApi passport;
  final AccountProvider account;
  final SessionRejectLedger ledger;
  final _Counters counters;

  static Future<_Harness> create() async {
    final storage = _GatedSecureStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final passport = _GatedPassportApi(dioWith(PassportStubAdapter()));
    final (ledger, _) = testLedger();
    final counters = _Counters();
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
    await account.signInWithSmsCode(phone: '13800000000', code: '248157');
    return _Harness._(storage, cookieStore, passport, account, ledger, counters);
  }

  /// 用调试入口发起一次换票；它会停在网络闸门上。
  ///
  /// 自动路径已经不再发这个请求（票据首次换票即被消耗，见 `markSessionRevoked`），
  /// 但这些异步窗口对唯一还在用它的入口同样成立。
  void startRenewal() {
    expect(account.debugRenewNow(), '已发起一次换票');
    expect(passport.renewals, hasLength(1));
  }

  void completeRenewal(String pacmtoken) {
    passport.renewals.last.complete(
      MiguLoginSession(cookies: {'pacmtoken': pacmtoken}),
    );
  }

  Future<String?> persistedPacmtoken() async {
    final restored = MiguCookieStore(secureStorage: storage);
    await restored.init();
    return restored.credentials.pacmtoken;
  }

  Future<String?> persistedUid() async {
    final restored = MiguCookieStore(secureStorage: storage);
    await restored.init();
    return restored.credentials.uid;
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('续期与换号竞态', () {
    test('续期挂起期间完成官方网页登录，旧续期返回后凭据仍属于新账号', () async {
      final h = await _Harness.create();
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      h.startRenewal();

      await h.account.importLoginCookie(
        'uid=u-new; pacmtoken=pacm-new; mg_auth_sid=s-new',
      );
      h.completeRenewal('pacm-old-renewed');
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');
      expect(h.cookieStore.credentials.uid, 'u-new');
      expect(h.cookieStore.loginSnapshot['mg_auth_sid'], 's-new');
      expect(h.account.status, AuthStatus.unverified);
      expect(h.account.hasLogin, isTrue);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      expect(h.counters.established, 2); // 原生登录 + 官方页面登录
      expect(h.counters.lost, 0);

      expect(await h.persistedPacmtoken(), 'pacm-new');
      expect(await h.persistedUid(), 'u-new');
      final stored = await AuthSessionStore(storage: h.storage).read();
      expect(stored.status, AuthStatus.unverified);
    });

    test('旧续期在新账号 Cookie 写入之前返回，不碰新会话', () async {
      final h = await _Harness.create();
      final deleteGate = Completer<void>();
      h.storage
        ..deleteGate = deleteGate
        ..deleteGateKey = PassportTicketStore.defaultKey;
      h.startRenewal();

      final import = h.account.importLoginCookie(
        'uid=u-new; pacmtoken=pacm-new; mg_auth_sid=s-new',
      );
      await _flush();

      // 导入停在删旧票据这一步，新 Cookie 还没开始写。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(h.account.status, AuthStatus.verified);

      h.completeRenewal('pacm-old-renewed');
      await _flush();

      // 旧续期已经返回，但没有把旧账号的值写进来。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 1);

      h.storage.deleteGate = null;
      deleteGate.complete();
      await import;
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');
      expect(h.account.status, AuthStatus.unverified);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      expect(h.counters.established, 2);
      expect(await h.persistedPacmtoken(), 'pacm-new');
    });

    test('旧续期在新账号 Cookie 写入期间返回，最终仍落新账号凭据', () async {
      final h = await _Harness.create();
      h.startRenewal();
      final writeGate = Completer<void>();
      h.storage
        ..writeGate = writeGate
        ..writeGateMarker = 'pacm-new';

      final import = h.account.importLoginCookie(
        'uid=u-new; pacmtoken=pacm-new; mg_auth_sid=s-new',
      );
      await _flush();

      // 内存里已换成新账号，安全存储的写入还挂着。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');

      h.completeRenewal('pacm-old-renewed');
      await _flush();

      // 旧续期在写入窗口内返回，不能把旧 pacmtoken 写回去。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');
      expect(h.cookieStore.credentials.uid, 'u-new');

      h.storage.writeGate = null;
      writeGate.complete();
      await import;
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');
      expect(h.cookieStore.credentials.uid, 'u-new');
      expect(h.account.status, AuthStatus.unverified);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      expect(h.counters.established, 2);
      expect(await h.persistedPacmtoken(), 'pacm-new');
      expect(await h.persistedUid(), 'u-new');
      final stored = await AuthSessionStore(storage: h.storage).read();
      expect(stored.status, AuthStatus.unverified);
    });

    test('续期挂起期间退出登录，旧续期返回后不能恢复会话', () async {
      final h = await _Harness.create();
      h.startRenewal();

      await h.account.signOut();
      h.completeRenewal('pacm-old-renewed');
      await _flush();

      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      expect(h.counters.established, 1);
      expect(h.counters.lost, 1);
      expect(await h.persistedPacmtoken(), isNull);
      final stored = await AuthSessionStore(storage: h.storage).read();
      expect(stored.status, AuthStatus.none);
    });

    test('续期已通过校验、落盘途中退出，不再把会话恢复成已验证', () async {
      final h = await _Harness.create();
      h.startRenewal();
      final writeGate = Completer<void>();
      h.storage
        ..writeGate = writeGate
        ..writeGateMarker = 'pacm-old-renewed';

      h.completeRenewal('pacm-old-renewed');
      await _flush();

      // 续期已经把旧值放进内存，正卡在安全存储写入上。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-old-renewed');

      final signOut = h.account.signOut();
      await _flush();
      expect(h.account.hasLogin, isFalse);

      h.storage.writeGate = null;
      writeGate.complete();
      await signOut;
      await _flush();

      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      // 退出之后不能因为旧续期收尾而重新启动保活。
      expect(h.counters.established, 1);
      expect(h.counters.lost, 1);
      expect(await h.persistedPacmtoken(), isNull);
      final stored = await AuthSessionStore(storage: h.storage).read();
      expect(stored.status, AuthStatus.none);
    });

    test('旧续期在新账号登录后才失败，不给新账号记一次失效', () async {
      final h = await _Harness.create();
      h.startRenewal();

      await h.account.importLoginCookie(
        'uid=u-new; pacmtoken=pacm-new; mg_auth_sid=s-new',
      );
      h.passport.renewals.last.completeError(const MiguLoginException('续期请求失败'));
      await _flush();

      expect(h.account.hasLogin, isTrue);
      expect(h.account.status, AuthStatus.unverified);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-new');
      expect(h.ledger.strikes, 0);
      expect(h.counters.lost, 0);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
    });

    test('续期已通过校验、状态落盘途中退出，不再重启保活', () async {
      final h = await _Harness.create();
      h.startRenewal();
      final writeGate = Completer<void>();
      h.storage
        ..writeGate = writeGate
        ..writeGateMarker = '"status":"verified"';

      h.completeRenewal('pacm-old-renewed');
      await _flush();

      // Cookie 已经写好，续期正卡在把「已验证」写进安全存储上。
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-old-renewed');

      final signOut = h.account.signOut();
      await _flush();
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);

      h.storage.writeGate = null;
      writeGate.complete();
      await signOut;
      await _flush();

      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
      // 退出之后不能因为旧续期收尾而重新启动保活。
      expect(h.counters.established, 1);
      expect(h.counters.lost, 1);
      expect(await h.persistedPacmtoken(), isNull);
    });

    test('旧账号续期挂起时不占用新账号的续期名额', () async {
      final h = await _Harness.create();
      h.startRenewal();

      await h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 2);

      // 新账号自己的换票必须能发出去，不能被旧账号那次占用挡住。
      expect(h.account.debugRenewNow(), '已发起一次换票');
      expect(h.passport.renewals, hasLength(2));

      // 同一会话里仍只允许一次在飞。
      expect(h.account.debugRenewNow(), '已有一次续期在飞，这次没叠加');
      expect(h.passport.renewals, hasLength(2));

      // 旧账号的续期回来，只能结束它自己，不能碰新账号的在飞状态。
      h.passport.renewals[0].complete(
        MiguLoginSession(cookies: {'pacmtoken': 'pacm-old-renewed'}),
      );
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 2);

      // 旧那次结束也不替新账号补发：还在飞的就是它自己那一次。
      expect(h.account.debugRenewNow(), '已有一次续期在飞，这次没叠加');
      expect(h.passport.renewals, hasLength(2));

      h.completeRenewal('pacm-renewed-b');
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-renewed-b');
      expect(h.account.status, AuthStatus.verified);
      expect(h.counters.established, 3);
      expect(h.counters.lost, 0);
      expect(await PassportTicketStore(storage: h.storage).read(), 'STnidStubToken');
      expect(await h.persistedPacmtoken(), 'pacm-renewed-b');
    });

    test('同一会话内续期成功仍然生效', () async {
      final h = await _Harness.create();
      h.startRenewal();

      h.completeRenewal('pacm-renewed');
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-renewed');
      expect(h.account.status, AuthStatus.verified);
      expect(h.account.hasLogin, isTrue);
      expect(h.ledger.strikes, 0);
      expect(h.counters.established, 2);
      expect(h.counters.lost, 0);
      expect(await PassportTicketStore(storage: h.storage).read(), 'STnidStubToken');
      expect(await h.persistedPacmtoken(), 'pacm-renewed');
    });
  });
}
