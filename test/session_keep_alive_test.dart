import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/session_keep_alive.dart';
import 'package:migu_lele/services/auth/session_probe.dart';

/// 用毫秒级间隔替换默认的 45-75 分钟，测试里不可能真的等那么久。
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

  test('允许后台时，隐藏到托盘仍然继续保活；判死之后 stop 依旧不再排期', () async {
    var calls = 0;
    final keepAlive = _build(
      result: (_) {
        calls++;
        return SessionProbe.alive;
      },
    )
      ..allowsBackground = true
      ..restart();

    keepAlive.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await _waitUntil(() => calls > 0);

    keepAlive.stop();
    final afterStop = calls;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, afterStop);
    expect(keepAlive.isArmed, isFalse);
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

  for (final background in [false, true]) {
    testWidgets('频繁切换焦点不推迟保活，托盘=$background', (tester) async {
      var calls = 0;
      final keepAlive = SessionKeepAlive(
        probe: () async {
          calls++;
          return SessionProbe.alive;
        },
        minInterval: const Duration(hours: 1),
        maxInterval: const Duration(hours: 1),
        clock: tester.binding.clock.now,
      )
        ..allowsBackground = background
        ..restart();
      addTearDown(keepAlive.dispose);

      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(minutes: 10));
        keepAlive.didChangeAppLifecycleState(
          i.isEven ? AppLifecycleState.inactive : AppLifecycleState.resumed,
        );
      }
      expect(calls, 4);
      keepAlive.dispose();
    });
  }

  testWidgets('后台逾期后恢复立即检查一次，不重新等完整间隔', (tester) async {
    var calls = 0;
    final keepAlive = SessionKeepAlive(
      probe: () async {
        calls++;
        return SessionProbe.alive;
      },
      minInterval: const Duration(hours: 1),
      maxInterval: const Duration(hours: 1),
      clock: tester.binding.clock.now,
    )..restart();
    addTearDown(keepAlive.dispose);

    keepAlive.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(hours: 4));
    expect(calls, 0);
    keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 59));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
    keepAlive.dispose();
  });

  testWidgets('短暂隐藏恢复后保留原定剩余时间', (tester) async {
    var calls = 0;
    final keepAlive = SessionKeepAlive(
      probe: () async {
        calls++;
        return SessionProbe.alive;
      },
      minInterval: const Duration(hours: 1),
      maxInterval: const Duration(hours: 1),
      clock: tester.binding.clock.now,
    )..restart();
    addTearDown(keepAlive.dispose);

    await tester.pump(const Duration(minutes: 40));
    keepAlive.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 10));
    keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 9));
    expect(calls, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    keepAlive.dispose();
  });

  for (final dispose in [false, true]) {
    testWidgets('在途探测结束后不唤醒已停止的调度，dispose=$dispose', (tester) async {
      final pending = Completer<SessionProbe>();
      var calls = 0;
      var callbacks = 0;
      final keepAlive = SessionKeepAlive(
        probe: () {
          calls++;
          return pending.future;
        },
        onAlive: () => callbacks++,
        onRevoked: () => callbacks++,
        minInterval: const Duration(hours: 1),
        maxInterval: const Duration(hours: 1),
        clock: tester.binding.clock.now,
      )..restart();
      addTearDown(keepAlive.dispose);
      await tester.pump(const Duration(hours: 1));
      expect(calls, 1);
      if (dispose) {
        keepAlive.dispose();
      } else {
        keepAlive.stop();
      }
      pending.complete(SessionProbe.alive);
      await tester.pump();
      keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(hours: 2));
      expect(callbacks, 0);
      expect(calls, 1);
      expect(keepAlive.isArmed, isFalse);
    });
  }

  testWidgets('在途时重新排期不并发探测，也不采用重启前的结论', (tester) async {
    final pending = Completer<SessionProbe>();
    var calls = 0;
    var revoked = 0;
    final keepAlive = SessionKeepAlive(
      probe: () {
        calls++;
        return calls == 1 ? pending.future : Future.value(SessionProbe.alive);
      },
      onRevoked: () => revoked++,
      minInterval: const Duration(hours: 1),
      maxInterval: const Duration(hours: 1),
      clock: tester.binding.clock.now,
    )..restart();
    addTearDown(keepAlive.dispose);
    await tester.pump(const Duration(hours: 1));
    keepAlive.restart();
    for (var i = 0; i < 4; i++) {
      keepAlive.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(minutes: 30));
      keepAlive.didChangeAppLifecycleState(AppLifecycleState.resumed);
    }
    expect(calls, 1);
    pending.complete(SessionProbe.revoked);
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(revoked, 0);
    expect(calls, 2);
    expect(keepAlive.isArmed, isTrue);
    keepAlive.dispose();
  });

  test('默认 45-75 分钟间隔：启动后不会立刻打网络', () async {
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
