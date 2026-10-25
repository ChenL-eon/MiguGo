import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/session_keep_alive.dart';
import 'package:migu_lele/services/auth/session_probe.dart';

class _Rig {
  int epoch = 0;
  int alive = 0;
  int revoked = 0;
  final List<Completer<SessionProbe>> probes = [];

  late final SessionKeepAlive keepAlive = SessionKeepAlive(
    probe: () {
      final gate = Completer<SessionProbe>();
      probes.add(gate);
      return gate.future;
    },
    onAlive: () => alive++,
    onRevoked: () => revoked++,
    sessionEpoch: () => epoch,
    minInterval: Duration.zero,
    maxInterval: Duration.zero,
  );
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '等待异步窗口超时');
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('前台保活探测的会话代数保护', () {
    test('切换会话后旧探测返回失效，不判定新会话失效', () async {
      final rig = _Rig();
      rig.keepAlive.restart();
      await _pumpUntil(() => rig.probes.length == 1);

      rig.epoch = 1;
      rig.probes.first.complete(SessionProbe.revoked);
      await _pumpUntil(() => rig.probes.length >= 2);

      expect(rig.revoked, 0);
      expect(rig.keepAlive.isArmed, isTrue);
      rig.keepAlive.dispose();
    });

    test('登出后旧探测返回失效，不触发失效回调', () async {
      final rig = _Rig();
      rig.keepAlive.restart();
      await _pumpUntil(() => rig.probes.length == 1);

      rig.epoch = 1;
      rig.keepAlive.stop();
      rig.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(rig.revoked, 0);
      expect(rig.keepAlive.isArmed, isFalse);
      rig.keepAlive.dispose();
    });

    test('当前会话探测返回失效仍触发失效回调并停摆', () async {
      final rig = _Rig();
      rig.keepAlive.restart();
      await _pumpUntil(() => rig.probes.length == 1);

      rig.probes.first.complete(SessionProbe.revoked);
      await _flush();

      expect(rig.revoked, 1);
      expect(rig.alive, 0);
      expect(rig.keepAlive.isArmed, isFalse);
      rig.keepAlive.dispose();
    });

    test('切换会话后旧探测返回存活，不刷新新会话的校验时间', () async {
      final rig = _Rig();
      rig.keepAlive.restart();
      await _pumpUntil(() => rig.probes.length == 1);

      rig.epoch = 1;
      rig.probes.first.complete(SessionProbe.alive);
      await _pumpUntil(() => rig.probes.length >= 2);

      expect(rig.alive, 0);
      expect(rig.revoked, 0);
      expect(rig.keepAlive.isArmed, isTrue);
      rig.keepAlive.dispose();
    });
  });
}
