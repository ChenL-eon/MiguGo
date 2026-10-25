import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';

/// Windows 全局快捷键。
///
/// 默认注册 Ctrl+Alt+空格（播放/暂停）与 Ctrl+Alt+←/→（上一首/下一首）；
/// 应用内裸空格由 DesktopShortcuts 处理，硬件媒体键由系统媒体会话（SMTC）接收。
/// 全局裸空格会占用所有应用的输入，因此做成可选开关，默认关闭。
class GlobalHotkeyService {
  GlobalHotkeyService(this._player, this._settings);

  final PlayerProvider _player;
  final SettingsProvider _settings;

  HotKey? _bareSpaceKey;
  bool _initialized = false;

  static const previousShortcut = 'Ctrl + Alt + ←';
  static const nextShortcut = 'Ctrl + Alt + →';
  static const playPauseShortcut = 'Ctrl + Alt + 空格';
  static const bareSpaceShortcut = '空格';

  Future<void> initialize() async {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;
    try {
      await hotKeyManager.unregisterAll();
    } catch (error) {
      debugPrint('清理旧快捷键失败：$error');
    }

    await _register(
      HotKey(
        key: PhysicalKeyboardKey.arrowLeft,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      () => unawaited(_player.previous()),
    );
    await _register(
      HotKey(
        key: PhysicalKeyboardKey.arrowRight,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      () => unawaited(_player.next()),
    );
    await _register(
      HotKey(
        key: PhysicalKeyboardKey.space,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      () => unawaited(_player.togglePlayPause()),
    );

    if (_settings.globalSpaceHotkeyEnabled) {
      await _registerBareSpace();
    }
  }

  Future<void> setBareSpaceEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      await _settings.setGlobalSpaceHotkeyEnabled(enabled);
      return;
    }

    if (enabled) {
      final registered = await _registerBareSpace();
      if (!registered) {
        throw StateError('空格快捷键注册失败，可能已被其他程序占用。');
      }
    } else {
      await _unregisterBareSpace();
    }
    await _settings.setGlobalSpaceHotkeyEnabled(enabled);
  }

  Future<bool> _registerBareSpace() async {
    if (_bareSpaceKey != null) return true;
    _bareSpaceKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: const [],
      scope: HotKeyScope.system,
    );
    final registered = await _register(
      _bareSpaceKey!,
      () => unawaited(_player.togglePlayPause()),
    );
    if (!registered) {
      _bareSpaceKey = null;
    }
    return registered;
  }

  Future<void> _unregisterBareSpace() async {
    final key = _bareSpaceKey;
    _bareSpaceKey = null;
    if (key == null) return;
    try {
      await hotKeyManager.unregister(key);
    } catch (error) {
      debugPrint('注销空格快捷键失败：$error');
    }
  }

  Future<bool> _register(HotKey hotKey, VoidCallback callback) async {
    try {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) => callback());
      return true;
    } catch (error) {
      debugPrint('注册全局快捷键失败：$error');
      return false;
    }
  }
}
