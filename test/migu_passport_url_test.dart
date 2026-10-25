import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/migu_passport_url.dart';

void main() {
  group('通行证全页登录地址', () {
    test('携带官方参数与回跳地址', () {
      final uri = Uri.parse(buildMiguPassportLoginUrl());

      expect(uri.scheme, 'https');
      expect(uri.host, 'passport.migu.cn');
      expect(uri.path, '/login');
      expect(uri.queryParameters['sourceid'], '220029');
      expect(uri.queryParameters['forceAuthn'], 'true');
      expect(uri.queryParameters['hideRegister'], '1');
      expect(uri.queryParameters['hideForgetPass'], '1');
      expect(uri.queryParameters.containsKey('callbackURL'), isFalse);

      final relayState = uri.queryParameters['relayState'];
      expect(relayState, isNotNull);
      final decoded =
          jsonDecode(utf8.decode(base64Decode(relayState!))) as Map<String, dynamic>;
      expect(decoded, {'callbackURL': miguMusicLoginCallbackUrl});
    });

    test('自定义回跳地址会写入 relayState', () {
      const callback = 'https://music.migu.cn/v5/#/musicLibrary';
      final uri = Uri.parse(buildMiguPassportLoginUrl(callbackUrl: callback));

      final relayState = uri.queryParameters['relayState'];
      final decoded =
          jsonDecode(utf8.decode(base64Decode(relayState!))) as Map<String, dynamic>;
      expect(decoded['callbackURL'], callback);
    });
  });
}
