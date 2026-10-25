import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const String _manualKey = 'migu_manual_cookies_v2';
const String _aCookie =
    'uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a; mg_auth_pacmtoken=web-a';
const String _bCookie =
    'uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b; mg_auth_pacmtoken=web-b';

/// 旧播放器 profile 在退出或换号后还能读到的 Cookie。
const Map<String, String> _staleHarvestOfA = {
  'pacmtoken': 'pacm-a',
  'mg_auth_sid': 's-a',
  'mg_auth_pacmtoken': 'web-a',
};

/// 只有网页会话名、没有核心凭据的旧回收结果。
const Map<String, String> _staleWebOnlyHarvestOfA = {
  'mg_auth_sid': 's-a',
  'mg_auth_pacmtoken': 'web-a',
};

class _GatedStorage extends FakeSecureCookieStorage {
  Completer<void>? _deleteGate;
  String? _deleteGateKey;
  int gatedDeletes = 0;

  Completer<void> gateNextDelete(String key) {
    _deleteGateKey = key;
    return _deleteGate = Completer<void>();
  }

  @override
  Future<void> delete(String key) async {
    final gate = _deleteGate;
    if (gate != null && key == _deleteGateKey) {
      _deleteGate = null;
      _deleteGateKey = null;
      gatedDeletes++;
      await gate.future;
    }
    await super.delete(key);
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('播放器 Cookie 回收竞态（P1-1）', () {
    test('正常退出成功后，回收残留的旧播放器 Cookie 不得恢复登录', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);

      await store.clearLoginCookies();
      expect(store.hasImportedLogin, isFalse);
      expect(storage.values[_manualKey], isNull);

      final changed = await store.refreshLoginCookies(_staleHarvestOfA);
      await _flush();

      final restarted = await _open(storage);
      expect(
        (
          changed: changed,
          hasLogin: store.hasImportedLogin,
          pacmtoken: store.credentials.pacmtoken,
          uid: store.credentials.uid,
          header: store.cookieHeaderFor(Uri.parse('https://music.migu.cn/v3/api/play')),
          disk: storage.values[_manualKey],
          restartedHasLogin: restarted.hasImportedLogin,
          restartedPacmtoken: restarted.credentials.pacmtoken,
        ),
        (
          changed: 0,
          hasLogin: false,
          pacmtoken: null,
          uid: null,
          header: null,
          disk: null,
          restartedHasLogin: false,
          restartedPacmtoken: null,
        ),
      );
    });

    test('退出清理尚未完成时，旧播放器回收不得写回内存或磁盘', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);

      final gate = storage.gateNextDelete(_manualKey);
      final signOut = store.clearLoginCookies();
      await _pumpUntil(() => storage.gatedDeletes == 1);
      expect(storage.values[_manualKey], isNotNull, reason: '前置条件：旧凭据的删除应被卡住，磁盘上仍有旧值');

      final harvest = store.refreshLoginCookies(_staleHarvestOfA);
      await _flush();
      final hasLoginWhilePending = store.hasImportedLogin;

      gate.complete();
      await signOut;
      final changed = await harvest;
      await _flush();

      final restarted = await _open(storage);
      expect(
        (
          hasLoginWhilePending: hasLoginWhilePending,
          changed: changed,
          hasLogin: store.hasImportedLogin,
          pacmtoken: store.credentials.pacmtoken,
          header: store.cookieHeaderFor(Uri.parse('https://music.migu.cn/v3/api/play')),
          disk: storage.values[_manualKey],
          restartedHasLogin: restarted.hasImportedLogin,
        ),
        (
          hasLoginWhilePending: false,
          changed: 0,
          hasLogin: false,
          pacmtoken: null,
          header: null,
          disk: null,
          restartedHasLogin: false,
        ),
      );
    });

    test('退出后换新账号，旧播放器的回收不得覆盖新账号', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);

      final changed = await store.refreshLoginCookies(_staleHarvestOfA);
      await _flush();

      final restarted = await _open(storage);
      expect(
        (
          changed: changed,
          pacmtoken: store.credentials.pacmtoken,
          uid: store.credentials.uid,
          sid: store.loginSnapshot['mg_auth_sid'],
          webPacmtoken: store.loginSnapshot['mg_auth_pacmtoken'],
          diskHasB: storage.values[_manualKey]?.contains('pacm-b'),
          restartedPacmtoken: restarted.credentials.pacmtoken,
          restartedSid: restarted.loginSnapshot['mg_auth_sid'],
        ),
        (
          changed: 0,
          pacmtoken: 'web-b',
          uid: 'u-b',
          sid: 's-b',
          webPacmtoken: 'web-b',
          diskHasB: true,
          restartedPacmtoken: 'web-b',
          restartedSid: 's-b',
        ),
      );
    });

    test('旧播放器只带回网页会话名时也不能改写新账号的网页会话', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);

      final changed = await store.refreshLoginCookies(_staleWebOnlyHarvestOfA);
      await _flush();

      final restarted = await _open(storage);
      expect(
        (
          changed: changed,
          pacmtoken: store.credentials.pacmtoken,
          sid: store.loginSnapshot['mg_auth_sid'],
          webPacmtoken: store.loginSnapshot['mg_auth_pacmtoken'],
          diskSid: storage.values[_manualKey]?.contains('"mg_auth_sid":"s-b"'),
          restartedSid: restarted.loginSnapshot['mg_auth_sid'],
        ),
        (
          changed: 0,
          pacmtoken: 'web-b',
          sid: 's-b',
          webPacmtoken: 'web-b',
          diskSid: true,
          restartedSid: 's-b',
        ),
      );
    });

    test('同一登录会话内，带当前代际的回收仍然写回', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      final token = store.webSyncToken;
      expect(token, isNotNull);

      final changed = await store.refreshLoginCookies(const {
        'mg_auth_sid': 's-a-renewed',
      }, webSyncToken: token);

      expect(
        (
          changed: changed,
          sid: store.loginSnapshot['mg_auth_sid'],
          pacmtoken: store.loginSnapshot['pacmtoken'],
          disk: storage.values[_manualKey]?.contains('s-a-renewed'),
        ),
        (changed: 1, sid: 's-a-renewed', pacmtoken: 'pacm-a', disk: true),
      );
    });

    test('不带代际或使用退出前的旧代际，回收一律拒绝', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      final tokenOfA = store.webSyncToken;

      final withoutToken = await store.refreshLoginCookies(const {
        'mg_auth_sid': 'no-token',
      });

      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);
      final withStaleToken = await store.refreshLoginCookies(
        _staleWebOnlyHarvestOfA,
        webSyncToken: tokenOfA,
      );

      expect(
        (
          withoutToken: withoutToken,
          withStaleToken: withStaleToken,
          sid: store.loginSnapshot['mg_auth_sid'],
          pacmtoken: store.credentials.pacmtoken,
        ),
        (withoutToken: 0, withStaleToken: 0, sid: 's-b', pacmtoken: 'web-b'),
      );
    });

    test('退出开始后同步代际立即失效，即使退出落盘尚未完成', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      final tokenOfA = store.webSyncToken;

      final gate = storage.gateNextDelete(_manualKey);
      final signOut = store.clearLoginCookies();
      await _pumpUntil(() => storage.gatedDeletes == 1);

      final harvest = store.refreshLoginCookies(
        _staleWebOnlyHarvestOfA,
        webSyncToken: tokenOfA,
      );
      gate.complete();
      await signOut;
      final changed = await harvest;
      await _flush();

      expect(
        (
          token: store.webSyncToken,
          changed: changed,
          hasLogin: store.hasImportedLogin,
          disk: storage.values[_manualKey],
        ),
        (token: null, changed: 0, hasLogin: false, disk: null),
      );
    });

    test('重启恢复登录会换新代际，上一轮进程的回收不能写回', () async {
      final storage = _GatedStorage();
      final store = await _open(storage);
      await store.importLoginCookies(_aCookie);
      final tokenOfA = store.webSyncToken;
      expect(tokenOfA, isNotNull);

      final restarted = await _open(storage);
      expect(restarted.webSyncToken, isNotNull);
      expect(restarted.webSyncToken, isNot(tokenOfA));

      final changed = await restarted.refreshLoginCookies(const {
        'mg_auth_sid': 'stale-after-restart',
      }, webSyncToken: tokenOfA);

      expect(
        (
          changed: changed,
          sid: restarted.loginSnapshot['mg_auth_sid'],
          pacmtoken: restarted.credentials.pacmtoken,
        ),
        (changed: 0, sid: 's-a', pacmtoken: 'web-a'),
      );
    });
  });
}
