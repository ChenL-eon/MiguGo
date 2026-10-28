import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  SessionProbeRecord record(int index) => SessionProbeRecord(
    at: DateTime(2026, 10, 25, 15, index),
    trigger: 'probe-$index',
    verdict: SessionProbe.alive,
    officialStatus: 200,
    officialCode: '000000',
  );

  test('导出文本包含轮换与过期元数据', () async {
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
    );

    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 25, 15),
        trigger: 'keep-alive',
        verdict: SessionProbe.alive,
        officialStatus: 200,
        officialCode: '000000',
        rotationHeader: true,
        rotated: true,
        expiryBefore: DateTime(2026, 10, 25, 15, 30),
        expiryFromResponse: DateTime(2026, 11, 24, 15, 30),
      ),
    );

    final text = await diagnostics.exportText(now: DateTime(2026, 10, 25, 16));

    expect(text, contains('keep-alive'));
    expect(text, contains('HTTP 200'));
    expect(text, contains('code=000000'));
    expect(text, contains('轮换: 响应头=有, 本地已更换=是'));
    expect(text, contains('2026-11-24'));
  });

  test('续期记录只写结果，不套探测那几行', () async {
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
    );

    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 26, 8),
        trigger: SessionProbeDiagnostics.renewalTrigger,
        verdict: SessionProbe.alive,
        rotated: true,
        note: '换到新凭据并写回，计数清零，状态回到已验证',
      ),
    );
    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 26, 8, 5),
        trigger: SessionProbeDiagnostics.renewalTrigger,
        verdict: SessionProbe.revoked,
        note: '咪咕明确回绝这张票据',
      ),
    );
    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 26, 12, 12),
        trigger: SessionProbeDiagnostics.renewalTrigger,
        verdict: SessionProbe.unknown,
        officialStatus: 200,
        officialCode: '199999',
        note: '咪咕答了但分不清票据问题还是服务抖动',
      ),
    );
    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 26, 12, 55),
        trigger: SessionProbeDiagnostics.renewalTrigger,
        verdict: SessionProbe.unknown,
        officialStatus: 200,
        officialInfo: '非 JSON',
        note: '咪咕答了但分不清票据问题还是服务抖动',
      ),
    );

    final text = await diagnostics.exportText();

    expect(text, contains('2026-10-26 08:00:00  renewal  →  alive'));
    expect(text, contains('续期: 本机已换新凭据=是'));
    expect(text, contains('结果: 换到新凭据并写回，计数清零，状态回到已验证'));
    expect(text, contains('2026-10-26 08:05:00  renewal  →  revoked'));
    expect(text, contains('续期: 本机已换新凭据=否'));
    expect(text, contains('结果: 咪咕明确回绝这张票据'));
    // 「分不清」这一档只有配上 HTTP 状态与票据码才可读，否则风控与票据过期长得一样。
    expect(text, contains('续期: 本机已换新凭据=否, HTTP 200, 票据码 199999'));
    // 续期没有「官方返回码」这一说，套用探测的排版只会读出无意义的 HTTP 未调用。
    expect(text, isNot(contains('官方:')));
    expect(text, isNot(contains('过期:')));
  });

  test('服务端文案里的疑似凭据内容会被省略', () async {
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
    );

    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 25, 15),
        trigger: 'startup',
        verdict: SessionProbe.unknown,
        officialStatus: 200,
        officialCode: '850002',
        officialInfo: 'token=SECRET_TOKEN_VALUE_1234567890',
        note: 'pacmtoken=SECRET_TOKEN_VALUE_1234567890',
      ),
    );

    final records = await diagnostics.load();
    expect(records.single.officialInfo, isNot(contains('SECRET')));
    expect(records.single.note, isNot(contains('SECRET')));
    final text = await diagnostics.exportText();
    expect(text, isNot(contains('SECRET_TOKEN_VALUE_1234567890')));
  });

  test('记录按上限滚动，并可从偏好恢复', () async {
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
      maxEntries: 3,
    );

    for (var index = 0; index < 5; index++) {
      await diagnostics.record(record(index));
    }

    final restored = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
      maxEntries: 3,
    );
    final records = await restored.load();

    expect(records, hasLength(3));
    expect(records.map((item) => item.trigger), [
      'probe-2',
      'probe-3',
      'probe-4',
    ]);
  });

  test('关闭记录时不写偏好', () async {
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: false,
    );

    await diagnostics.record(record(0));

    expect(await diagnostics.load(), isEmpty);
    expect(preferences.getString(SessionProbeDiagnostics.storageKey), isNull);
  });
}
