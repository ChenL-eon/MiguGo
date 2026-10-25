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

/// 通行证网络层：第一次换票（登录）正常，第二次（续期）停在闸门上等测试放行。
class _GatedRenewalAdapter extends PassportStubAdapter {
  _GatedRenewalAdapter({required this.failAsNetwork});

  /// true：续期请求根本没发出去（网络中断）；false：咪咕明确回绝这张票据。
  final bool failAsNetwork;

  final List<Completer<void>> renewGates = [];
  int _validateSeen = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.toString().contains('token-validate')) {
      _validateSeen++;
      if (_validateSeen >= 2) {
        final gate = Completer<void>();
        renewGates.add(gate);
        await gate.future;
        if (failAsNetwork) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        // 服务端答了但拒绝：这才是「凭据不被接受」的信号。
        return ResponseBody.fromString(
          '{"status":"9999","message":"票据已失效"}',
          403,
          headers: {
            'content-type': [Headers.jsonContentType],
          },
        );
      }
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _Counts {
  int lost = 0;
  int autoSignOuts = 0;
}

class _Harness {
  _Harness._({
    required this.storage,
    required this.cookieStore,
    required this.adapter,
    required this.account,
    required this.ledger,
    required this.clock,
    required this.counts,
  });

  final FakeSecureCookieStorage storage;
  final MiguCookieStore cookieStore;
  final _GatedRenewalAdapter adapter;
  final AccountProvider account;
  final SessionRejectLedger ledger;
  final StepClock clock;
  final _Counts counts;

  static Future<_Harness> create({required bool failAsNetwork}) async {
    SharedPreferences.setMockInitialValues({});
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final adapter = _GatedRenewalAdapter(failAsNetwork: failAsNetwork);
    final (ledger, clock) = testLedger();
    final counts = _Counts();
    late final AccountProvider account;
    account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: MiguPassportApi(dio: dioWith(adapter)),
      ledger: ledger,
      onSessionLost: () => counts.lost++,
      onAutoSignOut: () async {
        counts.autoSignOuts++;
        await account.signOut();
      },
    );
    await account.initialize();
    await account.signInWithSmsCode(phone: '13800000000', code: '248157');
    return _Harness._(
      storage: storage,
      cookieStore: cookieStore,
      adapter: adapter,
      account: account,
      ledger: ledger,
      clock: clock,
      counts: counts,
    );
  }

  /// 两次账号接口回绝，隔过 confirmGap：取证已经凑够两次。
  void armTwoStrikes() {
    noteAccountRejection(ledger);
    clock.advance(const Duration(minutes: 31));
    noteAccountRejection(ledger);
    expect(ledger.strikes, 2);
  }

  /// 触发静默续期，并等它停在网络闸门上。
  Future<void> startRenewal() async {
    account.markSessionRevoked();
    await _pumpUntil(() => adapter.renewGates.isNotEmpty);
    expect(adapter.renewGates, hasLength(1));
  }

  void releaseRenewal() => adapter.renewGates.last.complete();

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('条件没有达成：续期没有停在闸门上');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('续期失败原因分流', () {
    test('续期时网络中断，凑够两次取证也不退出登录', () async {
      final h = await _Harness.create(failAsNetwork: true);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      await h.settle();

      expect(h.counts.autoSignOuts, 0, reason: '请求没发出去不代表凭据作废');
      expect(h.counts.lost, 0);
      expect(h.account.hasLogin, isTrue);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(h.account.status, isNot(AuthStatus.none));
    });

    test('只有咪咕明确回绝续期票据时才自动退出', () async {
      final h = await _Harness.create(failAsNetwork: false);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      await h.settle();

      expect(h.counts.autoSignOuts, 1);
      expect(h.account.hasLogin, isFalse);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
    });
  });
}
