import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/web_session_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final FutureOr<ResponseBody> Function(RequestOptions options) reply;
  final List<RequestOptions> requests = [];

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

ResponseBody _json(String text, {int status = 200}) => ResponseBody.fromString(
  text,
  status,
  headers: {
    'content-type': [Headers.jsonContentType],
  },
);

Future<MiguCookieStore> _store(String cookie) async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  await store.importLoginCookies(cookie);
  return store;
}

/// 只按名字与域名返回固定内容的播放器 profile，用来验证回收的域名收口。
class _FixedProfile implements PlayerProfileCookies {
  _FixedProfile(this.cookies);

  final List<PlayerCookie> cookies;
  final List<String> written = [];
  int deletes = 0;

  @override
  Future<List<PlayerCookie>> read(Uri url) async => cookies;

  @override
  Future<bool> write(
    Uri url, {
    required String name,
    required String value,
    required String path,
  }) async {
    written.add('$name@$path');
    return true;
  }

  @override
  Future<bool> deleteAll() async {
    deletes++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('凭据外发边界', () {
    test('uid / pacmtoken / msisdn 只发给咪咕域名', () async {
      final adapter = _StubAdapter((_) => _json('{"code":"000000"}'));
      final client = MiguApiClient(
        dio: Dio()..httpClientAdapter = adapter,
        cookieStore: await _store('uid=u1; pacmtoken=p1; msisdn=13800000000'),
      );

      await client.getJson('https://app.c.nf.migu.cn/MUS/lyric/read');
      await client.getJson('https://lyric-host.example.com/some/song.lrc');

      expect(adapter.requests, hasLength(2));
      final migu = adapter.requests.first.headers;
      expect(migu['uid'], 'u1');
      expect(migu['pacmtoken'], 'p1');

      final foreign = adapter.requests.last.headers;
      expect(foreign.containsKey('uid'), isFalse, reason: '凭据不能跟着地址出咪咕域');
      expect(foreign.containsKey('pacmtoken'), isFalse);
      expect(foreign.containsKey('msisdn'), isFalse);
      expect(foreign.containsKey('Cookie'), isFalse);
    });
  });

  group('前台保活探测的凭据要求', () {
    test('只有 pacmtoken 也发一次探测（原生登录不带 uid）', () async {
      final adapter = _StubAdapter((_) => _json('{"code":"290001","info":"请先登录"}'));
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()..httpClientAdapter = adapter,
          cookieStore: await _store('pacmtoken=p1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.revoked);
      expect(adapter.requests, isNotEmpty, reason: '资料接口本来就不要求 uid');
    });

    test('缺 pacmtoken 时仍然不发请求', () async {
      final adapter = _StubAdapter((_) => _json('{"code":"000000"}'));
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()..httpClientAdapter = adapter,
          cookieStore: await _store('uid=u1'),
        ),
      );

      expect(await api.checkSessionAlive(), SessionProbe.unknown);
      expect(adapter.requests, isEmpty);
    });
  });

  group('播放器会话回收的域名收口', () {
    test('域名不是 migu.cn 后缀的会话 Cookie 不回收', () async {
      final store = await _store('pacmtoken=pacm-a; mg_auth_sid=s-a');
      final token = store.webSyncToken;
      expect(token, isNotNull);
      final profile = _FixedProfile([
        PlayerCookie(name: 'migugo_web_sync', value: token!, domain: '.migu.cn'),
        // 名字对、值对，但挂在仿冒域上：不能写进本机凭据快照。
        const PlayerCookie(
          name: 'mg_auth_sid',
          value: 's-evil',
          domain: 'evil-migu.cn',
        ),
      ]);

      expect(await WebSessionSync.harvestPlayer(store, profile: profile), 0);
      expect(store.credentials.pacmtoken, 'pacm-a');
      expect(store.loginSnapshot['mg_auth_sid'], isNot('s-evil'));
    });

    test('咪咕域下的会话 Cookie 正常回收', () async {
      final store = await _store('pacmtoken=pacm-a; mg_auth_sid=s-a');
      final token = store.webSyncToken;
      final profile = _FixedProfile([
        PlayerCookie(name: 'migugo_web_sync', value: token!, domain: '.migu.cn'),
        const PlayerCookie(name: 'mg_auth_sid', value: 's-renewed', domain: '.migu.cn'),
      ]);

      expect(await WebSessionSync.harvestPlayer(store, profile: profile), 1);
      expect(store.loginSnapshot['mg_auth_sid'], 's-renewed');
    });
  });
}
