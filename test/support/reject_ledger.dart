import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可以自己拨针的时钟：确认失效要求两次被拒隔过 `confirmGap`，测试不能真等 30 分钟。
class StepClock {
  StepClock([DateTime? start]) : now = start ?? DateTime(2026, 10, 24, 9);

  DateTime now;

  DateTime read() => now;

  void advance(Duration by) => now = now.add(by);
}

/// 只讲计数规则的账本：不挂偏好，落盘规则由账本自己的用例覆盖。
///
/// widget 测试的假异步时钟里不能 await 偏好通道，会卡在 `did not complete`。
(SessionRejectLedger, StepClock) testLedger({
  Duration gap = const Duration(minutes: 30),
}) {
  final clock = StepClock();
  return (SessionRejectLedger(clock: clock.read, confirmGap: gap), clock);
}

/// 挂真实偏好的账本，用来验证跨重启能读回。
Future<SessionRejectLedger> prefsLedger(StepClock clock) async => SessionRejectLedger(
  prefs: await SharedPreferences.getInstance(),
  clock: clock.read,
);

/// 账号接口（用户资料）回绝本机凭据。
void noteAccountRejection(
  SessionRejectLedger ledger, {
  int status = 401,
  String code = '',
  String info = '',
}) {
  ledger.note(
    uri: Uri.parse('https://app.c.nf.migu.cn/user/h5/user-info/v1.0'),
    loginScoped: true,
    status: status,
    code: code,
    info: info,
  );
}

/// 歌词这类不要求登录的接口回 401：只留证据，不参与失效判定。
void notePublicRejection(SessionRejectLedger ledger, {int status = 401}) {
  ledger.note(
    uri: Uri.parse('https://m.music.migu.cn/migu/remoting/lyric_read'),
    loginScoped: false,
    status: status,
  );
}
