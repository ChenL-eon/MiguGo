import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'session_probe.dart';

/// 前台保活：应用可见时每 45–75 分钟探一次登录态，尽早发现“会话已被咪咕吊销”。
///
/// 探测走 `MiguMusicApi.checkSessionAlive`：官方校验接口成功时可能下发新的
/// `pacmtoken`，应用会写回本机；它是否真的延长服务端有效期仍需真机验证。
/// 探测到失效才把结论交给上层，
/// 由账号层做两步判定；本类自身不续期、不自动重登。
/// 定时器只在有登录凭据时才挂载，退到后台暂停，回到前台恢复原定截止时间；
/// [allowsBackground] 置真时（桌面端隐藏到托盘）前后台一律继续排期。
/// 探测本身挂住时按 [probeTimeout] 收口成「未知」，绝不因为一次不返回的探测
/// 或一个抛错的回调而永久停摆。
class SessionKeepAlive with WidgetsBindingObserver {
  SessionKeepAlive({
    required this.probe,
    this.onAlive,
    this.onRevoked,
    this.sessionEpoch,
    Duration minInterval = const Duration(minutes: 45),
    Duration maxInterval = const Duration(minutes: 75),
    this.probeTimeout = const Duration(seconds: 120),
    Random? random,
    DateTime Function()? clock,
  }) : _min = minInterval,
       _max = maxInterval < minInterval ? minInterval : maxInterval,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  /// 一次登录态探测；生产环境传 `MiguMusicApi.checkSessionAlive`。
  ///
  /// 探测本身可能顺带写回官方轮换的 `pacmtoken`，但不会替用户重新登录。
  final Future<SessionProbe> Function() probe;

  /// 探测到凭据仍可用，用于刷新“最近一次校验时间”。
  final void Function()? onAlive;

  /// 探测到凭据已失效，用于把登录状态标为失效并提示重新登录。
  final void Function()? onRevoked;

  /// 当前登录凭据的代数；探测返回时若它已经变了，这次结论属于上一个会话。
  final int Function()? sessionEpoch;

  /// 单次探测的等待上限；超时只按「未知」处理，不影响登录状态。
  ///
  /// 咪咕接口的读超时是 20 秒，留足重试余地后仍挂住的基本是半开连接。
  final Duration probeTimeout;

  final Duration _min;
  final Duration _max;
  final Random _random;
  final DateTime Function() _clock;

  Timer? _timer;
  DateTime? _nextProbeAt;
  int _scheduleGeneration = 0;
  bool _armed = false;
  bool _foreground = true;
  bool _allowsBackground = false;
  bool _probing = false;
  bool _observing = false;

  /// 是否已排上队（登录后为 true，失效或登出后为 false）。
  bool get isArmed => _armed;

  /// 离开前台后是否继续保活。桌面端「关闭主窗口后常驻托盘」开启时由上层置真。
  bool get allowsBackground => _allowsBackground;

  set allowsBackground(bool value) {
    if (_allowsBackground == value) return;
    _allowsBackground = value;
    _sync();
  }

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
    stop();
  }

  /// 拿到新的登录凭据后重新排期。
  void restart() {
    _scheduleGeneration++;
    _armed = true;
    _timer?.cancel();
    _timer = null;
    _nextProbeAt = _clock().add(_nextDelay());
    _sync();
  }

  /// 登出或确认失效后永久停摆，直到下一次 [restart]。
  void stop() {
    _scheduleGeneration++;
    _armed = false;
    _timer?.cancel();
    _timer = null;
    _nextProbeAt = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌面端最小化、移动端切后台都算离开前台。
    _foreground =
        state != AppLifecycleState.paused && state != AppLifecycleState.hidden;
    _sync();
  }

  void _sync() {
    final onDuty = _foreground || _allowsBackground;
    if (!_armed || !onDuty || _probing) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    final now = _clock();
    _nextProbeAt ??= now.add(_nextDelay());
    final remaining = _nextProbeAt!.difference(now);
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, _runOnce);
  }

  /// 在 45–75 分钟之间抖动，避免每次启动都卡在同一个整点。
  Duration _nextDelay() {
    final span = _max.inMilliseconds - _min.inMilliseconds;
    if (span <= 0) return _min;
    return Duration(milliseconds: _min.inMilliseconds + _random.nextInt(span));
  }

  Future<void> _runOnce() async {
    _timer = null;
    _nextProbeAt = null;
    _probing = true;
    final generation = _scheduleGeneration;
    final epochOf = sessionEpoch;
    final epoch = epochOf?.call();
    var result = SessionProbe.unknown;
    try {
      result = await probe().timeout(probeTimeout);
    } on TimeoutException {
      // 探测挂死（连接建了不回、或对端半开）只算「未知」，等下一拍。
      debugPrint('登录态探测超过 $probeTimeout 未返回，按未知处理');
    } catch (error) {
      debugPrint('登录态探测异常，保持现有状态：$error');
    } finally {
      _probing = false;
    }
    if (!_armed) return;

    try {
      // 重启调度或换号后，旧探测只能恢复排期，不能再提交结论。
      if (_scheduleGeneration != generation ||
          (epochOf != null && epochOf() != epoch)) {
        return;
      }

      switch (result) {
        case SessionProbe.revoked:
          stop();
          onRevoked?.call();
        case SessionProbe.alive:
          onAlive?.call();
        case SessionProbe.unknown:
          break;
      }
    } catch (error) {
      // 回调抛错也不能把保活打死：这里只记一句，排期照旧。
      debugPrint('登录态保活处理探测结论时异常，继续排下一次：$error');
    } finally {
      // revoked 分支已 stop，此时 _armed 为假，_sync() 只会把排期收干净。
      _sync();
    }
  }
}
