import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 页面级系统栏样式。
///
/// [statusIconBrightness] 描述图标自身的明暗：深色背景传 [Brightness.light]，
/// 浅色背景传 [Brightness.dark]。导航栏默认透明，配合 edge-to-edge 使用。
SystemUiOverlayStyle androidSystemUiStyle({
  required Brightness statusIconBrightness,
  Brightness? navigationIconBrightness,
  Color? navigationBarColor,
}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: statusIconBrightness,
    // iOS 与 Android 的状态栏亮度语义相反；保留正确值避免未来跨端误用。
    statusBarBrightness: statusIconBrightness == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    systemNavigationBarColor: navigationBarColor ?? Colors.transparent,
    systemNavigationBarIconBrightness: navigationIconBrightness ?? statusIconBrightness,
    systemNavigationBarDividerColor: Colors.transparent,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}
