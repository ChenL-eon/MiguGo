import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_shell_controller.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

/// Windows 应用内快捷键：空格播放 / 暂停。
///
/// 仅在应用窗口内生效；文本输入或带修饰键时自动让位。
/// 全局快捷键与系统媒体键分别由 GlobalHotkeyService 与 SMTC 处理。
class DesktopShortcuts extends StatefulWidget {
  const DesktopShortcuts({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopShortcuts> createState() => _DesktopShortcutsState();
}

class _DesktopShortcutsState extends State<DesktopShortcuts> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = Platform.isWindows;
    if (_enabled) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (_enabled) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.space) return false;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    if (_isTextInputFocused()) return false;
    if (context.read<AppShellController>().webLoginActive) return false;

    final settings = context.read<SettingsProvider>();
    if (!settings.inAppSpaceShortcutEnabled) return false;

    // 全局裸空格开启后交由系统热键统一处理，避免同一次按键触发两次。
    if (settings.globalSpaceHotkeyEnabled) {
      return false;
    }

    final player = context.read<PlayerProvider>();
    if (!player.hasSong) return false;

    unawaited(player.togglePlayPause());
    return true;
  }

  bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
