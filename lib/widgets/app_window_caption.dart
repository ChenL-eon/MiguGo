import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 自绘的窗口控制条。
///
/// Windows 上原生标题栏已隐藏，整条都可以拖动窗口，右侧是最小化 / 最大化 / 关闭；
/// 背景保持透明，页面自己的底色（含侧栏）会直接延伸到窗口顶边，看不出分界。
class AppWindowCaption extends StatefulWidget {
  const AppWindowCaption({super.key});

  static const double height = 40;
  static const double buttonsWidth = 138;

  /// 只有 Windows 桌面端接管标题栏，其它端仍交给系统。
  static bool get managed => Platform.isWindows;

  @override
  State<AppWindowCaption> createState() => _AppWindowCaptionState();
}

class _AppWindowCaptionState extends State<AppWindowCaption> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (!AppWindowCaption.managed) return;
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    if (AppWindowCaption.managed) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } catch (error) {
      debugPrint('读取窗口最大化状态失败：$error');
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppWindowCaption.managed) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      height: AppWindowCaption.height,
      child: Row(
        children: [
          const Expanded(
            // 按住空白处即可拖动窗口，双击切换最大化；右侧按钮区不受影响。
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          WindowCaptionButton.minimize(
            brightness: brightness,
            onPressed: () => unawaited(windowManager.minimize()),
          ),
          _maximized
              ? WindowCaptionButton.unmaximize(
                  brightness: brightness,
                  onPressed: () => unawaited(windowManager.unmaximize()),
                )
              : WindowCaptionButton.maximize(
                  brightness: brightness,
                  onPressed: () => unawaited(windowManager.maximize()),
                ),
          WindowCaptionButton.close(
            brightness: brightness,
            onPressed: () => unawaited(windowManager.close()),
          ),
        ],
      ),
    );
  }
}
