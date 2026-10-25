import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const String _secureManualKey = 'migu_manual_cookies_v2';
const String _secureJarKey = 'migu_cookie_jar_v2';
const String _legacyManualKey = 'migu_manual_cookies_v1';
const String _legacyJarKey = 'migu_cookie_jar_v1';

const String _legacyPlain = '{"uid":"u-legacy","pacmtoken":"pacm-legacy"}';
const String _securePlain = '{"pacmtoken":"pacm-current"}';

/// 旧版明文记录已经迁进安全存储，但偏好里的明文键因为各种中断留了下来。
Future<({MiguCookieStore store, SharedPreferences prefs})> _open(
  FakeSecureCookieStorage storage,
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = MiguCookieStore(secureStorage: storage);
  await store.init();
  return (store: store, prefs: await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('旧版明文凭据兜底清理', () {
    test('安全存储已有凭据时，残留的旧明文键本次启动就被清掉', () async {
      final storage = FakeSecureCookieStorage()
        ..values[_secureManualKey] = _securePlain
        ..values[_secureJarKey] = '{"mg_auth_sid":"s-current"}';
      final h = await _open(storage, {
        _legacyManualKey: _legacyPlain,
        _legacyJarKey: '{"cookieid":"c-legacy"}',
      });

      expect(h.store.credentials.pacmtoken, 'pacm-current');
      expect(h.prefs.getString(_legacyManualKey), isNull, reason: '明文不能再留在偏好里');
      expect(h.prefs.getString(_legacyJarKey), isNull);
      expect(storage.values[_secureManualKey], _securePlain);
    });

    test('明文与安全存储内容一致时同样清掉残留', () async {
      final storage = FakeSecureCookieStorage()
        ..values[_secureManualKey] = _legacyPlain;
      final h = await _open(storage, {_legacyManualKey: _legacyPlain});

      expect(h.store.credentials.pacmtoken, 'pacm-legacy');
      expect(h.prefs.getString(_legacyManualKey), isNull);
    });

    test('安全存储读不通时保留明文：那是唯一一份可用凭据', () async {
      final storage = FakeSecureCookieStorage()
        ..values[_secureManualKey] = _securePlain
        ..failReads = true;
      final h = await _open(storage, {_legacyManualKey: _legacyPlain});

      expect(h.prefs.getString(_legacyManualKey), _legacyPlain);
      expect(h.store.storageWarning, contains('旧版'));
    });

    test('安全存储里没有凭据时不碰明文（正常迁移路径自己处理）', () async {
      final storage = FakeSecureCookieStorage();
      final h = await _open(storage, {_legacyManualKey: _legacyPlain});

      expect(h.store.credentials.pacmtoken, 'pacm-legacy');
      // 迁移成功后明文才该消失；这里验证迁移路径没被兜底逻辑破坏。
      expect(h.prefs.getString(_legacyManualKey), isNull);
      expect(storage.values[_secureManualKey], _legacyPlain);
    });
  });
}
