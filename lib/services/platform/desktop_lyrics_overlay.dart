import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生桌面歌词浮层的通道封装。
///
/// 浮层本身是 Win32 分层窗口，这里只负责推送重绘载荷、把按钮事件转达回 Dart。
class DesktopLyricsOverlay {
  DesktopLyricsOverlay({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'migu_lele/desktop_lyrics';

  final MethodChannel _channel;

  bool get supported => !kIsWeb && Platform.isWindows;

  Future<bool> show(Map<String, Object?> payload) => _invoke('show', payload);

  Future<bool> update(Map<String, Object?> payload) => _invoke('update', payload);

  Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (error) {
      debugPrint('关闭桌面歌词浮层失败：$error');
    } on MissingPluginException {
      // 非 Windows 构建里没有原生实现，忽略即可。
    }
  }

  /// [onEvent] 收到浮层控制条上的点击（含拖动结束后的位置）。
  void listen(void Function(String event, Map<Object?, Object?> arguments) onEvent) {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      onEvent(call.method, arguments is Map<Object?, Object?> ? arguments : const {});
      return null;
    });
  }

  void stopListening() {
    _channel.setMethodCallHandler(null);
  }

  Future<bool> _invoke(String method, Map<String, Object?> payload) async {
    try {
      final result = await _channel.invokeMethod<bool>(method, payload);
      return result ?? false;
    } on PlatformException catch (error) {
      debugPrint('桌面歌词浮层调用失败（$method）：$error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('桌面歌词浮层通道未注册（$method）：$error');
      return false;
    }
  }
}
