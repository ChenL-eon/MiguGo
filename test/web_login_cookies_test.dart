import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/web_login_cookies.dart';

WebLoginCookie cookie(
  String name,
  String value, {
  String domain = '.migu.cn',
  String path = '/',
}) {
  return WebLoginCookie(name: name, value: value, domain: domain, path: path);
}

void main() {
  group('网页登录 Cookie 清洗', () {
    test('只保留 migu.cn 域下的合法 Cookie', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('uid', 'a'),
        cookie('evil', 'b', domain: 'example.com'),
        cookie('bad;name', 'c'),
        cookie('bad_value', 'x;y'),
      ]);

      expect(set.header, 'uid=a');
    });

    test('同名 Cookie 由更具体的域或路径优先', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('uid', 'root', domain: '.migu.cn', path: '/'),
        cookie('uid', 'host', domain: 'music.migu.cn', path: '/'),
        cookie('uid', 'deep', domain: '.music.migu.cn', path: '/listen'),
      ]);

      expect(set.length, 1);
      expect(set.header, 'uid=deep');
    });

    test('同名 pacmtoken 跨域时导出音乐域凭据并保留 UI 统计', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('pacmtoken', 'music-value', domain: '.migu.cn'),
        cookie('pacmtoken', 'passport-value', domain: 'passport.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
      expect(set.header, 'pacmtoken=music-value');
      expect(set.length, 1);
      expect(set.cookieNames, ['pacmtoken']);
      expect(set.cookies.single.value, 'passport-value');
    });

    test('更具体域或路径的空值不覆盖有效凭据', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('pacmtoken', '', domain: 'music.migu.cn'),
        cookie('pacmtoken', 'valid'),
        cookie('mg_auth_sid', '', path: '/listen'),
        cookie('mg_auth_sid', 'session'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
      expect(set.header, 'mg_auth_sid=session; pacmtoken=valid');
      expect(set.length, 2);
    });

    test('只有空值凭据时不导出且保留名称统计', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('pacmtoken', ''),
        cookie('mg_auth_sid', '   '),
        cookie('cookieId', 'device'),
      ]);

      expect(set.header, isNull);
      expect(set.length, 3);
      expect(set.cookieNames, ['cookieId', 'mg_auth_sid', 'pacmtoken']);
    });

    test('请求头按名称稳定排序且不暴露重复名称', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_uid', '1'),
        cookie('mg_auth_pid', '2'),
        cookie('mg_auth_pid', '3', path: '/deep'),
      ]);

      expect(set.header, 'mg_auth_pid=3; mg_auth_uid=1');
    });

    test('空集合不生成请求头', () {
      final set = WebLoginCookieSet.fromCookies(const []);
      expect(set.isEmpty, isTrue);
      expect(set.header, isNull);
      expect(set.hasAuthHint, isFalse);
    });
  });

  group('登录完成检测', () {
    test('migu.cn 域下的登录会话 Cookie 视为登录完成', () {
      final set = WebLoginCookieSet.fromCookies([cookie('mg_auth_sid', 'sid-value')]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
      expect(set.hasAuthHint, isTrue);
    });

    test('官方网页的另一种会话 Cookie 同样有效', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('migu-utoken-sessionid', 'v', domain: 'music.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
    });

    test('pacmtoken 是原生 VIP 取链凭据，同样算登录完成', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('pacmtoken', 'p', domain: '.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
      expect(set.hasOfficialCookieFor('music.migu.cn'), isTrue);
    });

    test('统计与匿名会话 Cookie 不算登录完成', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('task-session-id', 'analytics'),
        cookie('cookieId', 'device'),
        cookie('migu-device-uuid', 'device'),
        cookie('_ga', '1'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isFalse);
    });

    test('只对通行证域生效的会话 Cookie 不算登录完成且不导出', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_sid', 'sid-value', domain: 'passport.migu.cn'),
        cookie('pacmtoken', 'passport-value', domain: 'passport.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isFalse);
      expect(set.hasWebSessionFor('passport.migu.cn'), isTrue);
      expect(set.header, isNull);
      expect(set.length, 2);
    });

    test('同名 Cookie 同时存在于两个域时按音乐域判定', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_sid', 'passport', domain: 'passport.migu.cn'),
        cookie('mg_auth_sid', 'web', domain: '.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isTrue);
      expect(set.length, 1);
    });

    test('会话 Cookie 值为空不算登录完成', () {
      final set = WebLoginCookieSet.fromCookies([cookie('mg_auth_sid', '')]);

      expect(set.hasWebSessionFor('music.migu.cn'), isFalse);
    });

    test('手动读取只认官方 mg_auth_* Cookie 作兜底', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_pid', 'p', domain: '.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isFalse);
      expect(set.hasOfficialCookieFor('music.migu.cn'), isTrue);
      expect(set.officialCookieNames, ['mg_auth_pid']);
    });

    test('匿名统计 Cookie 即使名称像凭证也不能兜底导入', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('task-session-id', 'x', domain: '.migu.cn'),
        cookie('mg_uem_user_id_9fbe6599400e43a4a58700a822fd57f8', 'y'),
        cookie('cookieId', 'z'),
      ]);

      expect(set.hasOfficialCookieFor('music.migu.cn'), isFalse);
      expect(set.hasAuthHint, isFalse);
    });

    test('只对通行证域生效的 Cookie 不能兜底导入', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_pid', 'p', domain: 'passport.migu.cn'),
      ]);

      expect(set.hasOfficialCookieFor('music.migu.cn'), isFalse);
      expect(set.hasOfficialCookieFor('passport.migu.cn'), isTrue);
    });

    test('通行证域下的会话 Cookie 不当作音乐登录', () {
      final set = WebLoginCookieSet.fromCookies([
        cookie('mg_auth_sid', 'p', domain: 'passport.migu.cn'),
        cookie('cookieId', 'c', domain: '.migu.cn'),
      ]);

      expect(set.hasWebSessionFor('music.migu.cn'), isFalse);
      expect(set.cookieNames, ['cookieId', 'mg_auth_sid']);
    });
  });
}
