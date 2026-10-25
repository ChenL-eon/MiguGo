import 'package:flutter/widgets.dart';

/// 把悬浮底栏占用高度传给页面，让滚动内容能给导航栏和迷你播放器留出空间。
///
/// 只有 Android 壳层会提供非零值；桌面与 Windows 窄窗路径下 [of] 返回 0。
class AndroidShellInset extends InheritedWidget {
  const AndroidShellInset({super.key, required this.bottom, required super.child});

  final double bottom;

  static double of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AndroidShellInset>()?.bottom ?? 0;
  }

  @override
  bool updateShouldNotify(AndroidShellInset oldWidget) => oldWidget.bottom != bottom;
}
