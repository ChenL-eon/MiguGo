import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../services/platform/window_theme.dart';

/// 把 Flutter 实际生效的主题同步给原生窗口与系统状态栏。
class WindowChrome extends StatefulWidget {
  const WindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> {
  Brightness? _appliedBrightness;
  Color? _appliedCaption;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final caption =
        theme.extension<AppPalette>()?.background ??
        (brightness == Brightness.dark
            ? AppPalette.dark.background
            : AppPalette.light.background);
    if (_appliedBrightness == brightness && _appliedCaption == caption) return;
    _appliedBrightness = brightness;
    _appliedCaption = caption;
    unawaited(WindowThemeService.applyBase(brightness: brightness, caption: caption));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: context.palette.background,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: widget.child,
    );
  }
}

/// 整屏自定义背景的页面用它接管原生标题栏配色，离开时自动还原。
class WindowCaptionOverride extends StatefulWidget {
  const WindowCaptionOverride({
    super.key,
    required this.brightness,
    required this.caption,
    required this.child,
  });

  final Brightness brightness;
  final Color caption;
  final Widget child;

  @override
  State<WindowCaptionOverride> createState() => _WindowCaptionOverrideState();
}

class _WindowCaptionOverrideState extends State<WindowCaptionOverride> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(WindowCaptionOverride oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption != widget.caption ||
        oldWidget.brightness != widget.brightness) {
      _apply();
    }
  }

  void _apply() {
    unawaited(
      WindowThemeService.pushOverride(
        brightness: widget.brightness,
        caption: widget.caption,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(WindowThemeService.popOverride());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
