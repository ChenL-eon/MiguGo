import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
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

ResponseBody _json(
  String text, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  text,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

class _DelayedDiagnostics extends SessionProbeDiagnostics {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> record(SessionProbeRecord record) async {
    entered.complete();
    await release.future;
  }
}

Future<MiguCookieStore> _store({String? cookie}) async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  if (cookie != null) await store.importLoginCookies(cookie);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final profileAlive in [true, false]) {
    test('完整探测完成后才裁决退出，资料兜底成功=$profileAlive', () async {
      final storage = FakeSecureCookieStorage();
      final store = MiguCookieStore(secureStorage: storage);
      await store.init();
      await store.importLoginCookies('pacmtoken=p1; uid=u1');
      final (ledger, clock) = testLedger();
      ledger.note(
        uri: Uri.parse(AppConstants.pacmCheckUrl),
        loginScoped: true,
        status: 200,
        code: '850005',
      );
      clock.advance(const Duration(minutes: 31));
      var exits = 0;
      late final AccountProvider account;
      account = AccountProvider(
        cookieStore: store,
        authSessionStore: AuthSessionStore(storage: storage),
        passportTicketStore: PassportTicketStore(storage: storage),
        ledger: ledger,
        onAutoSignOut: () async {
          exits++;
          await account.signOut();
        },
      );
      await account.initialize();
      var loginAtFallback = false;
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()..httpClientAdapter = _StubAdapter((options) {
            if (options.uri.path.toLowerCase().contains('checkpacmtoken')) {
              return _json('{"code":"850005","info":"登录超时"}');
            }
            loginAtFallback = account.hasLogin;
            return profileAlive
                ? _json('{"code":"000000","data":{"nickname":"test"}}')
                : _json('{"code":"290001","info":"请先登录"}');
          }),
          cookieStore: store,
          ledger: ledger,
          sessionEpoch: () => account.credentialEpoch,
          onSessionRevoked: account.markSessionRevoked,
        ),
        sessionEpoch: () => account.credentialEpoch,
      );

      final verdict = await api.checkSessionAlive();
      await Future<void>.delayed(Duration.zero);
      expect(loginAtFallback, isTrue);
      expect(verdict, profileAlive ? SessionProbe.alive : SessionProbe.revoked);
      expect(exits, profileAlive ? 0 : 1);
      expect(account.hasLogin, profileAlive);
      if (profileAlive) expect(ledger.strikes, 0);
    });
  }

  group('完整探测证据边界', () {
    for (final officialRejected in [false, true]) {
      for (final hasUid in [false, true]) {
        test('资料拒绝只在完整裁决后记一次，官方拒绝=$officialRejected，uid=$hasUid', () async {
          final store = await _store(
            cookie: 'pacmtoken=p1${hasUid ? '; uid=u1' : ''}',
          );
          final (ledger, _) = testLedger();
          var callbacks = 0;
          final api = MiguMusicApi(
            client: MiguApiClient(
              cookieStore: store,
              ledger: ledger,
              onSessionRevoked: () => callbacks++,
              dio: Dio()..httpClientAdapter = _StubAdapter((options) {
                if (options.uri.path.toLowerCase().contains('checkpacmtoken')) {
                  return _json(officialRejected
                      ? '{"code":"850005"}'
                      : '{"code":"850003","info":"内部错误"}');
                }
                expect(callbacks, 0);
                expect(ledger.strikes, 0);
                return _json('{"code":"290001","info":"请先登录"}');
              }),
            ),
          );
          final rejected = officialRejected || hasUid;
          expect(await api.checkSessionAlive(),
              rejected ? SessionProbe.revoked : SessionProbe.unknown);
          expect(callbacks, rejected ? 1 : 0);
          expect(ledger.strikes, rejected ? 1 : 0);
          if (rejected) {
            expect(ledger.lastAccount!.path, Uri.parse(officialRejected
                ? AppConstants.pacmCheckUrl
                : AppConstants.userProfileUrl).path);
          }
        });
      }
    }

    test('两个接口都无法确认时不新增或清除拒绝计数', () async {
      final (ledger, clock) = testLedger();
      noteAccountRejection(ledger);
      clock.advance(const Duration(minutes: 31));
      var callbacks = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
          ledger: ledger,
          onSessionRevoked: () => callbacks++,
          dio: Dio()..httpClientAdapter = _StubAdapter(
            (_) => _json('{}', status: 503),
          ),
        ),
      );
      expect(await api.checkSessionAlive(), SessionProbe.unknown);
      expect(ledger.strikes, 1);
      expect(callbacks, 0);
    });

    test('探测等待兜底期间，独立账号请求仍正常记录拒绝', () async {
      final fallbackEntered = Completer<void>();
      final fallbackRelease = Completer<void>();
      final (ledger, _) = testLedger();
      var callbacks = 0;
      final client = MiguApiClient(
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => callbacks++,
        dio: Dio()..httpClientAdapter = _StubAdapter((options) async {
          if (options.uri.path == Uri.parse(AppConstants.userProfileUrl).path) {
            fallbackEntered.complete();
            await fallbackRelease.future;
            return _json('{"code":"000000"}');
          }
          return _json('{"code":"290001","info":"请先登录"}');
        }),
      );
      final pending = MiguMusicApi(client: client).checkSessionAlive();
      await fallbackEntered.future;
      expect(callbacks, 0);
      expect(ledger.strikes, 0);
      await client.getRaw(AppConstants.userHomePageUrl);
      expect(callbacks, 1);
      expect(ledger.strikes, 1);
      fallbackRelease.complete();
      expect(await pending, SessionProbe.alive);
      expect(callbacks, 1);
      expect(ledger.strikes, 0);
    });

    test('官方拒绝返回前换号，不再用新账号做旧探测兜底', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final store = await _store(cookie: 'pacmtoken=old; uid=u1');
      final (ledger, _) = testLedger();
      var callbacks = 0;
      var profiles = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(
          cookieStore: store,
          ledger: ledger,
          onSessionRevoked: () => callbacks++,
          dio: Dio()..httpClientAdapter = _StubAdapter((options) async {
            if (options.uri.path.toLowerCase().contains('checkpacmtoken')) {
              entered.complete();
              await release.future;
              return _json('{"code":"850005"}');
            }
            profiles++;
            return _json('{"code":"290001"}');
          }),
        ),
      );
      final pending = api.checkSessionAlive();
      await entered.future;
      await store.importLoginCookies('pacmtoken=new; uid=u2');
      release.complete();
      expect(await pending, SessionProbe.unknown);
      expect(profiles, 0);
      expect(callbacks, 0);
      expect(ledger.strikes, 0);
      expect(store.credentials.pacmtoken, 'new');
    });

    for (final alive in [false, true]) {
      for (final duringDiagnostics in [false, true]) {
        test('换号后旧结论不更改新账号计数，alive=$alive，诊断等待=$duringDiagnostics', () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final diagnostics = _DelayedDiagnostics();
          final store = await _store(cookie: 'pacmtoken=old; uid=u1');
          final (ledger, _) = testLedger();
          var callbacks = 0;
          final api = MiguMusicApi(
            diagnostics: duringDiagnostics ? diagnostics : null,
            client: MiguApiClient(
              cookieStore: store,
              ledger: ledger,
              onSessionRevoked: () => callbacks++,
              dio: Dio()..httpClientAdapter = _StubAdapter((options) async {
                if (options.uri.path.toLowerCase().contains('checkpacmtoken')) {
                  return _json('{"code":"850003"}');
                }
                if (!duringDiagnostics) {
                  entered.complete();
                  await release.future;
                }
                return _json(alive ? '{"code":"000000"}' : '{"code":"290001"}');
              }),
            ),
          );
          final pending = api.checkSessionAlive();
          await (duringDiagnostics ? diagnostics.entered.future : entered.future);
          await store.importLoginCookies('pacmtoken=new; uid=u2');
          noteAccountRejection(ledger);
          if (duringDiagnostics) {
            diagnostics.release.complete();
          } else {
            release.complete();
          }
          expect(await pending, SessionProbe.unknown);
          expect(callbacks, 0);
          expect(ledger.strikes, 1);
          expect(store.credentials.pacmtoken, 'new');
        });
      }
    }
  });

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
            (_) => _json(
              "{\"code\":\"E401\",\"info\":\"unauthorized\"}",
              status: 401,
            ),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(
        client.getJson(accountUrl),
        throwsA(isA<MiguApiException>()),
      );
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
        dio: Dio()
          ..httpClientAdapter = _StubAdapter((_) => _json('{}', status: 401)),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(
        client.getJson(publicUrl),
        throwsA(isA<MiguApiException>()),
      );
      expect(revoked, 0);
      expect(ledger.strikes, 0);
      expect(ledger.last, isNotNull);
      expect(ledger.last!.loginScoped, isFalse);
    });

    test('未登录时的 401 不打扰用户', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter((_) => _json('{}', status: 401)),
        cookieStore: await _store(),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      await expectLater(
        client.getJson(accountUrl),
        throwsA(isA<MiguApiException>()),
      );
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
        dio: Dio()
          ..httpClientAdapter = _StubAdapter((_) => _json('{"code":"000000"}')),
        cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ledger: ledger,
      );

      await client.getJson(accountUrl);
      expect(ledger.strikes, 0);
      // 计数清了，但那次失败仍然留着，界面还能解释上一条提示为什么出现过。
      expect(ledger.last, isNotNull);
    });

    test('官方校验接口回成功码也清零，错误页那种空编码不算', () async {
      final (ledger, _) = testLedger();
      noteAccountRejection(ledger);
      expect(ledger.strikes, 1);

      Future<void> probe(String body) async {
        final client = MiguApiClient(
          dio: Dio()..httpClientAdapter = _StubAdapter((_) => _json(body)),
          cookieStore: await _store(cookie: 'pacmtoken=p1'),
          ledger: ledger,
        );
        await client.getJson('https://c.musicapp.migu.cn/mgateway/api/checkPacMtoken');
      }

      // 空编码可能是错误页，不能拿它把旧账洗掉。
      await probe('{}');
      expect(ledger.strikes, 1);

      await probe('{"code":"000000"}');
      expect(ledger.strikes, 0);
    });

    test('缺 uid 时三个账号接口的回绝都只留证据', () async {
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            (_) => _json('{"code":"290001","info":"请先登录"}'),
          ),
        // 原生登录只有 pacmtoken，没有 uid。
        cookieStore: await _store(cookie: 'pacmtoken=p1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      for (final url in const [
        'https://app.c.nf.migu.cn/pc/user/home-page/v1.0',
        'https://app.c.nf.migu.cn/user/h5/user-info/v1.0',
        'https://app.c.nf.migu.cn/pc/user/h5/queryUserInfo/v1.0',
      ]) {
        await client.getJson(url);
      }
      // 三个接口对「缺 uid」回的都是这一句；计入的话，两次就把还好用的凭据退掉了。
      expect(revoked, 0, reason: '缺 uid 也会回 290001，不能算作凭据失效');
      expect(ledger.strikes, 0);
      expect(ledger.lastAccount, isNull);
      expect(ledger.last!.loginScoped, isFalse);
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

      await expectLater(
        api.fetchUserProfile(),
        throwsA(isA<MiguApiException>()),
      );
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

  group('官方 checkPacMtoken 校验与轮换', () {
    const checkPath = '/mgateway/api/checkPacMtoken';
    const profilePath = '/user/h5/user-info/v1.0';

    test('先走官方校验，成功即返回 alive 并写回轮换的 pacmtoken', () async {
      final requests = <Uri>[];
      final store = await _store(
        cookie: 'uid=u1; pacmtoken=old; mg_auth_pacmtoken=old',
      );
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              requests.add(options.uri);
              return _json(
                '{"code":"000000"}',
                headers: const {
                  'pacmtoken': ['rotated'],
                },
              );
            }),
          cookieStore: store,
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.alive);
      expect(requests.map((uri) => uri.path), [checkPath]);
      expect(store.credentials.pacmtoken, 'rotated');
      // 网页快照里的同义别名必须一起换，否则下次启动又会取回旧值。
      expect(store.loginSnapshot['mg_auth_pacmtoken'], 'rotated');
    });

    test('诊断记录轮换与过期元数据，且不保存凭据值', () async {
      final preferences = await SharedPreferences.getInstance();
      final diagnostics = SessionProbeDiagnostics(
        preferences: preferences,
        enabled: true,
      );
      final store = await _store(
        cookie:
            'uid=u1; pacmtoken=old-secret-token; '
            'mg_auth_pacmtoken=old-secret-token',
      );
      final api = MiguMusicApi(
        diagnostics: diagnostics,
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              return _json(
                '{"code":"000000"}',
                headers: const {
                  'pacmtoken': ['new-secret-token'],
                  'set-cookie': [
                    'pacmtoken=new-secret-token; Path=/; Max-Age=2592000',
                  ],
                },
              );
            }),
          cookieStore: store,
        ),
      );

      expect(
        await api.checkSessionAlive(trigger: 'keep-alive'),
        SessionProbe.alive,
      );

      final record = (await diagnostics.load()).single;
      expect(record.trigger, 'keep-alive');
      expect(record.verdict, SessionProbe.alive);
      expect(record.officialCode, '000000');
      expect(record.rotationHeader, isTrue);
      expect(record.rotated, isTrue);
      expect(record.expiryFromResponse, isNotNull);

      final text = await diagnostics.exportText();
      expect(text, contains('keep-alive'));
      expect(text, isNot(contains('new-secret-token')));
      expect(text, isNot(contains('old-secret-token')));
    });

    test('官方校验只回 850002 时改用账号资料确认', () async {
      final requests = <Uri>[];
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              requests.add(options.uri);
              if (options.uri.path == checkPath) {
                return _json('{"info":"内部错误","code":"850002"}');
              }
              return _json('{"code":"000000","data":{"nickname":"测试"}}');
            }),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.alive);
      expect(requests.map((uri) => uri.path), [checkPath, profilePath]);
    });

    test('官方校验认不准、账号资料明确失效时返回 revoked', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              if (options.uri.path == checkPath) {
                return _json('{"info":"内部错误","code":"850002"}');
              }
              return _json('{"code":"290001","info":"请先登录"}');
            }),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.revoked);
    });

    test('两份探测都看不懂时保持 unknown，不判失效', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              if (options.uri.path == checkPath) {
                return _json('{"info":"内部错误","code":"850002"}');
              }
              return _json('{"code":"210004","info":"参数错误"}');
            }),
          cookieStore: await _store(cookie: 'pacmtoken=p1; uid=u1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.unknown);
    });

    test('校验接口回 850005 登录超时，缺 uid 也判失效', () async {
      // 2026-10-26 真机记录：前一晚 `000000` 通过并轮换过 token，次日开机回这句，
      // 同时账号资料与歌单都是 `290001`、VIP 取链拿不到地址。这个接口只看
      // `pacmtoken`，它的回绝没有「缺 uid」这种解释，所以不需要 uid 也能定案。
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              if (options.uri.path == checkPath) {
                return _json('{"info":"登录超时","code":"850005"}');
              }
              return _json('{"code":"290001","info":"请先登录"}');
            }),
          cookieStore: await _store(cookie: 'pacmtoken=p1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.revoked);
    });

    test('校验接口回 850003 内部错误时仍然给不出失效结论', () async {
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter((options) {
              if (options.uri.path == checkPath) {
                return _json('{"info":"内部错误","code":"850003"}');
              }
              return _json('{"code":"290001","info":"请先登录"}');
            }),
          cookieStore: await _store(cookie: 'pacmtoken=p1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.unknown);
    });

    test('校验接口回 850005 时，拦截器那条路径也给同一个结论', () async {
      // 探测走 checkSessionAlive，取证走拦截器；同一句回包若两处判定不一致，
      // 就会出现「界面说没失效，状态却一直在降级」。
      final (ledger, _) = testLedger();
      var revoked = 0;
      final client = MiguApiClient(
        dio: Dio()
          ..httpClientAdapter = _StubAdapter(
            (_) => _json('{"info":"登录超时","code":"850005"}'),
          ),
        cookieStore: await _store(cookie: 'pacmtoken=p1'),
        ledger: ledger,
        onSessionRevoked: () => revoked++,
      );

      try {
        await client.getRaw('https://c.musicapp.migu.cn$checkPath');
      } on MiguApiException catch (_) {
        // 抛不抛不重要，这里只看它有没有把它当成凭据被拒来取证。
      }

      expect(revoked, 1);
      expect(ledger.strikes, 1);
      expect(ledger.last!.path, checkPath);
      expect(ledger.last!.loginScoped, isTrue);
    });

    test('响应头带 pacmtoken= 前缀或属性时只取新值', () async {
      final store = await _store(cookie: 'pacmtoken=old');
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter(
              (_) => _json(
                '{"code":"000000"}',
                headers: const {
                  'pacmtoken': ['pacmtoken=rotated; Path=/; HttpOnly'],
                },
              ),
            ),
          cookieStore: store,
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.alive);
      expect(store.credentials.pacmtoken, 'rotated');
    });

    test('轮换值不合法时不写回，避免把坏值发出去', () async {
      final store = await _store(cookie: 'pacmtoken=old');
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()
            ..httpClientAdapter = _StubAdapter(
              (_) => _json(
                '{"code":"000000"}',
                headers: const {
                  'pacmtoken': ['bad value'],
                },
              ),
            ),
          cookieStore: store,
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.alive);
      expect(store.credentials.pacmtoken, 'old');
    });
  });
}
