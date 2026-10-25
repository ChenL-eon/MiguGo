import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, required this.body});

  final int status;
  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        'content-type': [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<MiguCookieStore> _store() async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  await store.importLoginCookies('pacmtoken=p1; mg_auth_sid=s1');
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('失效取证的归属', () {
    test('公开接口的 401 不抢走“登录可能已失效”的证据', () async {
      final (ledger, _) = testLedger();
      final account = AccountProvider(cookieStore: await _store(), ledger: ledger);

      noteAccountRejection(ledger);
      notePublicRejection(ledger);
      account.markRejected();

      expect(account.status, AuthStatus.rejected);
      expect(
        account.statusHint,
        contains('/user/h5/user-info/'),
        reason: '状态说明要引用要求登录的账号接口',
      );
      expect(account.statusHint, isNot(contains('lyric_read')));
    });
  });

  group('HTTP 403 取证', () {
    Future<({SessionRejectLedger ledger, int revoked})> probe403({
      required String url,
    }) async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            status: 403,
            body: '{"code":"440022","info":"没有权限"}',
          ),
        cookieStore: await _store(),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );
      // 403 会被转换成可展示异常向上抛；这里只关心拦截器留下的证据。
      await client.getJson(url).catchError((_) => null);
      return (ledger: ledger, revoked: revoked);
    }

    test('403 留下一条证据，但一次都不计入失效判定', () async {
      final result = await probe403(url: 'https://app.c.nf.migu.cn/MUS/lyric/read');

      expect(result.ledger.last, isNotNull, reason: '文档说 403 只留记录');
      expect(result.ledger.last!.status, 403);
      expect(result.ledger.strikes, 0);
      expect(result.revoked, 0);
    });

    test('账号接口回 403 也只留记录：可能只是这首歌没有权益', () async {
      final result = await probe403(
        url: 'https://app.c.nf.migu.cn/MUS/RS/user/h5/user-info/v1.0',
      );

      expect(result.ledger.last, isNotNull);
      expect(result.ledger.strikes, 0);
      expect(result.revoked, 0);
    });
  });
}
