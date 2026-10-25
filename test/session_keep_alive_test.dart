import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/session_keep_alive.dart';
import 'package:migu_lele/services/auth/session_probe.dart';

/// 用毫秒级间隔替换 4-6 小时，测试里不可能真的等那么久。
SessionKeepAlive _build({
  required SessionProbe Function(int call) result,
  void Function()? onAlive,
  void Function()? onRevoked,
  Duration minInterval = const Duration(milliseconds: 5),
  Duration maxInterval = const Duration(milliseconds: 10),
}) {
  var call = 0;
  return SessionKeepAlive(
    probe: () async => result(++call),
    onAlive: onAlive,
    onRevoked: onRevoked,
    minInterval: minInterval,
    maxInterval: maxInterval,
  );
}

Future<void> _waitUntil(bool Function() condition, {int timeoutMs = 1000}) async {
  var waited = 0;
  while (!condition() && waited < timeoutMs) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    waited += 5;
  }
  if (!condition()) fail('等待条件超时（${timeoutMs}ms）');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没有登录凭据时不排期，restart 之后才开始探测', () async {
    var calls = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.alive;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, 0);
    expect(keepAlive.isArmed, isFalse);

    keepAlive.restart();
    await _waitUntil(() => calls > 0);
    expect(keepAlive.isArmed, isTrue);
    keepAlive.dispose();
  });

  test('凭据仍有效时刷新状态并继续排下一次', () async {
    var calls = 0;
    var aliveHits = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.alive;
      },
      onAlive: () => aliveHits++,
    )..restart();

    // 探测计数会先于回调增长，等回调本身，避免读到刚发起第二次探测的瞬间。
    await _waitUntil(() => aliveHits >= 2);
    expect(calls, greaterThanOrEqualTo(2));
    expect(aliveHits, greaterThanOrEqualTo(2));
    expect(keepAlive.isArmed, isTrue);
    keepAlive.dispose();
  });

  test('探测到失效后永久停摆，只上报一次', () async {
    var calls = 0;
    var revokedHits = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.revoked;
      },
      onRevoked: () => revokedHits++,
    )..restart();

    await _waitUntil(() => revokedHits > 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(revokedHits, 1);
    expect(calls, 1);
    expect(keepAlive.isArmed, isFalse);
    keepAlive.dispose();
  });

  test('判不准或探测抛异常都不算失效，会继续排期', () async {
    var calls = 0;
    var revokedHits = 0;
    final keepAlive = _build(
      result: (call) {
        calls++;
        if (call == 1) throw StateError('探测炸了');
        return SessionProbe.unknown;
      },
      onRevoked: () => revokedHits++,
    )..restart();

    await _waitUntil(() => calls >= 2);
    expect(revokedHits, 0);
    expect(keepAlive.isArmed, isTrue);
    keepAlive.dispose();
  });

  test('退到后台取消定时器，回到前台重新排期', () async {
    var calls = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.alive;
      },
    )..restart();

    keepAlive.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, 0);

    keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _waitUntil(() => calls > 0);
    keepAlive.dispose();
  });

  test('stop 之后不会被前后台切换唤醒', () async {
    var calls = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.alive;
      },
    )..restart();

    keepAlive.stop();
    keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, 0);
    expect(keepAlive.isArmed, isFalse);
    keepAlive.dispose();
  });

  test('默认 4-6 小时间隔：启动后不会立刻打网络', () async {
    var calls = 0;
    final keepAlive = SessionKeepAlive(
      probe: () async {
        calls++;
        return SessionProbe.alive;
      },
    )..restart();

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 0);
    keepAlive.dispose();
  });
}
