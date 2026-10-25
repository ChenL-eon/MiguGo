import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 同步 Windows 原生标题栏：底色跟随当前页面，图标与文字隐藏，
/// 让标题栏看起来就是界面的一部分。
class WindowThemeService {
  const WindowThemeService._();

  static const MethodChannel _channel = MethodChannel('migu_lele/window_theme');

  // 与 windows/runner 里的初始底色保持一致，避免首帧出现色差。
  static Brightness _baseBrightness = Brightness.light;
  static Color _baseCaption = const Color(0xFFF4F7FC);
  static Brightness? _overrideBrightness;
  static Color? _overrideCaption;
  static bool _captionIconHidden = false;

  /// 应用整体底色，由 [WindowChrome] 在主题变化时推送。
  static Future<void> applyBase({
    required Brightness brightness,
    required Color caption,
  }) async {
    if (_baseBrightness == brightness && _baseCaption == caption) return;
    _baseBrightness = brightness;
    _baseCaption = caption;
    await _sync();
  }

  /// 整屏自定义背景的页面（播放页）临时接管标题栏配色。
  static Future<void> pushOverride({
    required Brightness brightness,
    required Color caption,
  }) async {
    _overrideBrightness = brightness;
    _overrideCaption = caption;
    await _sync();
  }

  static Future<void> popOverride() async {
    if (_overrideCaption == null) return;
    _overrideBrightness = null;
    _overrideCaption = null;
    await _sync();
  }

  static Future<void> _sync() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('setTitleBarTheme', <String, Object?>{
        'brightness': (_overrideBrightness ?? _baseBrightness).name,
        'caption': (_overrideCaption ?? _baseCaption).toARGB32() & 0x00FFFFFF,
      });
      if (!_captionIconHidden) {
        _captionIconHidden = true;
        await _channel.invokeMethod<void>('hideCaptionIcon');
      }
    } catch (error) {
      debugPrint('同步窗口标题栏主题失败：$error');
    }
  }
}
