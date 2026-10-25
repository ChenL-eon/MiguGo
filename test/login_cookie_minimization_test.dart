import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/web_login_cookies.dart';

WebLoginCookie _cookie(String name, String value, {String domain = '.migu.cn'}) {
  return WebLoginCookie(name: name, value: value, domain: domain, path: '/');
}

/// 网页登录窗口的采集范围：隐私政策承诺「其余 Cookie 一概不取」，
/// 落盘的请求头就只能含登录凭据本身。
void main() {
  group('导入只取登录凭据 Cookie', () {
    test('统计与设备 Cookie 一项都不进导入请求头', () {
      final set = WebLoginCookieSet.fromCookies([
        _cookie('cookieId', 'device-id'),
        _cookie('task-session-id', 'analytics'),
        _cookie('migu-device-uuid', 'uuid'),
        _cookie('mg_uem_user_id_9fbe6599', 'u'),
        _cookie('passID', 'p1'),
      ]);

      expect(set.header, isNull, reason: '没有凭据时不该导出任何 Cookie');
    });

    test('只保留网页会话凭据、mg_auth_* 与同名账号字段', () {
      final set = WebLoginCookieSet.fromCookies([
        _cookie('cookieId', 'device-id'),
        _cookie('migu-device-uuid', 'uuid'),
        _cookie('pacmtoken', 'pacm'),
        _cookie('mg_auth_sid', 'sid'),
        _cookie('mg_auth_uid', 'auth-uid'),
        _cookie('uid', 'u2'),
        _cookie('msisdn', '13800000000'),
      ]);

      expect(
        set.header,
        'mg_auth_sid=sid; mg_auth_uid=auth-uid; msisdn=13800000000; '
        'pacmtoken=pacm; uid=u2',
      );
    });

    test('名称像凭证但不是官方会话的 Cookie 仍然不取', () {
      final set = WebLoginCookieSet.fromCookies([
        _cookie('sso_token', 'x'),
        _cookie('memberLevel', '1'),
        _cookie('mg_auth_pid', 'pid'),
      ]);

      expect(set.header, 'mg_auth_pid=pid');
      expect(set.hasAuthHint, isTrue);
    });
  });
}
