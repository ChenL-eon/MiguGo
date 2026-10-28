import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

enum _RenewalOutcome {
  /// 续期成功：咪咕认这张票据，回了一份新凭据。
  renewed,

  /// HTTP 200 但没有下发新凭据（实测失效票据就是这样，配 `199999`）。
  noToken,

  /// HTTP 200、正文不是 JSON（内容类型不对或被中间层换掉），什么码都读不出。
  plainBody,

  /// 请求根本没发出去：网络中断。
  network,

  /// 服务端回了 403，但分不清是票据失效还是接口本身不许访问。
  forbidden,

  /// 服务端回了 401：明确回绝这张票据。
  unauthorized,
}

/// 通行证网络层：第一次换票（登录）正常，第二次（续期）停在闸门上等测试放行。
class _GatedRenewalAdapter extends PassportStubAdapter {
  _GatedRenewalAdapter({required this.outcome});

  final _RenewalOutcome outcome;

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
        if (outcome == _RenewalOutcome.renewed) {
          return super.fetch(options, requestStream, cancelFuture);
        }
        if (outcome == _RenewalOutcome.noToken) {
          // 咪咕认不下这张票据时的真实形态：200、不下发 Set-Cookie、业务码 199999。
          return ResponseBody.fromString(
            '{"status":"199999","message":"系统繁忙"}',
            200,
            headers: {'content-type': [Headers.jsonContentType]},
          );
        }
        if (outcome == _RenewalOutcome.plainBody) {
          return ResponseBody.fromString(
            '<html>blocked</html>',
            200,
            headers: {
              'content-type': ['text/plain; charset=utf-8'],
            },
          );
        }
        if (outcome == _RenewalOutcome.network) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        // 403 不能被当成“凭据作废”，只有 401 才是明确回绝。
        return ResponseBody.fromString(
          '{"status":"9999","message":"票据已失效"}',
          outcome == _RenewalOutcome.unauthorized ? 401 : 403,
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
    required this.diagnostics,
    required this.counts,
  });

  final FakeSecureCookieStorage storage;
  final MiguCookieStore cookieStore;
  final _GatedRenewalAdapter adapter;
  final AccountProvider account;
  final SessionRejectLedger ledger;
  final StepClock clock;
  final SessionProbeDiagnostics diagnostics;
  final _Counts counts;

  static Future<_Harness> create({
    required _RenewalOutcome outcome,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final adapter = _GatedRenewalAdapter(outcome: outcome);
    final (ledger, clock) = testLedger();
    final diagnostics = SessionProbeDiagnostics(
      preferences: await SharedPreferences.getInstance(),
      enabled: true,
    );
    final counts = _Counts();
    late final AccountProvider account;
    account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: MiguPassportApi(dio: dioWith(adapter)),
      ledger: ledger,
      diagnostics: diagnostics,
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
      diagnostics: diagnostics,
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

  /// 发起一次换票，并等它停在网络闸门上。
  ///
  /// 换票现在只有调试入口这一个调用方（票据首次换票即被消耗，自动路径不再发它），
  /// 所以这里用 `debugRenewNow()` 来把失败分类与记录写满。
  Future<void> startRenewal() async {
    account.debugRenewNow();
    await _pumpUntil(() => adapter.renewGates.isNotEmpty);
    expect(adapter.renewGates, hasLength(1));
  }

  void releaseRenewal() => adapter.renewGates.last.complete();

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 调试记录里按写入顺序排好的续期条目。
  Future<List<SessionProbeRecord>> renewalRecords() async {
    await settle();
    final records = await diagnostics.load();
    return records
        .where(
          (record) => record.trigger == SessionProbeDiagnostics.renewalTrigger,
        )
        .toList();
  }

  /// 一次换票落下的那条结果。
  ///
  /// 手动入口会先记一条「主动发起」再记结果，所以这里是两条；只看第一条会把
  /// 「发起过」当成「问到什么」，现场读记录的人也确实会读到这两行。
  Future<SessionProbeRecord> renewalOutcome() async {
    final records = await renewalRecords();
    expect(records, hasLength(2));
    expect(records.first.note, '调试：主动发起一次续期');
    return records.last;
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
    test('自动失效判定不再白发续期，两次取证一定走完退出', () async {
      // 2026-10-26 真机确认票据在首次换票时就被消耗掉，自动续期永远换不到新会话；
      // 它原先还把 `markSessionRevoked` 的裁决吞成 `markRejected`，界面因此长期挂着
      // 死凭据、不自动退出。这里钉住两件事：不白发请求、退出不再被吞。
      final h = await _Harness.create(outcome: _RenewalOutcome.noToken);
      h.armTwoStrikes();

      h.account.markSessionRevoked();
      await h.settle();

      expect(h.adapter.renewGates, isEmpty);
      expect(await h.renewalRecords(), isEmpty);
      expect(h.counts.autoSignOuts, 1);
      expect(h.account.hasLogin, isFalse);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
    });

    test('续期时网络中断，凑够两次取证也不退出登录', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.network);
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

    test('续期被 403 回绝也不能判死：只降级状态，凭据保留', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.forbidden);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      await h.settle();

      expect(h.counts.autoSignOuts, 0, reason: '403 分不清是票据失效还是接口不许访问');
      expect(h.counts.lost, 0);
      expect(h.account.hasLogin, isTrue);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(h.account.status, AuthStatus.rejected);
    });

    test('续期被 401 明确回绝，且已有两次取证时自动退出', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.unauthorized);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      await h.settle();

      expect(h.counts.autoSignOuts, 1);
      expect(h.account.hasLogin, isFalse);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
    });
  });

  group('续期结果写进调试记录', () {
    test('换到新凭据时记下写回成功，导出看得出新会话真换到了', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.renewed);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      final record = await h.renewalOutcome();

      expect(record.verdict, SessionProbe.alive);
      expect(record.rotated, isTrue);
      expect(record.note, contains('换到新凭据并写回'));
      expect(h.account.status, AuthStatus.verified);
    });

    test('网络中断的续期记为问不到结果，不写成票据作废', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.network);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      final record = await h.renewalOutcome();

      expect(record.verdict, SessionProbe.unknown);
      expect(record.rotated, isFalse);
      expect(record.note, '请求没到达咪咕，没问到结果');
    });

    test('403 与 401 各记各的：分不清和明确回绝不写成同一条', () async {
      final ambiguous = await _Harness.create(
        outcome: _RenewalOutcome.forbidden,
      );
      ambiguous.armTwoStrikes();
      await ambiguous.startRenewal();
      ambiguous.releaseRenewal();

      final rejected = await _Harness.create(
        outcome: _RenewalOutcome.unauthorized,
      );
      rejected.armTwoStrikes();
      await rejected.startRenewal();
      rejected.releaseRenewal();

      final ambiguousRecord = await ambiguous.renewalOutcome();
      expect(ambiguousRecord.verdict, SessionProbe.unknown);
      expect(ambiguousRecord.note, contains('分不清票据问题还是服务抖动'));
      expect(ambiguousRecord.officialStatus, 403);
      expect(ambiguousRecord.officialCode, '9999');

      final rejectedRecord = await rejected.renewalOutcome();
      expect(rejectedRecord.verdict, SessionProbe.revoked);
      expect(rejectedRecord.note, '咪咕明确回绝这张票据');
      expect(rejectedRecord.officialStatus, 401);
      // 现场排查时读的是导出文本，续期那几行必须真的能读出来。
      expect(
        await rejected.diagnostics.exportText(),
        contains('结果: 咪咕明确回绝这张票据'),
      );
    });

    test('200 却不给新凭据时记下票据码，与服务端风控分得开', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.noToken);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      final record = await h.renewalOutcome();

      expect(record.verdict, SessionProbe.unknown);
      expect(record.officialStatus, 200);
      expect(record.officialCode, '199999');
      expect(
        await h.diagnostics.exportText(),
        contains('续期: 本机已换新凭据=否, HTTP 200, 票据码 199999'),
      );
      // 这种回包判不死票据：只降级状态，凭据与票据都留着。
      expect(h.account.status, AuthStatus.rejected);
      expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
    });

    test('原生登录没有留存票据时，记下续期压根没法试', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.renewed);
      await h.account.importLoginCookie(
        'uid=u-web; pacmtoken=pacm-web; mg_auth_sid=s-web',
      );
      expect(await h.renewalRecords(), isEmpty);

      expect(h.account.debugRenewNow(), '本机没有留存票据，这次没试');
      final records = await h.renewalRecords();

      expect(records, hasLength(1));
      expect(records.single.verdict, SessionProbe.unknown);
      expect(records.single.note, '调试：本机没有可用票据');
      expect(h.adapter.renewGates, isEmpty);
    });

    test('200 且读不出业务码时记下回包形态，而不是只留一个 HTTP 200', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.plainBody);
      h.armTwoStrikes();
      await h.startRenewal();

      h.releaseRenewal();
      final record = await h.renewalOutcome();

      expect(record.officialStatus, 200);
      expect(record.officialCode, isEmpty);
      expect(record.officialInfo, '非 JSON');
      expect(
        await h.diagnostics.exportText(),
        contains('续期: 本机已换新凭据=否, HTTP 200, 回包 非 JSON'),
      );
    });

    test('调试入口不叠在已经起飞的那次上', () async {
      final h = await _Harness.create(outcome: _RenewalOutcome.renewed);

      await h.startRenewal();
      // 刚点过一次、还挂在闸门上：再点只能留一条“不叠加”，不能同时飞两次。
      expect(h.account.debugRenewNow(), '已有一次续期在飞，这次没叠加');
      final pending = await h.renewalRecords();
      expect(pending.map((record) => record.note), [
        '调试：主动发起一次续期',
        '调试：已有一次续期在飞，这次不叠加',
      ]);
      expect(h.adapter.renewGates, hasLength(1));

      h.releaseRenewal();
      expect((await h.renewalRecords()).last.note, contains('换到新凭据并写回'));
      expect(h.account.status, AuthStatus.verified);
    });
  });
}
