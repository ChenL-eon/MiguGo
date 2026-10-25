import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/web_session_sync.dart';

void main() {
  group('网页会话同步的名称白名单', () {
    test('官方登录会话名称可以同步', () {
      expect(WebSessionSync.isSessionCookieName('mg_auth_sid'), isTrue);
      expect(WebSessionSync.isSessionCookieName('pacmtoken'), isTrue);
      expect(WebSessionSync.isSessionCookieName('mg_auth_pacmtoken'), isTrue);
      expect(WebSessionSync.isSessionCookieName('migu-utoken-sessionid'), isTrue);
      expect(WebSessionSync.isSessionCookieName(' MG_AUTH_UID '), isTrue);
    });

    test('统计与设备 Cookie 不参与同步，免得覆盖本机可用凭据', () {
      expect(WebSessionSync.isSessionCookieName('cookieid'), isFalse);
      expect(WebSessionSync.isSessionCookieName('migu-device-uuid'), isFalse);
      expect(WebSessionSync.isSessionCookieName('task-session-id'), isFalse);
      expect(WebSessionSync.isSessionCookieName('mg_uem_user_id_123'), isFalse);
      expect(WebSessionSync.isSessionCookieName('capsuleID'), isFalse);
      expect(WebSessionSync.isSessionCookieName(''), isFalse);
    });
  });
}
