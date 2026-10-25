import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/reject_ledger.dart';

/// 删本机凭据不可逆，所以「被拒几次才算失效」这件事必须钉死在测试里。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('被拒计数的门槛', () {
    test('不要求登录的接口回 401 只留证据，不计数', () async {
      final (ledger, _) = testLedger();

      notePublicRejection(ledger);
      notePublicRejection(ledger, status: 403);

      expect(ledger.strikes, 0);
      expect(ledger.last, isNotNull);
      expect(ledger.last!.loginScoped, isFalse);
    });

    test('一波并发失败只算一次：间隔不足 confirmGap 不再计数', () async {
      final (ledger, clock) = testLedger();

      noteAccountRejection(ledger);
      clock.advance(const Duration(seconds: 20));
      noteAccountRejection(ledger);
      clock.advance(const Duration(minutes: 3));
      noteAccountRejection(ledger);

      expect(ledger.strikes, 1);
    });

    test('隔过 confirmGap 再次被拒才凑够两次', () async {
      final (ledger, clock) = testLedger();

      noteAccountRejection(ledger, status: 401);
      clock.advance(const Duration(minutes: 31));
      noteAccountRejection(ledger, code: '290001', info: '请先登录');

      expect(ledger.strikes, 2);
      expect(ledger.last!.code, '290001');
      expect(ledger.last!.info, '请先登录');
    });

    test('账号接口成功回包后旧账清零，但证据留着', () async {
      final (ledger, clock) = testLedger();
      noteAccountRejection(ledger);
      expect(ledger.strikes, 1);

      ledger.resetStrikes();
      clock.advance(const Duration(minutes: 40));
      noteAccountRejection(ledger);

      expect(ledger.strikes, 1);
      expect(ledger.last, isNotNull);
    });

    test('clear 连偏好里的那条记录一起抹掉', () async {
      final ledger = await prefsLedger(StepClock());
      noteAccountRejection(ledger);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('migu_last_session_reject_v1'), isNotNull);

      ledger.clear();
      await Future<void>.delayed(Duration.zero);

      expect(ledger.strikes, 0);
      expect(ledger.last, isNull);
      expect(prefs.getString('migu_last_session_reject_v1'), isNull);
      expect(prefs.getInt('migu_session_reject_strikes_v1'), isNull);
    });
  });

  group('证据的内容与持久化', () {
    test('一行结论带时间、地址、状态码与业务码', () async {
      final (ledger, _) = testLedger();
      noteAccountRejection(ledger, code: '290001', info: '请先登录');

      final summary = ledger.last!.summary;
      expect(summary, contains('09:00'));
      expect(summary, contains('app.c.nf.migu.cn/user/h5/user-info/v1.0'));
      expect(summary, contains('HTTP 401'));
      expect(summary, contains('编码 290001'));
      expect(summary, contains('请先登录'));
    });

    test('跨重启能读回上一条证据与计数', () async {
      final ledger = await prefsLedger(StepClock());
      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      await Future<void>.delayed(Duration.zero);

      final reopened = SessionRejectLedger();
      await reopened.init();

      expect(reopened.strikes, 1);
      expect(reopened.last!.path, '/user/h5/user-info/v1.0');
      expect(reopened.last!.info, '请先登录');
    });

    test('损坏的记录被忽略，不影响新的一次', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('migu_last_session_reject_v1', '{bad json');
      final ledger = SessionRejectLedger(prefs: prefs, clock: StepClock().read);
      await ledger.init();

      expect(ledger.last, isNull);
      expect(ledger.strikes, 0);
    });
  });

  group('服务端文案的过滤', () {
    test('正常文案原样保留', () {
      expect(SessionRejectLedger.sanitizeInfo('请先登录'), '请先登录');
      expect(SessionRejectLedger.sanitizeInfo('  '), '');
    });

    test('像凭据或带参数的一律省略，绝不落盘', () {
      expect(
        SessionRejectLedger.sanitizeInfo('token=abc123; uid=13800000000'),
        contains('已省略'),
      );
      expect(
        SessionRejectLedger.sanitizeInfo('请访问 https://passport.migu.cn/authn 重试'),
        contains('已省略'),
      );
      expect(
        SessionRejectLedger.sanitizeInfo('QWxvZ2luVG9rZW5FeGFtcGxlVmFsdWU='),
        contains('已省略'),
      );
    });

    test('过长的文案截断，不把状态说明撑爆', () {
      final long = '服务端返回了一段很长的说明文字' * 6;
      final result = SessionRejectLedger.sanitizeInfo(long);
      expect(result.length, lessThanOrEqualTo(49));
      expect(result, endsWith('…'));
    });
  });
}
