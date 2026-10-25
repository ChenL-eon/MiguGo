import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机设备标识：随请求头自动上报，用来把同一账号的多端会话区分开。
///
/// Android 读取 `Settings.Secure.ANDROID_ID`（同一设备 + 同一签名下稳定），
/// 其余平台在首次启动时生成随机 UUID 并落盘。咪咕没有 refresh token，
/// 这个标识只用于设备区分，不参与任何登录签名计算，也不读取 IMEI 等敏感信息。
class DeviceIdentity {
  DeviceIdentity._();

  static const MethodChannel _channel = MethodChannel('migu_lele/device');
  static const String _cacheKey = 'migu_device_uuid_v1';

  static String? _cached;

  /// 稳定标识；同一台机器多次调用返回同一个值。
  static Future<String> current() async {
    final cached = _cached;
    if (cached != null) return cached;
    final id = await _load();
    _cached = id;
    return id;
  }

  /// 测试与热重载后重新取值时使用。
  @visibleForTesting
  static void reset() => _cached = null;

  static Future<String> _load() async {
    if (Platform.isAndroid) {
      try {
        final androidId = await _channel.invokeMethod<String>('androidId');
        if (androidId != null && androidId.isNotEmpty) return androidId;
      } catch (_) {
        // 原生通道不可用（例如单元测试环境）时退回落盘 UUID。
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cacheKey);
      if (saved != null && saved.isNotEmpty) return saved;
      final fresh = _randomUuid();
      await prefs.setString(_cacheKey, fresh);
      return fresh;
    } catch (_) {
      // 偏好存储不可用也不能阻断请求，本次运行内用一个临时标识即可。
      return _randomUuid();
    }
  }

  /// 用 [Random.secure] 手搓 UUID v4，避免为一次性取号引入 uuid 依赖。
  static String _randomUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
