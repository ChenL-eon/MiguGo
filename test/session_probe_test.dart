import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final FutureOr<ResponseBody> Function(RequestOptions options) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => reply(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String text, {int status = 200}) => ResponseBody.fromString(
  text,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Future<MiguCookieStore> _store({String? cookie}) async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  if (cookie != null) await store.importLoginCookies(cookie);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('登录态判定', () {
    test('只有 HTTP 401 判为失效，403 与其余非 2xx 都不判', () {
      expect(
        classifySessionProbe(status: 401, code: '', info: ''),
        SessionProbe.revoked,
      );
      // 403 更可能是这首歌没有权益，当成失效会把人无故登出。
      expect(
        classifySessionProbe(status: 403, code: '', info: ''),
        SessionProbe.unknown,
      );
      expect(
        classifySessionProbe(status: 503, code: '', info: ''),
        SessionProbe.unknown,
      );
    });

    test('业务码为成功时判为有效', () {
      for (final code in ['', '000000', '0000', '0', '200']) {
        expect(
          classifySessionProbe(status: 200, code: code, info: '成功'),
          SessionProbe.alive,
          reason: code,
        );
      }
    });

    test('“请先登录”这类文案判为失效', () {
      expect(
        classifySessionProbe(status: 200, code: '290001', info: '请先登录'),
        SessionProbe.revoked,
      );
      expect(
        classifySessionProbe(status: 200, code: 'X', info: '登录状态已失效'),
        SessionProbe.revoked,
      );
      expect(
        classifySessionProbe(status: 200, code: 'X', info: 'token已失效，请重新获取'),
        SessionProbe.revoked,
      );
    });

    test('认不准的编码保持 unknown，避免误伤听歌', () {
      expect(
        classifySessionProbe(status: 200, code: '299999', info: 'uid不能为空'),
        SessionProbe.unknown,
      );
      expect(
        classifySessionProbe(status: 200, code: '210004', info: '参数错误'),
        SessionProbe.unknown,
      );
      // 「登录状态」「token」这两个宽泛词以前会把参数报错也算成失效，现在不再。
      expect(
        classifySessionProbe(status: 200, code: '210004', info: 'token不能为空'),
        SessionProbe.unknown,
      );
      expect(
        classifySessionProbe(status: 200, code: '210004', info: '登录状态参数缺失'),
        SessionProbe.unknown,
      );
    });
  });

  group('会话失效取证与上报', () {
    const accountUrl = 'https://app.c.nf.migu.cn/user/h5/user-info/v1.0';
    const publicUrl = 'https://app.u.nf.migu.cn/migu/remoting/lyric_read';

    test('账号接口回 401 时既上报也记账', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            (_) => _json("{\"code\":\"E401\",\"info\":\"unauthorized\"}", status: 401),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(client.getJson(accountUrl), throwsA(isA<MiguApiException>()));
      expect(revoked, 1);
      expect(ledger.strikes, 1);
      expect(ledger.last!.path, '/user/h5/user-info/v1.0');
      expect(ledger.last!.status, 401);
      expect(ledger.last!.loginScoped, isTrue);
    });

    test('公开接口的 401 只留证据，不上报也不计数', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()..httpClientAdapter = _StubAdapter((_) => _json('{}', status: 401)),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(client.getJson(publicUrl), throwsA(isA<MiguApiException>()));
      expect(revoked, 0);
      expect(ledger.strikes, 0);
      expect(ledger.last, isNotNull);
      expect(ledger.last!.loginScoped, isFalse);
    });

    test('未登录时的 401 不打扰用户', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()..httpClientAdapter = _StubAdapter((_) => _json('{}', status: 401)),
        cookieStore: await _store(),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(client.getJson(accountUrl), throwsA(isA<MiguApiException>()));
      expect(revoked, 0);
      expect(ledger.strikes, 0);
    });

    test('一波并发失败只算一次取证', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            (options) => _json('{"code":"290001","info":"请先登录"}'),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await client.getJson(accountUrl);
      await client.getJson('https://app.c.nf.migu.cn/pc/user/home-page/v1.0');
      expect(revoked, 2);
      expect(ledger.strikes, 1);
    });

    test('账号接口成功回包把旧账清零', () async {
      final (ledger, _) = testLedger();
      noteAccountRejection(ledger);
      expect(ledger.strikes, 1);

      final client = MiguApiClient(
        dio: Dio()..httpClientAdapter = _StubAdapter((_) => _json('{"code":"000000"}')),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
      );

      await client.getJson(accountUrl);
      expect(ledger.strikes, 0);
      // 计数清了，但那次失败仍然留着，界面还能解释上一条提示为什么出现过。
      expect(ledger.last, isNotNull);
    });

    test('HTTP 200 + “请先登录”同样上报，并带上重新登录标记', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            (_) => _json('{"code":"290001","info":"请先登录"}'),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );
      final api = MiguMusicApi(client: client);

      await expectLater(api.fetchUserProfile(), throwsA(isA<MiguApiException>()));
      expect(revoked, 1);
      expect(ledger.strikes, 1);
      expect(ledger.last!.info, '请先登录');
    });

    test('请求自动带上 deviceId 与账号凭据头', () async {
      final adapter = _StubAdapter((_) => _json('{"code":"000000"}'));
      final options = <RequestOptions>[];
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = adapter
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                options.add(o);
                h.next(o);
              },
            ),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
      );

      await client.getJson(accountUrl);
      final headers = options.single.headers;
      expect(headers['deviceId'], isNotNull);
      expect(headers['uid'], 'u1');
      expect(headers['pacmtoken'], 'p1');
    });
  });

  group('前台保活探测', () {
    test('没有 pacmtoken 时不发请求：探测只认这份唯一凭据', () async {
      final requests = <String>[];
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              requests.add(options.uri.toString());
              return _json('{"code":"000000"}');
            }),
          cookieStore: await _store(cookie: 'uid=u1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.unknown);
      expect(requests, isEmpty);
    });

    test('凭据仍被接受时返回 alive', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter(
              (_) => _json('{"code":"000000","data":{"nickname":"测试"}}'),
            ),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );
      expect(await api.checkSessionAlive(), SessionProbe.alive);
    });

    test('服务端回“请先登录”时返回 revoked', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter(
              (_) => _json('{"code":"290001","info":"请先登录"}'),
            ),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );
      expect(await api.checkSessionAlive(), SessionProbe.revoked);
    });

    test('网络异常只返回 unknown', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter(
              (_) => throw DioException(
                type: DioExceptionType.connectionError,
                requestOptions: RequestOptions(path: ''),
              ),
            ),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );
      expect(await api.checkSessionAlive(), SessionProbe.unknown);
    });
  });
}
