import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/pages/official_login_page.dart';

void main() {
  group('登录窗口导航白名单', () {
    test('咪咕官方站点放行', () {
      expect(isAllowedLoginNavigation(Uri.parse('https://passport.migu.cn/')), isTrue);
      expect(isAllowedLoginNavigation(Uri.parse('https://music.migu.cn/v3/')), isTrue);
      expect(isAllowedLoginNavigation(Uri.parse('https://www.migu.cn/')), isTrue);
      expect(isAllowedLoginNavigation(Uri.parse('https://migu.cn/')), isTrue);
    });

    test('空白页与地址缺失放行，不影响 WebView 自身行为', () {
      expect(isAllowedLoginNavigation(null), isTrue);
      expect(isAllowedLoginNavigation(Uri.parse('about:blank')), isTrue);
    });

    test('离开咪咕域就拦下：不在本窗口里渲染别人的页面', () {
      expect(
        isAllowedLoginNavigation(Uri.parse('https://evil.example.com/login')),
        isFalse,
      );
      expect(isAllowedLoginNavigation(Uri.parse('https://migu.cn.evil.com/')), isFalse);
      expect(isAllowedLoginNavigation(Uri.parse('https://evil-migu.cn/')), isFalse);
      expect(isAllowedLoginNavigation(Uri.parse('http://passport.migu.cn/')), isFalse);
      expect(isAllowedLoginNavigation(Uri.parse('weixin://abc')), isFalse);
    });
  });
}
