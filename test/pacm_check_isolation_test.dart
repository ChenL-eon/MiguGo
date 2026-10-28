import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

/// 可编排的假传输层：按到达顺序回放，把「谁先谁后」完全交给测试控制。
class _ScriptAdapter implements HttpClientAdapter {
  _ScriptAdapter(this.reply);

  final FutureOr<ResponseBody> Function(RequestOptions options) reply;
  final List<RequestOptions> requests = [];

  List<RequestOptions> get checks => requests.where(_isCheck).toList();
  int get checkCalls => checks.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

bool _isCheck(RequestOptions options) =>
    options.uri.path.toLowerCase().contains('checkpacmtoken');

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

/// 一份成功的官方校验回包，可带轮换头与下发 Cookie。
ResponseBody _aliveCheck({String? rotatesTo, List<String>? setCookie}) {
  final headers = <String, List<String>>{};
  if (rotatesTo != null) headers['pacmtoken'] = [rotatesTo];
  if (setCookie != null) headers['set-cookie'] = setCookie;
  return _json('{"code":"000000","info":"成功"}', headers: headers);
}

Future<MiguCookieStore> _store(String cookie) async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  await store.importLoginCookies(cookie);
  return store;
}

({MiguApiClient client, MiguMusicApi api, _ScriptAdapter adapter}) _harness(
  MiguCookieStore store,
  FutureOr<ResponseBody> Function(RequestOptions options) reply, {
  SessionProbeDiagnostics? diagnostics,
}) {
  final adapter = _ScriptAdapter(reply);
  final client = MiguApiClient(
    dio: Dio()..httpClientAdapter = adapter,
    cookieStore: store,
    ledger: testLedger().$1,
  );
  return (
    client: client,
    api: MiguMusicApi(client: client, diagnostics: diagnostics),
    adapter: adapter,
  );
}

