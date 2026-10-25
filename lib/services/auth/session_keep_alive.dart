import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'session_probe.dart';

/// 前台保活：应用可见时每 4–6 小时探一次登录态，尽早发现“会话已被咪咕吊销”。
///
/// 咪咕不发 refresh token，这里只做只读探测：探测到失效就把结论交给上层——
/// 账号层会先用原生登录留下的票据试一次静默续期，续不到才提示重新登录。
/// 本类自身不续期、不自动重登。
/// 定时器只在有登录凭据时才挂载，退到后台立即取消，回到前台重新排期。
class SessionKeepAlive with WidgetsBindingObserver {
  SessionKeepAlive({
    required this.probe,
    this.onAlive,
    this.onRevoked,
    this.sessionEpoch,
    Duration minInterval = const Duration(hours: 4),
    Duration maxInterval = const Duration(hours: 6),
    Random? random,
  }) : _min = minInterval,
       _max = maxInterval < minInterval ? minInterval : maxInterval,
       _random = random ?? Random.secure();

  /// 一次只读探测；生产环境传 `MiguMusicApi.checkSessionAlive`。
  final Future<SessionProbe> Function() probe;

  /// 探测到凭据仍可用，用于刷新“最近一次校验时间”。
  final void Function()? onAlive;

  /// 探测到凭据已失效，用于把登录状态标为失效并提示重新登录。
  final void Function()? onRevoked;

  /// 当前登录凭据的代数；探测返回时若它已经变了，这次结论属于上一个会话。
  final int Function()? sessionEpoch;

  final Duration _min;
  final Duration _max;
  final Random _random;

  Timer? _timer;
  bool _armed = false;
  bool _foreground = true;
  bool _probing = false;
  bool _observing = false;

  /// 是否已排上队（登录后为 true，失效或登出后为 false）。
  bool get isArmed => _armed;

  void attach() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    _timer?.cancel();
    _timer = null;
  }

  /// 拿到新的登录凭据后重新排期。
  void restart() {
    _armed = true;
    _sync();
  }

  /// 登出或确认失效后永久停摆，直到下一次 [restart]。
  void stop() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌面端最小化、移动端切后台都算离开前台。
    _foreground =
        state != AppLifecycleState.paused && state != AppLifecycleState.hidden;
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!_armed || !_foreground || _probing) return;
    _timer = Timer(_nextDelay(), _runOnce);
  }

  /// 在 4–6 小时之间抖动，避免每次启动都卡在同一个整点。
  Duration _nextDelay() {
    final span = _max.inMilliseconds - _min.inMilliseconds;
    if (span <= 0) return _min;
    return Duration(milliseconds: _min.inMilliseconds + _random.nextInt(span));
  }

  Future<void> _runOnce() async {
    _timer = null;
    _probing = true;
    final epochOf = sessionEpoch;
    final epoch = epochOf?.call();
    var result = SessionProbe.unknown;
    try {
      result = await probe();
    } catch (error) {
      debugPrint('登录态探测异常，保持现有状态：$error');
    } finally {
      _probing = false;
    }

    // 探测期间换号或退出时，这次结论属于上一个会话：既不能宣布新会话失效，
    // 也不能把新会话标成已验证，只把保活重新排到当前凭据上。
    if (epochOf != null && epochOf() != epoch) {
      _sync();
      return;
    }

    switch (result) {
      case SessionProbe.revoked:
        stop();
        onRevoked?.call();
      case SessionProbe.alive:
        onAlive?.call();
        _sync();
      case SessionProbe.unknown:
        _sync();
    }
  }
}
