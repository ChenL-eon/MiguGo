import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _manualKey = 'migu_manual_cookies_v2';
const _jarKey = 'migu_cookie_jar_v2';
const _pendingKey = 'migu_logout_pending_v1';

const _aCookie = {'uid': 'u-a', 'pacmtoken': 'pacm-a'};
const _bCookie = 'uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b';

Future<MiguCookieStore> _open(FakeSecureCookieStorage storage) async {
  final store = MiguCookieStore(secureStorage: storage);
  await store.init();
  return store;
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

Future<void> _capture(
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

class _GatedStorage extends FakeSecureCookieStorage {
  String? _gateKey;
  Completer<void>? _gate;
  int gatedDeletes = 0;

  Completer<void> gateNextDelete(String key) {
    _gateKey = key;
    return _gate = Completer<void>();
  }

  @override
  Future<void> delete(String key) async {
    final gate = _gate;
    if (gate != null && key == _gateKey) {
      _gate = null;
      _gateKey = null;
      gatedDeletes++;
      await gate.future;
    }
    await super.delete(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P1-2 条件清理的持久化语义', () {
    test('条件清理命中旧快照但手动 Cookie 删不掉：不得报告成功，退出意图必须落盘', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);

      storage.failDeleteKeys.add(_manualKey);
      final durable = await store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );

      expect(store.hasImportedLogin, isFalse);
      expect(store.webSyncToken, isNull);
      final reopened = await _open(storage);
      expect(
        (
          durable: durable,
          marker: storage.values[_pendingKey],
          restartedUid: reopened.credentials.uid,
        ),
        (durable: false, marker: 'pending', restartedUid: null),
        reason: '内存清空不等于磁盘撤回：删除失败时必须失败并留下退出意图',
      );
      expect(store.storageWarning, contains('撤回'));
      expect(storage.values[_manualKey], contains('pacm-a'));

      storage.failDeleteKeys.clear();
      final cleaned = await _open(storage);
      expect(cleaned.hasImportedLogin, isFalse);
      expect(storage.values, isEmpty);
    });

    test('手动 Cookie 已删但 Cookie 罐删不掉：仍不得报告成功', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);
      await _capture(store, 'https://music.migu.cn/api', [
        'server_session=keep; Path=/; Domain=.migu.cn',
      ]);

      storage.failDeleteKeys.add(_jarKey);
      final durable = await store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );

      expect(
        (
          durable: durable,
          marker: storage.values[_pendingKey],
          manual: storage.values[_manualKey],
          jarKept: storage.values[_jarKey]?.contains('server_session'),
        ),
        (durable: false, marker: 'pending', manual: null, jarKept: true),
        reason: '两份凭据文件必须全部删除才算撤回完成',
      );
      expect(store.storageWarning, contains('撤回'));

      storage.failDeleteKeys.clear();
      final reopened = await _open(storage);
      expect(
        (
          hasLogin: reopened.hasImportedLogin,
          header: reopened.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
          manual: storage.values[_manualKey],
          jar: storage.values[_jarKey],
          marker: storage.values[_pendingKey],
        ),
        (hasLogin: false, header: null, manual: null, jar: null, marker: null),
      );
    });

    test('清理任务在途时完成新登录：新账号不被旧清理删除', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);

      final gate = storage.gateNextDelete(_manualKey);
      final cleanup = store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );
      await _pumpUntil(() => storage.gatedDeletes == 1);
      expect(store.hasImportedLogin, isFalse);

      final loginB = store.importLoginCookies(_bCookie);
      expect(store.credentials.uid, 'u-b');
      await _flush();

      gate.complete();
      final durable = await cleanup;
      await loginB;

      expect(
        (
          durable: durable,
          uid: store.credentials.uid,
          diskHasB: storage.values[_manualKey]?.contains('pacm-b'),
          marker: storage.values[_pendingKey],
        ),
        (durable: true, uid: 'u-b', diskHasB: true, marker: null),
      );

      final reopened = await _open(storage);
      expect(reopened.credentials.uid, 'u-b');
      expect(reopened.credentials.pacmtoken, 'pacm-b');
    });

    test('旧清理任务与新登录并发、新登录取失效：磁盘不得留下旧账号', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);

      storage.failWriteKeys.add(_manualKey);
      final cleanup = store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );
      final loginB = store.importLoginCookies(_bCookie);
      final durable = await cleanup;
      await loginB;

      expect(store.hasImportedLogin, isTrue);
      expect(store.credentials.uid, 'u-b');
      final reopened = await _open(storage);
      expect(
        (
          durable: durable,
          manualOnDisk: storage.values[_manualKey],
          marker: storage.values[_pendingKey],
          restartedUid: reopened.credentials.uid,
        ),
        (durable: true, manualOnDisk: null, marker: null, restartedUid: null),
        reason: '旧清理必须先撤回 A；B 只是没落盘，不能让 A 留在磁盘上',
      );
    });

    test('条件清理成功：内存、磁盘、退出意图全部清空，重启保持未登录', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);
      await _capture(store, 'https://music.migu.cn/api', [
        'server_session=keep; Path=/; Domain=.migu.cn',
      ]);

      final durable = await store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );

      expect(durable, isTrue);
      expect(store.hasImportedLogin, isFalse);
      expect(store.storageWarning, isNull);
      expect(storage.values, isEmpty);

      final reopened = await _open(storage);
      expect(reopened.hasImportedLogin, isFalse);
      expect(reopened.cookieHeaderFor(Uri.parse('https://music.migu.cn/')), isNull);

      await reopened.importLoginCookies(_bCookie);
      final afterLogin = await _open(storage);
      expect(afterLogin.credentials.uid, 'u-b');
      expect(afterLogin.credentials.pacmtoken, 'pacm-b');
      expect(storage.values[_pendingKey], isNull);
    });

    test('退出意图和旧凭据都无法落盘/删除：如实返回失败并提示重启可能恢复', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);

      storage.failWriteKeys.add(_pendingKey);
      storage.failDeleteKeys.add(_manualKey);
      final durable = await store.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );

      expect(store.hasImportedLogin, isFalse);
      expect(durable, isFalse);
      expect(storage.values[_pendingKey], isNull);
      expect(store.storageWarning, contains('撤回'));
      expect(store.storageWarning, contains('重启后可能恢复'));
      expect(storage.values[_manualKey], contains('pacm-a'));

      // 标记写不进、旧 Cookie 又删不掉时没有任何持久撤回手段；
      // 这个用例锁住“必须如实报告”的边界，而不是宣称已经安全。
      final reopened = await _open(storage);
      expect(reopened.credentials.uid, 'u-a');
    });

    test('条件清理失败后重新登录：新登录取代退出意图，重启只恢复新账号', () async {
      final storage = FakeSecureCookieStorage();
      final store = await _open(storage);
      final applied = await store.applyNativeLoginSession(_aCookie);

      storage.failDeleteKeys.add(_manualKey);
      expect(
        await store.clearLoginCookiesIfUnchanged(
          snapshot: applied.snapshot,
          revision: applied.revision,
        ),
        isFalse,
      );
      expect(storage.values[_pendingKey], 'pending');

      storage.failDeleteKeys.clear();
      await store.importLoginCookies(_bCookie);

      expect(store.credentials.uid, 'u-b');
      expect(storage.values[_pendingKey], isNull);
      expect(
        jsonDecode(storage.values[_manualKey]!),
        containsPair('pacmtoken', 'pacm-b'),
      );

      final reopened = await _open(storage);
      expect(reopened.hasImportedLogin, isTrue);
      expect(reopened.credentials.uid, 'u-b');
      expect(reopened.credentials.pacmtoken, 'pacm-b');
    });
  });
}
