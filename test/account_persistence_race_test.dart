import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

/// 可以卡住某一次认证状态写入的存储：写入开始时停下，直到测试放行。
class _GatedAuthStorage extends FakeSecureCookieStorage {
  String? _gateStatus;
  Completer<void>? _gate;
  int gatedStarts = 0;

  void armAuthGate(AuthStatus status) {
    _gateStatus = status.name;
    _gate = null;
    gatedStarts = 0;
  }

  bool get gateHeld => _gate != null && !_gate!.isCompleted;

  void releaseGate() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> write(String key, String value) async {
    if (key == AuthSessionStore.defaultKey &&
        _gateStatus != null &&
        value.contains('"status":"$_gateStatus"')) {
      _gateStatus = null;
      final gate = Completer<void>();
      _gate = gate;
      gatedStarts++;
      await gate.future;
    }
    await super.write(key, value);
  }
}

class _Harness {
  _Harness._(this.storage, this.cookieStore, this.account);

  final _GatedAuthStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;

  static Future<_Harness> create() async {
    final storage = _GatedAuthStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
    );
    await account.initialize();
    return _Harness._(storage, cookieStore, account);
  }

  /// 模拟应用重启：同一份存储，全新的 Cookie 仓库与账号对象。
  Future<AccountProvider> reopen() async {
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
    );
    await account.initialize();
    return account;
  }

  Future<AuthSession> storedSession() => AuthSessionStore(storage: storage).read();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('认证状态持久化与退出/换号竞态', () {
    test('退出时旧状态写入仍在途，完成后不得把已退出的状态写回', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');

      h.storage.armAuthGate(AuthStatus.verified);
      h.account.markVerified();
      await _pumpUntil(() => h.storage.gatedStarts == 1);

      final signOut = h.account.signOut();
      await _flush();
      h.storage.releaseGate();
      await signOut;
      await _flush();

      expect(h.account.status, AuthStatus.none);
      expect(h.account.hasLogin, isFalse);
      expect((await h.storedSession()).status, AuthStatus.none);

      final reopened = await h.reopen();
      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
    });

    test('旧账号状态写入在切到新账号后才完成，不得覆盖新账号的状态', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');

      h.storage.armAuthGate(AuthStatus.verified);
      h.account.markVerified();
      await _pumpUntil(() => h.storage.gatedStarts == 1);

      final signOut = h.account.signOut();
      final importing = h.account.importLoginCookie(
        'uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b',
      );
      await _pumpUntil(
        () => h.account.hasLogin && h.cookieStore.credentials.pacmtoken == 'pacm-b',
      );

      h.storage.releaseGate();
      await signOut;
      await importing;
      await _flush();

      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.account.status, AuthStatus.unverified);
      expect((await h.storedSession()).status, AuthStatus.unverified);
    });

    test('同一会话的多次状态写入乱序完成时，最终以最后一次状态为准', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');

      h.storage.armAuthGate(AuthStatus.verified);
      h.account.markVerified();
      await _pumpUntil(() => h.storage.gatedStarts == 1);

      h.account.markRejected();
      await _flush();
      h.storage.releaseGate();
      await _flush();

      expect(h.account.status, AuthStatus.rejected);
      expect((await h.storedSession()).status, AuthStatus.rejected);
    });

    test('退出后重新初始化不会从旧元数据恢复登录态', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      expect((await h.storedSession()).status, AuthStatus.unverified);

      await h.account.signOut();
      expect((await h.storedSession()).status, AuthStatus.none);

      final reopened = await h.reopen();
      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
    });

    test('正常登录落盘后重新初始化能恢复为已保存凭据', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');

      final stored = await h.storedSession();
      expect(stored.status, AuthStatus.unverified);
      expect(stored.importedAt, isNotNull);

      final reopened = await h.reopen();
      expect(reopened.hasLogin, isTrue);
      expect(reopened.status, AuthStatus.unverified);
      expect(reopened.importedAt, isNotNull);
    });
  });
}
