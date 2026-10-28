import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/auth/web_session_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const String _aCookie =
    'uid=u-a; pacmtoken=pacm-a; mg_auth_sid=s-a; mg_auth_pacmtoken=web-a';
const String _bCookie =
    'uid=u-b; pacmtoken=pacm-b; mg_auth_sid=s-b; mg_auth_pacmtoken=web-b';

class _StoredCookie {
  _StoredCookie({required this.value, required this.domain, required this.path});

  String value;
  final String domain;
  final String path;
}

/// 内存版播放器 profile，行为与 Windows 上可用的
/// `getCookies(url:)` / `setCookie` / `deleteAllCookies` 对齐。
class _FakePlayerProfile implements PlayerProfileCookies {
  final Map<String, _StoredCookie> _cookies = {};
  int deletes = 0;
  bool failDelete = false;

  String? valueOf(String name) => _cookies[name]?.value;

  bool get isEmpty => _cookies.isEmpty;

  void set(String name, String value, {String path = '/'}) {
    _cookies[name] = _StoredCookie(value: value, domain: '.migu.cn', path: path);
  }

  @override
  Future<List<PlayerCookie>> read(Uri url) async {
    return [
      for (final entry in _cookies.entries)
        if (_matches(url, entry.value))
          PlayerCookie(
            name: entry.key,
            value: entry.value.value,
            domain: entry.value.domain,
          ),
    ];
  }

  bool _matches(Uri url, _StoredCookie cookie) {
    final host = url.host.toLowerCase();
    final domain = cookie.domain.toLowerCase();
    if (domain.startsWith('.')) {
      if (host != domain.substring(1) && !host.endsWith(domain)) return false;
    } else if (host != domain) {
      return false;
    }
    final path = url.path.isEmpty ? '/' : url.path;
    return path.startsWith(cookie.path);
  }

  @override
  Future<bool> write(
    Uri url, {
    required String name,
    required String value,
    required String path,
  }) async {
    _cookies[name] = _StoredCookie(value: value, domain: '.migu.cn', path: path);
    return true;
  }

  @override
  Future<bool> deleteAll() async {
    if (failDelete) return false;
    deletes++;
    _cookies.clear();
    return true;
  }
}

Future<MiguCookieStore> _open(FakeSecureCookieStorage storage) async {
  final store = MiguCookieStore(secureStorage: storage);
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('官方播放器 profile 的代际隔离（P1-1）', () {
    test('登录后播种当前会话，正常的网页续签仍能回收', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      final token = store.webSyncToken;

      await WebSessionSync.seedPlayer(store, profile: profile);
      expect(
        (
          sentinel: profile.valueOf('migugo_web_sync'),
          pacmtoken: profile.valueOf('pacmtoken'),
          sid: profile.valueOf('mg_auth_sid'),
          deletes: profile.deletes,
        ),
        (sentinel: token, pacmtoken: 'pacm-a', sid: 's-a', deletes: 0),
      );

      profile.set('mg_auth_sid', 's-a-renewed');
      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);

      expect(
        (
          changed: changed,
          sid: store.loginSnapshot['mg_auth_sid'],
          pacmtoken: store.loginSnapshot['pacmtoken'],
        ),
        (changed: 1, sid: 's-a-renewed', pacmtoken: 'pacm-a'),
      );
    });

    test('退出后主动清空播放器 profile，回收不会复活登录', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      await store.clearLoginCookies();
      await WebSessionSync.clearPlayerProfile(profile: profile);
      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);

      expect(
        (
          empty: profile.isEmpty,
          deletes: profile.deletes,
          changed: changed,
          hasLogin: store.hasImportedLogin,
        ),
        (empty: true, deletes: 1, changed: 0, hasLogin: false),
      );
    });

    test('已退出时重新打开播放器会清掉残留的旧 profile', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      await store.clearLoginCookies();
      await WebSessionSync.seedPlayer(store, profile: profile);

      expect(
        (
          empty: profile.isEmpty,
          deletes: profile.deletes,
          sentinel: profile.valueOf('migugo_web_sync'),
        ),
        (empty: true, deletes: 1, sentinel: null),
      );
    });

    test('换号后播种先清空旧 profile，再写入新账号', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      final tokenOfB = store.webSyncToken;
      expect(
        (
          deletes: profile.deletes,
          sentinel: profile.valueOf('migugo_web_sync'),
          pacmtoken: profile.valueOf('pacmtoken'),
          sid: profile.valueOf('mg_auth_sid'),
          webPacmtoken: profile.valueOf('mg_auth_pacmtoken'),
          hasA: profile.valueOf('pacmtoken') == 'pacm-a',
        ),
        (
          deletes: 1,
          sentinel: tokenOfB,
          pacmtoken: 'pacm-b',
          sid: 's-b',
          webPacmtoken: 'pacm-b',
          hasA: false,
        ),
      );

      profile.set('mg_auth_sid', 's-b-renewed');
      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);
      expect(
        (changed: changed, sid: store.loginSnapshot['mg_auth_sid']),
        (changed: 1, sid: 's-b-renewed'),
      );
    });

    test('同一会话重复播种不会清掉页面自己的其它 Cookie', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);
      profile.set('custom_web_cookie', 'keep');

      await WebSessionSync.seedPlayer(store, profile: profile);

      expect(
        (
          deletes: profile.deletes,
          custom: profile.valueOf('custom_web_cookie'),
          sid: profile.valueOf('mg_auth_sid'),
        ),
        (deletes: 0, custom: 'keep', sid: 's-a'),
      );
    });

    test('旧 profile 清理失败时不写入新账号，回收也被拒绝', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);
      final tokenOfA = store.webSyncToken;

      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);
      profile.failDelete = true;

      await WebSessionSync.seedPlayer(store, profile: profile);
      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);

      expect(
        (
          sentinel: profile.valueOf('migugo_web_sync'),
          profilePacmtoken: profile.valueOf('pacmtoken'),
          changed: changed,
          storePacmtoken: store.loginSnapshot['mg_auth_pacmtoken'],
          storeSid: store.loginSnapshot['mg_auth_sid'],
          tokenOfA: tokenOfA,
        ),
        (
          sentinel: tokenOfA,
          profilePacmtoken: 'pacm-a',
          changed: 0,
          storePacmtoken: 'pacm-b',
          storeSid: 's-b',
          tokenOfA: tokenOfA,
        ),
      );
    });

    test('profile 仍是旧代际时，回收不写回新账号', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      await store.clearLoginCookies();
      await store.importLoginCookies(_bCookie);

      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);

      expect(
        (
          changed: changed,
          pacmtoken: store.loginSnapshot['mg_auth_pacmtoken'],
          sid: store.loginSnapshot['mg_auth_sid'],
        ),
        (changed: 0, pacmtoken: 'pacm-b', sid: 's-b'),
      );
    });

    test('退出后 profile 清理失败，回收仍无法复活登录', () async {
      final store = await _open(FakeSecureCookieStorage());
      final profile = _FakePlayerProfile();
      await store.importLoginCookies(_aCookie);
      await WebSessionSync.seedPlayer(store, profile: profile);

      await store.clearLoginCookies();
      profile.failDelete = true;
      await WebSessionSync.seedPlayer(store, profile: profile);
      final changed = await WebSessionSync.harvestPlayer(store, profile: profile);

      expect(
        (
          changed: changed,
          hasLogin: store.hasImportedLogin,
          profilePacmtoken: profile.valueOf('pacmtoken'),
        ),
        (changed: 0, hasLogin: false, profilePacmtoken: 'pacm-a'),
      );
    });
  });
}