Future<SessionProbeDiagnostics> _diagnostics() async =>
    SessionProbeDiagnostics(
      preferences: await SharedPreferences.getInstance(),
      enabled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('checkPacMtoken 单飞', () {
    test('同一次登录里并发探测只发一次请求，轮换只落地一次', () async {
      final diagnostics = await _diagnostics();
      final store = await _store('pacmtoken=p1; uid=u1');
      final gate = Completer<void>();
      final harness = _harness(
        store,
        (options) async {
          if (_isCheck(options)) {
            await gate.future;
            return _aliveCheck(rotatesTo: 'rotated-1');
          }
          return _aliveCheck();
        },
        diagnostics: diagnostics,
      );

      final startup = harness.api.checkSessionAlive(trigger: 'startup');
      final keepAlive = harness.api.checkSessionAlive(trigger: 'keep-alive');
      gate.complete();
      final verdicts = await Future.wait([startup, keepAlive]);

      expect(harness.adapter.checkCalls, 1);
      expect(verdicts, [SessionProbe.alive, SessionProbe.alive]);
      // 后来者复用同一次请求，写回又是幂等的，凭据只会被换一次。
      expect(store.credentials.pacmtoken, 'rotated-1');
      expect(store.credentialWriteStats.rotationWrites, 1);

      final records = await diagnostics.load();
      expect(records, hasLength(2));
      expect(records.where((record) => record.probeShared), hasLength(1));
      // 复用同一次请求的那条也看得见「本机凭证换过」，但真正的写回只有一次。
      expect(records.where((record) => record.rotated), hasLength(2));
    });

    test('失败、超时、取消都不让单飞标记粘连，下一次照样真发', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.cancel,
      ]) {
        final store = await _store('pacmtoken=p1; uid=u1');
        final harness = _harness(store, (options) {
          if (_isCheck(options)) {
            return Future.error(
              DioException(requestOptions: options, type: type),
            );
          }
          return _aliveCheck();
        });
        final api = harness.api;

        await api.checkSessionAlive(trigger: 'first');
        await api.checkSessionAlive(trigger: 'second');

        expect(
          harness.adapter.checkCalls,
          2,
          reason: '$type 之后不能把已经结束的失败探测继续当成在飞结果复用',
        );
        expect(store.credentialWriteStats.rejections, 0);
      }
    });

    test('成功探测结束后同样释放：顺序两次各发一次', () async {
      final store = await _store('pacmtoken=p1; uid=u1');
      var issued = 0;
      final harness = _harness(store, (options) {
        if (_isCheck(options)) {
          issued++;
          return _json(
            '{"code":"000000"}',
            headers: {'pacmtoken': ['r-$issued']},
          );
        }
        return _aliveCheck();
      });
      final api = harness.api;

      await api.checkSessionAlive(trigger: 'startup');
      await api.checkSessionAlive(trigger: 'manual');

      expect(harness.adapter.checkCalls, 2);
      expect(store.credentials.pacmtoken, 'r-2');
      expect(store.credentialWriteStats.rotationWrites, 2);
    });

    test('换号之后的探测不被上一代际的在飞请求顶替', () async {
      final store = await _store('pacmtoken=old-account; uid=u1');
      final gate = Completer<void>();
      // 服务端按带出去的那份凭据回一张新票：两次请求各自拿到属于自己会话的结果。
      final harness = _harness(
        store,
        (options) async {
          if (_isCheck(options)) {
            await gate.future;
            final sent = options.headers['pacmtoken'];
            return _aliveCheck(rotatesTo: '$sent-rotated');
          }
          return _aliveCheck();
        },
      );
      final api = harness.api;
      final stale = api.checkSessionAlive(trigger: 'startup');

      await store.clearLoginCookies();
      await store.importLoginCookies('pacmtoken=new-account; uid=u2');
      final fresh = api.checkSessionAlive(trigger: 'manual');

      gate.complete();
      await Future.wait([stale, fresh]);
      expect(harness.adapter.checkCalls, 2, reason: '新代际必须自己问一次');
      // 新代际那次请求带出去的是新账号的凭据；旧那次的轮换结果被代际挡在门外。
      expect(harness.adapter.checks.last.headers['pacmtoken'], 'new-account');
      expect(store.credentials.pacmtoken, 'new-account-rotated');
      expect(store.credentialWriteStats.rejections, 1);
    });
  });

  group('旧会话结果不得改写当前凭据', () {
    test('退出后在飞探测的轮换头复活不了已删除的凭据', () async {
      final diagnostics = await _diagnostics();
      final store = await _store('pacmtoken=p1; uid=u1');
      final gate = Completer<void>();
      final harness = _harness(
        store,
        (options) async {
          if (_isCheck(options)) {
            await gate.future;
            return _aliveCheck(rotatesTo: 'late-rotation');
          }
          return _aliveCheck();
        },
        diagnostics: diagnostics,
      );
      final api = harness.api;

      final pending = api.checkSessionAlive(trigger: 'startup');
      await store.clearLoginCookies();
      gate.complete();
      await pending;

      expect(store.hasImportedLogin, isFalse);
      expect(store.credentials.pacmtoken, isNull);
      expect(store.credentialSource, 'none');
      expect(store.credentialWriteStats.rejections, 1);

      final record = (await diagnostics.load()).single;
      expect(record.rotated, isFalse, reason: '旧会话的轮换不能复活已删除的凭据');
    });

    test('重新登录后，旧代际的轮换结果盖不到新凭据上', () async {
      final diagnostics = await _diagnostics();
      final store = await _store('pacmtoken=old-account; uid=u1');
      final gate = Completer<void>();
      final harness = _harness(
        store,
        (options) async {
          if (_isCheck(options)) {
            await gate.future;
            return _aliveCheck(rotatesTo: 'late-rotation');
          }
          return _aliveCheck();
        },
        diagnostics: diagnostics,
      );
      final api = harness.api;

      final pending = api.checkSessionAlive(trigger: 'startup');
      await store.clearLoginCookies();
      await store.importLoginCookies('pacmtoken=new-account; uid=u2');
      gate.complete();
      await pending;

      expect(store.credentials.pacmtoken, 'new-account');
      expect(store.credentialWriteStats.rejections, 1);
      expect(store.credentialWriteStats.rotationWrites, 0);
      final record = (await diagnostics.load()).single;
      expect(record.rotated, isFalse);
      // 记录里能看到「问的是旧那一份、写回后还是新那一份」，但看不到值。
      expect(record.credentialBefore, isNot(record.credentialAfter));
    });
  });

  group('凭据传输一致性', () {
    test('Cookie 头与裸 pacmtoken 头带出同一份，轮换后一起跟上', () async {
      final store = await _store('pacmtoken=first-token; uid=u1');
      final harness = _harness(store, (options) {
        if (_isCheck(options)) {
          return _json('{"code":"000000"}', headers: {'pacmtoken': ['second-token']});
        }
        return _aliveCheck();
      });
      final api = harness.api;

      await api.checkSessionAlive(trigger: 'startup');
      final probe = harness.adapter.checks.single;
      expect(probe.headers['pacmtoken'], 'first-token');
      expect(probe.headers['Cookie'], contains('pacmtoken=first-token'));

      await api.checkSessionAlive(trigger: 'manual');
      final afterRotation = harness.adapter.checks.last;
      expect(store.credentials.pacmtoken, 'second-token');
      expect(afterRotation.headers['pacmtoken'], 'second-token');
      expect(afterRotation.headers['Cookie'], contains('pacmtoken=second-token'));
      expect(
        store.credentialHeaderMatches(Uri.parse(AppConstants.pacmCheckUrl)),
        isTrue,
      );
    });

    test('服务端下发普通 Cookie 不会把裸头改写成另一份凭据', () async {
      final store = await _store('pacmtoken=first-token; uid=u1');
      final harness = _harness(store, (options) {
        if (_isCheck(options)) {
          return _json(
            '{"code":"000000"}',
            headers: {
              'set-cookie': [
                'mg_auth_sid=web-session; Path=/; Domain=.migu.cn',
                'other=tracking; Path=/; Domain=.migu.cn',
              ],
            },
          );
        }
        return _aliveCheck();
      });
      final api = harness.api;

      await api.checkSessionAlive(trigger: 'startup');
      await api.checkSessionAlive(trigger: 'manual');

      expect(store.credentials.pacmtoken, 'first-token');
      expect(store.credentialWriteStats.cookieWrites, 0);
      final second = harness.adapter.checks.last;
      expect(second.headers['pacmtoken'], 'first-token');
      expect(second.headers['Cookie'], allOf(contains('pacmtoken=first-token'), contains('mg_auth_sid=')));
    });

    test('服务端用 Set-Cookie 下发同名凭据时，两条通道一起换', () async {
      final store = await _store('pacmtoken=first-token; uid=u1');
      final harness = _harness(store, (options) {
        if (_isCheck(options)) {
          return _aliveCheck(
            setCookie: ['pacmtoken=third-token; Path=/; Domain=.migu.cn'],
          );
        }
        return _aliveCheck();
      });

      await harness.api.checkSessionAlive(trigger: 'startup');
      await harness.api.checkSessionAlive(trigger: 'manual');

      expect(store.credentials.pacmtoken, 'third-token');
      expect(store.credentialSource, 'set-cookie');
      final second = harness.adapter.checks.last;
      expect(second.headers['pacmtoken'], 'third-token');
      expect(second.headers['Cookie'], contains('pacmtoken=third-token'));
    });

    test('离开咪咕域名后两条通道都不带凭据', () async {
      final store = await _store('pacmtoken=p1; uid=u1');
      final harness = _harness(store, (_) => _json('{"code":"000000"}'));
      await harness.client.getRaw('https://cdn.example.com/other.js');

      final request = harness.adapter.requests.single;
      expect(request.headers['Cookie'], isNull);
      expect(request.headers['pacmtoken'], isNull);
      expect(request.headers['uid'], isNull);
    });
  });

  group('日志只留指纹', () {
    test('调试输出、导出文本与记录里都没有凭据原文', () async {
      final diagnostics = await _diagnostics();
      final store = await _store('pacmtoken=plain-imported-value; uid=u1');
      final harness = _harness(
        store,
        (options) {
          if (_isCheck(options)) {
            return _aliveCheck(
              rotatesTo: 'plain-rotated-value',
              setCookie: [
                'mg_auth_sid=plain-web-session; Path=/; Domain=.migu.cn',
              ],
            );
          }
          return _aliveCheck();
        },
        diagnostics: diagnostics,
      );
      final api = harness.api;

      final printed = <String>[];
      final previous = debugPrint;
      void capture(String? line, {int? wrapWidth}) {
        if (line != null) printed.add(line);
      }
      debugPrint = capture;
      addTearDown(() => debugPrint = previous);

      await api.checkSessionAlive(trigger: 'startup');

      final records = await diagnostics.load();
      final exported = await diagnostics.exportText(now: DateTime(2026, 10, 26));
      final all = [
        ...printed,
        exported,
        ...records.map((record) => record.toJson().toString()),
      ].join('\n');

      for (final secret in [
        'plain-imported-value',
        'plain-rotated-value',
        'plain-web-session',
      ]) {
        expect(all, isNot(contains(secret)));
      }
      // 但要看得到「拿哪一份去问、写回后换成了哪一份」。
      expect(exported, contains('凭证: 探测前='));
      expect(
        printed.any((line) => line.contains('登录探测 startup → alive')),
        isTrue,
      );
      expect(store.credentialSource, 'rotation');
      expect(store.credentialFingerprint, isNot(contains('plain')));
    });
  });
}
