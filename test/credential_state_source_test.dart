import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _manualKey = 'migu_manual_cookies_v2';
const _jarKey = 'migu_cookie_jar_v2';
const _legacyManualKey = 'migu_manual_cookies_v1';
const _legacyJarKey = 'migu_cookie_jar_v1';

const _webHost = 'https://music.migu.cn/';
const _apiHost = 'https://app.c.nf.migu.cn/';

/// 原生登录只留这一份凭据；Windows 与 Android 拿到的是同一种集合。
const _nativeCookie = 'pacmtoken=native-a; uid=u-a';

/// 网页/浏览器导入会同时留下主名与 `mg_auth_*` 别名与网页会话。
const _webCookie =
    'uid=u-b; pacmtoken=web-b; mg_auth_sid=s-b; mg_auth_pacmtoken=web-b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureCookieStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = FakeSecureCookieStorage();
  });

  Future<MiguCookieStore> open() async {
    final store = MiguCookieStore(secureStorage: storage);
    await store.init();
    return store;
  }

  Future<void> capture(
    MiguCookieStore store,
    String url,
    List<String> setCookies,
  ) async {
    final headers = Headers();
    headers.set('set-cookie', setCookies);
    await store.capture(
      Response<dynamic>(
        requestOptions: RequestOptions(path: url),
        statusCode: 200,
        headers: headers,
      ),
    );
  }

  /// Cookie 头里某个名称的值，按出现顺序列出。
  List<String> headerValues(String? header, String name) {
    if (header == null) return const [];
    return [
      for (final pair in header.split(';'))
        if (pair.split('=').first.trim() == name)
          pair.substring(pair.indexOf('=') + 1).trim(),
    ];
  }

  group('认证凭证只有一个落点', () {
    test('Set-Cookie 更新认证凭证后，各处状态源一致', () async {
      final store = await open();
      await store.importLoginCookies('uid=u1; pacmtoken=old; mg_auth_pacmtoken=old');

      await capture(store, '${_apiHost}user/h5/user-info/v1.0', [
        'pacmtoken=fresh; Path=/; Domain=.migu.cn; Max-Age=3600',
      ]);

      expect(store.credentials.pacmtoken, 'fresh');
      expect(store.loginSnapshot['pacmtoken'], 'fresh');
      expect(store.loginSnapshot['mg_auth_pacmtoken'], 'fresh');
      expect(store.credentialSource, 'set-cookie');
      expect(store.credentialExpiresAt, isNotNull);

      // 罐子里不该再留凭证副本，否则它和被谁清掉两件事会互相矛盾。
      expect(storage.values[_jarKey], isNull);

      for (final url in [_webHost, _apiHost]) {
        final header = store.cookieHeaderFor(Uri.parse(url));
        expect(header, contains('pacmtoken=fresh'));
        expect(header, isNot(contains('old')));
        expect(store.credentialHeaderMatches(Uri.parse(url)), isTrue, reason: url);
      }

      final restarted = await open();
      expect(restarted.credentials.pacmtoken, 'fresh');
      expect(restarted.loginSnapshot['mg_auth_pacmtoken'], 'fresh');
      expect(restarted.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);
    });

    test('普通 Cookie 更新与删除不会碰认证凭证，也不会牵连其余 Cookie', () async {
      final store = await open();
      await store.importLoginCookies(_nativeCookie);

      await capture(store, '${_apiHost}api/a', [
        'anon=1; Path=/; Domain=.migu.cn',
        'session=s1; Path=/; Domain=.migu.cn',
      ]);
      expect(store.cookieHeaderFor(Uri.parse(_webHost)), contains('anon=1'));

      await capture(store, '${_apiHost}api/b', [
        'session=; Path=/; Domain=.migu.cn; Max-Age=0',
        'extra=2; Path=/; Domain=.migu.cn',
      ]);

      final header = store.cookieHeaderFor(Uri.parse(_webHost));
      expect(header, contains('anon=1'), reason: '留下的一条普通 Cookie 不能被牵连删掉');
      expect(header, contains('extra=2'));
      expect(header, isNot(contains('session')));
      expect(header, contains('pacmtoken=native-a'), reason: '认证凭证不受普通 Cookie 清理影响');
      expect(store.credentials.pacmtoken, 'native-a');
      expect(store.credentialWriteStats.cookieWrites, 0);
    });

    test('服务端删除同名凭证后，仍继续发送已轮换的那一份，不退回原始导入值', () async {
      final store = await open();
      await store.importLoginCookies('pacmtoken=imported');

      await capture(store, '${_apiHost}api/a', [
        'pacmtoken=rotated; Path=/; Domain=.migu.cn; Max-Age=3600',
      ]);
      expect(store.credentials.pacmtoken, 'rotated');

      await capture(store, '${_apiHost}api/b', [
        'pacmtoken=; Path=/; Domain=.migu.cn; Max-Age=0',
      ]);

      // 过期与删除只是 Cookie 语义，不能把本机凭据悄悄换成没重新验证过的旧值。
      expect(store.credentials.pacmtoken, 'rotated');
      expect(store.cookieHeaderFor(Uri.parse(_webHost)), 'pacmtoken=rotated');
      expect(store.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);
      expect(store.credentialWriteStats.deleteIgnored, 1);

      final restarted = await open();
      expect(restarted.credentials.pacmtoken, 'rotated');
    });

    test('升级前存在罐子里的凭证被接回快照，并且不再留在罐子里', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'uid': 'u1', 'pacmtoken': 'imported'}),
        _legacyJarKey: jsonEncode([
          {
            'name': 'pacmtoken',
            'value': 'jar-fresh',
            'domain': 'migu.cn',
            'path': '/',
            'hostOnly': false,
            'secure': true,
          },
        ]),
      });

      final store = await open();

      // 旧读法本来就是罐子里的值优先，升级前后发出去的必须是同一份。
      expect(store.credentials.pacmtoken, 'jar-fresh');
      expect(store.loginSnapshot['pacmtoken'], 'jar-fresh');
      expect(store.credentialSource, 'migrated');
      expect(store.cookieHeaderFor(Uri.parse(_webHost)), contains('pacmtoken=jar-fresh'));
      expect(store.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);

      final jar = storage.values[_jarKey];
      expect(jar, isNot(contains('jar-fresh')));
      expect(jar, isNot(contains('pacmtoken')));
    });

    test('罐子里已到期的凭证不会被当成更值的新凭据接回', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'pacmtoken': 'imported'}),
        _legacyJarKey: jsonEncode([
          {
            'name': 'pacmtoken',
            'value': 'jar-expired',
            'domain': 'migu.cn',
            'path': '/',
            'hostOnly': false,
            'secure': true,
            'expiresAt': '2020-01-01T00:00:00.000Z',
          },
        ]),
      });

      final store = await open();

      expect(store.credentials.pacmtoken, 'imported');
      expect(store.cookieHeaderFor(Uri.parse(_webHost)), 'pacmtoken=imported');
      expect(store.credentialExpiresAt, isNull);
      expect(storage.values[_jarKey], isNot(contains('jar-expired')));
    });
  });

  group('旧会话结果不得改写当前凭据', () {
    test('退出之后迟到的 Set-Cookie 不能把已删除的凭据恢复回来', () async {
      final store = await open();
      await store.importLoginCookies(_nativeCookie);
      await store.clearLoginCookies();

      await capture(store, '${_apiHost}api/late', [
        'pacmtoken=late-rotation; Path=/; Domain=.migu.cn',
      ]);

      expect(store.hasImportedLogin, isFalse);
      expect(store.credentials.pacmtoken, isNull);
      expect(store.cookieHeaderFor(Uri.parse(_webHost)), isNull);
      expect(store.credentialSource, 'none');
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_jarKey], isNull);
      expect(store.credentialWriteStats.rejections, 1);

      final restarted = await open();
      expect(restarted.hasImportedLogin, isFalse);
    });

    test('带着旧代际的轮换结果写不进新账号', () async {
      final store = await open();
      await store.importLoginCookies(_nativeCookie);
      final generationOfA = store.webSyncToken;
      expect(generationOfA, isNotNull);

      await store.importLoginCookies(_webCookie);

      final changed = await store.applyRenewedCredentials(
        {'pacmtoken': 'stale-from-a'},
        loginGeneration: generationOfA,
      );

      expect(changed, 0);
      expect(store.credentials.pacmtoken, 'web-b');
      expect(store.loginSnapshot['pacmtoken'], 'web-b');
      expect(store.credentialWriteStats.rejections, 1);
      expect(storage.values[_manualKey], contains('web-b'));
    });

    test('当前代际的轮换结果照常写回，主名与别名一起换', () async {
      final store = await open();
      await store.importLoginCookies(_webCookie);

      final changed = await store.applyRenewedCredentials(
        {'pacmtoken': 'renewed'},
        loginGeneration: store.webSyncToken,
      );

      expect(changed, greaterThan(0));
      expect(store.credentials.pacmtoken, 'renewed');
      expect(store.loginSnapshot['pacmtoken'], 'renewed');
      expect(store.loginSnapshot['mg_auth_pacmtoken'], 'renewed');
      expect(store.credentialSource, 'rotation');
      expect(store.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);
    });

    test('网页回收不再改写认证凭证', () async {
      final store = await open();
      await store.importLoginCookies(_webCookie);
      await store.applyRenewedCredentials(
        {'pacmtoken': 'rotated'},
        loginGeneration: store.webSyncToken,
      );

      final changed = await store.refreshLoginCookies(
        const {'mg_auth_pacmtoken': 'harvested-old', 'pacmtoken': 'harvested-old'},
        webSyncToken: store.webSyncToken,
      );

      expect(changed, 0);
      expect(store.credentials.pacmtoken, 'rotated');
      expect(store.credentialWriteStats.harvestSkips, 2);

      // 网页会话名照常回收，回收通道只是不再碰凭证。
      expect(
        await store.refreshLoginCookies(
          const {'mg_auth_sid': 'sid-fresh'},
          webSyncToken: store.webSyncToken,
        ),
        1,
      );
      expect(store.loginSnapshot['mg_auth_sid'], 'sid-fresh');
    });
  });

  group('内存与磁盘不一致时如实报告', () {
    test('安全存储写不进去时，不宣称凭据已经落盘', () async {
      storage.failWrites = true;
      final store = await open();
      await store.importLoginCookies(_nativeCookie);

      expect(store.hasImportedLogin, isTrue);
      expect(store.credentials.pacmtoken, 'native-a');
      expect(store.credentialStateIsDurable, isFalse);
      expect(store.storageWarning, isNotNull);
      expect(storage.values[_manualKey], isNull);

      final changed = await store.applyRenewedCredentials(
        {'pacmtoken': 'renewed'},
        loginGeneration: store.webSyncToken,
      );
      expect(changed, greaterThan(0));
      expect(store.credentials.pacmtoken, 'renewed');
      expect(store.credentialStateIsDurable, isFalse);

      // 恢复可写之后，下一次改写才重新宣称一致。
      storage.failWrites = false;
      expect(
        await store.applyRenewedCredentials(
          {'pacmtoken': 'persisted'},
          loginGeneration: store.webSyncToken,
        ),
        greaterThan(0),
      );
      expect(store.credentialStateIsDurable, isTrue);
      expect(storage.values[_manualKey], contains('persisted'));

      final restarted = await open();
      expect(restarted.credentials.pacmtoken, 'persisted');
    });

    test('落盘成功时凭据状态被宣称为一致', () async {
      final store = await open();
      expect(store.credentialStateIsDurable, isTrue);
      await store.importLoginCookies(_nativeCookie);
      expect(store.credentialStateIsDurable, isTrue);
      expect(store.storageWarning, isNull);
    });
  });

  group('两种真实登录集合的恢复与重新登录', () {
    test('原生登录（只有 pacmtoken）重启与重登后处处一致', () async {
      final store = await open();
      await store.importLoginCookies(_nativeCookie);
      expect(store.loginSnapshot.containsKey('mg_auth_pacmtoken'), isFalse,
          reason: '原生登录不该凭空多出一份别名副本');

      final restarted = await open();
      expect(restarted.credentials.pacmtoken, 'native-a');
      expect(restarted.credentialSource, 'restored');
      expect(restarted.credentialHeaderMatches(Uri.parse(_apiHost)), isTrue);

      await restarted.importLoginCookies('pacmtoken=native-a2');
      expect(restarted.credentials.pacmtoken, 'native-a2');
      expect(restarted.credentialSource, 'import');
      expect(restarted.credentialHeaderMatches(Uri.parse(_apiHost)), isTrue);
    });

    test('网页导入（主名+别名+会话）重启与重登后处处一致', () async {
      final store = await open();
      await store.importLoginCookies(_webCookie);
      expect(store.credentials.pacmtoken, 'web-b');
      expect(store.hasWebSessionCookie, isTrue);

      final restarted = await open();
      expect(restarted.credentials.pacmtoken, 'web-b');
      expect(restarted.loginSnapshot['mg_auth_sid'], 's-b');
      expect(restarted.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);
      final header = restarted.cookieHeaderFor(Uri.parse(_webHost));
      expect(headerValues(header, 'pacmtoken'), ['web-b']);
      expect(headerValues(header, 'mg_auth_pacmtoken'), ['web-b']);

      await restarted.importLoginCookies(
        'uid=u-c; pacmtoken=web-c; mg_auth_pacmtoken=web-c',
      );
      expect(restarted.credentials.pacmtoken, 'web-c');
      expect(restarted.loginSnapshot.containsKey('mg_auth_sid'), isFalse);
      expect(restarted.credentialHeaderMatches(Uri.parse(_webHost)), isTrue);
    });
  });
}
