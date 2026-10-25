import 'dart:async';

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

/// 每次探测都挂起，由测试决定它在换号前还是换号后才返回。
class _Harness {
  _Harness._(
    this.storage,
    this.cookieStore,
    this.account,
    this.keepAlive,
    this.ledger,
    this.clock,
  );

  final FakeSecureCookieStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;
  final SessionKeepAlive keepAlive;
  final SessionRejectLedger ledger;
  final StepClock clock;

  final List<Completer<SessionProbe>> probes = [];
  int established = 0;
  int lost = 0;
  int autoSignOut = 0;

  static Future<_Harness> create() async {
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, clock) = testLedger();
    late final SessionKeepAlive keepAlive;
    late final _Harness harness;
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
      onSessionEstablished: () {
        harness.established++;
        keepAlive.restart();
      },
      onSessionLost: () {
        harness.lost++;
        keepAlive.stop();
      },
      onAutoSignOut: () async {
        harness.autoSignOut++;
      },
    );
    keepAlive = SessionKeepAlive(
      probe: () {
        final gate = Completer<SessionProbe>();
        harness.probes.add(gate);
        return gate.future;
      },
      onAlive: account.markVerified,
      onRevoked: account.markSessionRevoked,
      sessionEpoch: () => account.credentialEpoch,
      minInterval: Duration.zero,
      maxInterval: Duration.zero,
    );
    harness = _Harness._(storage, cookieStore, account, keepAlive, ledger, clock);
    await account.initialize();
    return harness;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('前台保活探测与换号/退出竞态', () {
    test('A 的探测在切到 B 之后返回失效，不把 B 标成失效', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      await _pumpUntil(() => h.probes.isNotEmpty);

      await h.account.signOut();
      await h.account.importLoginCookie('uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b');
      expect(h.account.status, AuthStatus.unverified);

      h.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(h.account.status, AuthStatus.unverified);
      expect(h.account.hasLogin, isTrue);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.cookieStore.credentials.uid, 'u-b');
      expect(h.ledger.strikes, 0);
      expect(h.ledger.last, isNull);
      expect(h.lost, 1);
      expect(h.autoSignOut, 0);
      expect(h.keepAlive.isArmed, isTrue);
      h.keepAlive.dispose();
    });

    test('A 的探测在退出后返回失效，不写回证据也不触发退出', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      await _pumpUntil(() => h.probes.isNotEmpty);

      await h.account.signOut();
      h.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.ledger.strikes, 0);
      expect(h.ledger.last, isNull);
      expect(h.lost, 1);
      expect(h.autoSignOut, 0);
      expect(h.keepAlive.isArmed, isFalse);
      h.keepAlive.dispose();
    });

    test('切到 B 后旧探测返回失效，不触发 B 的自动退出', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      await _pumpUntil(() => h.probes.isNotEmpty);

      await h.account.signOut();
      await h.account.importLoginCookie('uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b');
      // B 自己已经有了两次真实回绝；旧探测不能被算成第三次。
      noteAccountRejection(h.ledger);
      h.clock.advance(const Duration(minutes: 31));
      noteAccountRejection(h.ledger);
      expect(h.ledger.strikes, 2);

      h.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(h.autoSignOut, 0);
      expect(h.lost, 1);
      expect(h.account.status, AuthStatus.unverified);
      expect(h.account.hasLogin, isTrue);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-b');
      expect(h.ledger.strikes, 2);
      expect(h.keepAlive.isArmed, isTrue);
      h.keepAlive.dispose();
    });

    test('当前会话的探测返回失效仍按原逻辑标记失效', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      await _pumpUntil(() => h.probes.isNotEmpty);

      h.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(h.account.status, AuthStatus.rejected);
      expect(h.ledger.strikes, 0);
      expect(h.lost, 0);
      expect(h.autoSignOut, 0);
      expect(h.keepAlive.isArmed, isFalse);
      h.keepAlive.dispose();
    });

    test('切到 B 后旧探测返回存活，不把 B 标成已验证', () async {
      final h = await _Harness.create();
      await h.account.importLoginCookie('uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a');
      await _pumpUntil(() => h.probes.isNotEmpty);

      await h.account.signOut();
      await h.account.importLoginCookie('uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b');
      expect(h.account.status, AuthStatus.unverified);

      h.probes.first.complete(SessionProbe.alive);
      await _flush();

      expect(h.account.status, AuthStatus.unverified);
      expect(h.account.hasLogin, isTrue);
      expect(h.lost, 1);
      expect(h.keepAlive.isArmed, isTrue);
      h.keepAlive.dispose();
    });
  });
}
