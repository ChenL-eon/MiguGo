import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _manualKey = 'migu_manual_cookies_v2';
const _jarKey = 'migu_cookie_jar_v2';
const _legacyManualKey = 'migu_manual_cookies_v1';
const _legacyJarKey = 'migu_cookie_jar_v1';
const _pendingKey = 'migu_logout_pending_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<MiguCookieStore> createStore(FakeSecureCookieStorage storage) async {
    final store = MiguCookieStore(secureStorage: storage);
    await store.init();
    return store;
  }

  Future<void> capture(
    MiguCookieStore store,
    String url,
    List<String> setCookies,
  ) async {
    final options = RequestOptions(path: url);
    final headers = Headers();
    headers.set('set-cookie', setCookies);
    await store.capture(
      Response<dynamic>(requestOptions: options, statusCode: 200, headers: headers),
    );
  }

  group('导入与优先级', () {
    test('首次导入后发送手动 Cookie，且不写入普通偏好设置', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);

      final count = await store.importLoginCookies('Cookie: uid=u1; token=t1');

      expect(count, 2);
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        'uid=u1; token=t1',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyManualKey), isNull);
      expect(prefs.getString(_legacyJarKey), isNull);
      expect(storage.values[_manualKey], contains('uid'));
      expect(storage.values[_jarKey], isNull);
    });

    test('只有通行证或统计类 Cookie 时不算持有登录会话', () async {
      final store = await createStore(FakeSecureCookieStorage());

      await store.importLoginCookies('passID=p1; task-session-id=t1');
      expect(store.hasImportedLogin, isTrue);
      expect(store.hasWebSessionCookie, isFalse);

      await store.importLoginCookies('mg_auth_sid=s1; uid=u1');
      expect(store.hasWebSessionCookie, isTrue);
    });

    test('服务端轮换同名 Cookie 时优先使用服务端值', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await store.importLoginCookies('uid=u1; token=old');

      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'token=server; Path=/; Domain=.migu.cn; Max-Age=3600',
      ]);

      final header = store.cookieHeaderFor(Uri.parse('https://music.migu.cn/'));
      expect(header, contains('token=server'));
      expect(header, isNot(contains('token=old')));
      expect(header, contains('uid=u1'));
    });

    test('服务端删除同名 Cookie 后，手动登录凭据仍然发送', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      await store.importLoginCookies('uid=u1; token=old');

      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'token=server; Path=/; Domain=.migu.cn; Max-Age=3600',
      ]);
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'token=; Path=/; Domain=.migu.cn; Max-Age=0',
      ]);

      // 罐子里已经没有可用值时不能继续压住手动快照，否则凭据会被永久抑制，
      // 表现为登录状态突然失效且只能重新导入。
      final header = store.cookieHeaderFor(Uri.parse('https://music.migu.cn/'));
      expect(header, contains('token=old'));
      expect(header, contains('uid=u1'));

      final restarted = await createStore(storage);
      final restartedHeader = restarted.cookieHeaderFor(
        Uri.parse('https://music.migu.cn/'),
      );
      expect(restartedHeader, contains('token=old'));
    });

    test('重新导入会清空旧会话并重置服务端管理记录', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await store.importLoginCookies('uid=old; token=old');
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'token=server; Path=/; Domain=.migu.cn',
        'extra=1; Path=/; Domain=.migu.cn',
      ]);

      await store.importLoginCookies('uid=new; token=new');

      final header = store.cookieHeaderFor(Uri.parse('https://music.migu.cn/'));
      expect(header, 'uid=new; token=new');
      expect(header, isNot(contains('extra')));
    });

    test('注销会被拒绝的非法 Cookie 头', () async {
      final store = await createStore(FakeSecureCookieStorage());
      expect(
        () => store.importLoginCookies('bad-name; token=1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => store.importLoginCookies('ok=1; bad=va;lue'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('网页会话回灌', () {
    test('只更新登录相关名称，忽略统计与设备 Cookie', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await store.importLoginCookies('mg_auth_sid=old; uid=u1');

      final changed = await store.refreshLoginCookies(const {
        'mg_auth_sid': 'fresh',
        'cookieid': 'anon-1',
        'migu-device-uuid': 'dev-1',
      }, webSyncToken: store.webSyncToken);

      expect(changed, 1);
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        'mg_auth_sid=fresh; uid=u1',
      );
    });

    test('空值不会覆盖已有凭据', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await store.importLoginCookies('pacmtoken=p1');

      final changed = await store.refreshLoginCookies(const {
        'pacmtoken': '',
      }, webSyncToken: store.webSyncToken);

      expect(changed, 0);
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        'pacmtoken=p1',
      );
    });

    test('回灌结果重启后仍然生效', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      await store.importLoginCookies('mg_auth_sid=old');

      await store.refreshLoginCookies(const {
        'mg_auth_sid': 'fresh',
      }, webSyncToken: store.webSyncToken);
      final restarted = await createStore(storage);

      expect(
        restarted.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        'mg_auth_sid=fresh',
      );
    });

    test('快照副本被读取用于写入网页 profile', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await store.importLoginCookies('mg_auth_sid=s1; uid=u1');

      expect(store.loginSnapshot, {'mg_auth_sid': 's1', 'uid': 'u1'});
      expect(() => store.loginSnapshot['uid'] = 'tampered', throwsUnsupportedError);
    });
  });

  group('Set-Cookie 语义', () {
    test('Domain、Path 与 Secure 限制发送范围', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'sid=1; Path=/api; Secure; Domain=.migu.cn',
      ]);

      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/api/song')),
        'sid=1',
      );
      expect(store.cookieHeaderFor(Uri.parse('https://music.migu.cn/other')), isNull);
      expect(store.cookieHeaderFor(Uri.parse('https://music.migu.cn/apix')), isNull);
      expect(store.cookieHeaderFor(Uri.parse('http://music.migu.cn/api/song')), isNull);
    });

    test('host-only Cookie 不发送给其他子域', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'anon=1; Path=/',
        'shared=2; Path=/; Domain=.migu.cn',
      ]);

      final sameHost = store.cookieHeaderFor(
        Uri.parse('https://app.u.nf.migu.cn/next'),
      );
      expect(sameHost, contains('anon=1'));
      expect(sameHost, contains('shared=2'));

      final otherHost = store.cookieHeaderFor(Uri.parse('https://music.migu.cn/'));
      expect(otherHost, isNot(contains('anon=1')));
      expect(otherHost, contains('shared=2'));
    });

    test('拒绝为其他域名写入 Cookie', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'evil=1; Path=/; Domain=evil.com',
      ]);
      expect(store.cookieHeaderFor(Uri.parse('https://app.u.nf.migu.cn/api')), isNull);
    });

    test('Expires 过期与 Max-Age 删除均生效', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'a=1; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
        'b=2; Path=/; Max-Age=0',
        'c=3; Path=/; Max-Age=3600',
      ]);
      expect(store.cookieHeaderFor(Uri.parse('https://app.u.nf.migu.cn/api')), 'c=3');
    });

    test('解析合并返回的多条 Set-Cookie', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'a=1; Path=/, b=2; Path=/',
      ]);
      final header = store.cookieHeaderFor(Uri.parse('https://app.u.nf.migu.cn/api'));
      expect(header, contains('a=1'));
      expect(header, contains('b=2'));
    });

    test('路径更长的 Cookie 排在前面', () async {
      final store = await createStore(FakeSecureCookieStorage());
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'token=root; Path=/',
        'token=api; Path=/api',
      ]);
      expect(
        store.cookieHeaderFor(Uri.parse('https://app.u.nf.migu.cn/api/x')),
        'token=api; token=root',
      );
    });
  });

  group('持久化与迁移', () {
    test('重启后恢复手动 Cookie 与服务端会话', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      await store.importLoginCookies('uid=u1; token=t1');
      await capture(store, 'https://app.u.nf.migu.cn/api', [
        'session=server; Path=/; Domain=.migu.cn',
      ]);

      final restarted = await createStore(storage);
      final header = restarted.cookieHeaderFor(Uri.parse('https://music.migu.cn/'));
      expect(header, contains('session=server'));
      expect(header, contains('uid=u1'));
      expect(header, contains('token=t1'));
    });

    test('旧版明文数据迁移成功后删除旧键', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'uid': 'legacy', 'token': 't'}),
        _legacyJarKey: jsonEncode([
          {'name': 'anon', 'value': '1', 'domain': 'app.u.nf.migu.cn'},
        ]),
      });
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyManualKey), isNull);
      expect(prefs.getString(_legacyJarKey), isNull);
      expect(storage.values[_manualKey], isNotNull);
      expect(storage.values[_jarKey], isNotNull);
      expect(
        store.cookieHeaderFor(Uri.parse('https://app.u.nf.migu.cn/')),
        contains('uid=legacy'),
      );
    });

    test('迁移写入失败时保留旧数据并给出警告，不回写明文', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'uid': 'legacy'}),
      });
      final storage = FakeSecureCookieStorage()..failWrites = true;
      final store = await createStore(storage);

      expect(store.storageWarning, isNotNull);
      expect(store.storageWarning, contains('迁移'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyManualKey), isNotNull);
      expect(storage.values[_manualKey], isNull);
      expect(store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')), 'uid=legacy');
    });

    test('安全存储不可读时仅临时读取旧数据，不尝试明文写入', () async {
      SharedPreferences.setMockInitialValues({
        _legacyManualKey: jsonEncode({'uid': 'legacy'}),
      });
      final storage = FakeSecureCookieStorage()..failReads = true;
      final store = await createStore(storage);

      expect(store.storageWarning, isNotNull);
      expect(storage.writeCount, 0);
      expect(store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')), 'uid=legacy');
    });

    test('损坏的旧数据不会把原始内容写进日志', () async {
      const marker = 'SECRET_COOKIE_MARKER_123';
      SharedPreferences.setMockInitialValues({_legacyManualKey: '{"$marker": '});

      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);

      await createStore(FakeSecureCookieStorage());

      expect(logs.join('\n'), isNot(contains(marker)));
      expect(logs, isNotEmpty);
    });
  });

  group('退出登录清除', () {
    test('手动快照与服务端会话一起清空，落盘两份都不留', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);

      await store.importLoginCookies('uid=u1; pacmtoken=old');
      await capture(store, 'https://music.migu.cn/api', [
        'mg_auth_sid=s2; Path=/; Domain=.migu.cn',
      ]);
      expect(store.hasWebSessionCookie, isTrue);

      await store.clearLoginCookies();

      expect(store.hasImportedLogin, isFalse);
      expect(store.importedCookieCount, 0);
      expect(store.hasWebSessionCookie, isFalse);
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/api')),
        isNull,
        reason: '退出后连请求头都不该再带上任何一份凭据',
      );
      expect(storage.values[_manualKey], isNull);
      expect(storage.values[_jarKey], isNull);
      expect(store.storageWarning, isNull);
    });

    test('本来就是未登录时清除不报错，也不留下空文件', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);

      await store.clearLoginCookies();

      expect(store.hasImportedLogin, isFalse);
      expect(storage.values, isEmpty);
    });
  });

  group('续期覆盖', () {
    test('新 pacmtoken 生效并清掉罐子里的旧值，其余会话 Cookie 保留', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      await store.importLoginCookies('uid=u1; pacmtoken=old; mg_auth_sid=sid-1');
      // 服务端此前轮换过一次，罐子里的值优先于快照。
      await capture(store, 'https://app.c.nf.migu.cn/api', [
        'pacmtoken=rotated-old; Path=/; Domain=.migu.cn',
      ]);
      expect(store.credentials.pacmtoken, 'rotated-old');

      await store.applyRenewedCredentials({'pacmtoken': 'renewed'});

      expect(store.credentials.pacmtoken, 'renewed');
      expect(store.hasWebSessionCookie, isTrue);
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        contains('mg_auth_sid=sid-1'),
      );
      expect(
        store.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        isNot(contains('rotated-old')),
      );
      expect(storage.values[_manualKey], contains('renewed'));
      expect(storage.values[_jarKey], isNot(contains('rotated-old')));
    });

    test('值没变时不做无谓写入', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      await store.importLoginCookies('pacmtoken=same');
      final writes = storage.writeCount;

      expect(await store.applyRenewedCredentials({'pacmtoken': 'same'}), 0);
      expect(storage.writeCount, writes);
    });
  });

  group('作废登录的条件清理', () {
    test('之后写入的同名凭据不会被旧快照清理掉', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      final first = await store.applyNativeLoginSession({
        'pacmtoken': 'same',
        'uid': 'u1',
      });
      final second = await store.applyNativeLoginSession({
        'pacmtoken': 'same',
        'uid': 'u1',
      });

      // 值完全相同，只能靠修订号区分这是后一次登录写入的凭据。
      expect(second.revision, isNot(first.revision));
      expect(
        await store.clearLoginCookiesIfUnchanged(
          snapshot: first.snapshot,
          revision: first.revision,
        ),
        isFalse,
      );
      expect(store.credentials.pacmtoken, 'same');
      expect(store.credentials.uid, 'u1');
      expect(storage.values[_manualKey], contains('same'));

      expect(
        await store.clearLoginCookiesIfUnchanged(
          snapshot: second.snapshot,
          revision: second.revision,
        ),
        isTrue,
      );
      expect(store.hasImportedLogin, isFalse);
      expect(storage.values[_manualKey], isNull);
    });

    test('清理的落盘失败仍清内存，但如实报告失败并留下退出意图', () async {
      final storage = FakeSecureCookieStorage();
      final store = await createStore(storage);
      final applied = await store.applyNativeLoginSession({'pacmtoken': 'p1'});
      storage.failDeletes = true;

      expect(
        await store.clearLoginCookiesIfUnchanged(
          snapshot: applied.snapshot,
          revision: applied.revision,
        ),
        isFalse,
        reason: '内存清空不代表磁盘撤回完成',
      );
      expect(store.hasImportedLogin, isFalse);
      expect(store.storageWarning, contains('撤回'));
      expect(
        storage.values[_manualKey],
        contains('p1'),
        reason: '删除失败时旧记录仍在磁盘上，界面需要据此提示',
      );
      expect(storage.values[_pendingKey], 'pending');

      storage.failDeletes = false;
      final restarted = await createStore(storage);
      expect(restarted.hasImportedLogin, isFalse);
      expect(storage.values, isEmpty);
    });
  });
}
