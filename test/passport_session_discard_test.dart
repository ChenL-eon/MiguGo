import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';

import 'support/passport_stub.dart';

String _cookieOf(RequestOptions request) =>
    (request.headers['Cookie'] ?? '').toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('通行证会话只在本次登录内有效', () {
    test('验证码会话在登录过程中带上，登录收尾后不再发出去', () async {
      final adapter = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(adapter));

      await api.fetchGraphCaptcha(MiguImgcodeType.sms);
      await api.verifyGraphCaptcha(MiguImgcodeType.sms, 'ab12');
      // 取图与校验必须共用同一个验证码会话，所以这一步确实要带上它。
      expect(_cookieOf(adapter.requests.last), contains('mgnd_session_id'));

      await api.loginWithSmsCode('13800000000', '248157');
      // 下一次登录的第一步：上一份登录的验证码会话不该跟着出门。
      await api.fetchGraphCaptcha(MiguImgcodeType.password, refresh: true);
      expect(
        _cookieOf(adapter.requests.last),
        isNot(contains('mgnd_session_id')),
        reason: '隐私政策写明这张会话随本次登录结束丢弃',
      );
    });

    test('续期收尾后也丢弃通行证会话', () async {
      final adapter = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(adapter));

      await api.fetchGraphCaptcha(MiguImgcodeType.sms);
      await api.renewSession('STnidStubToken');
      await api.fetchGraphCaptcha(MiguImgcodeType.sms, refresh: true);

      expect(_cookieOf(adapter.requests.last), isNot(contains('mgnd_session_id')));
    });
  });
}
