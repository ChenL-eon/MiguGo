import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';

/// 桌面端「关闭主窗口后常驻托盘」。
///
/// 咪咕给每个 `pacmtoken` 只有签发后两小时命，应用一退就再没人去问服务端，
/// 关掉几小时必然要重新登录。开启后点窗口上的关闭只是把窗口藏起来，进程留着
/// 继续做同一件保活探测；要真退出用托盘菜单里的「退出」。
///
/// 只做 Windows：Android 没有托盘，后台进程会被系统回收，等价能力得另做前台服务。
class DesktopTrayService with WindowListener, TrayListener {
  DesktopTrayService({
    required this.onKeepAliveInBackground,
    required this.onWindowHidden,
  });

  /// 隐藏期间要不要继续保活，由调用方接到 [SessionKeepAlive.allowsBackground] 上。
  final void Function(bool enabled) onKeepAliveInBackground;

  /// 窗口收进托盘时要不要停下播放。用户点的是「关闭」，不是「静音」，
  /// 但让曲子从已经看不见界面的窗口里继续响会让人以为程序没关掉。
  final void Function() onWindowHidden;

  /// tray_manager 在 Windows 上按 `data/flutter_assets/<这个路径>` 找文件。
  static const String _iconPath = 'assets/tray/tray_icon.ico';

  bool _enabled = false;
  bool _quitting = false;

  /// 按开关装上或拆掉托盘。平台不支持时什么都不做，关闭行为保持原样。
  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows || _enabled == enabled) return;
    try {
      if (enabled) {
        // 托盘先挂上，再吞掉关闭：反过来的话，图标没出来（比如打包里少了那枚 .ico）
        // 而关闭已经被拦掉，用户把窗口一关就没有任何地方能把它唤回来了。
        await _addTray();
        await windowManager.setPreventClose(true);
        _enabled = true;
        onKeepAliveInBackground(true);
      } else {
        _enabled = false;
        onKeepAliveInBackground(false);
        await windowManager.setPreventClose(false);
        await _removeTray();
      }
    } catch (error) {
      _enabled = false;
      onKeepAliveInBackground(false);
      // 回到「关闭就是真退出」，别让半开的托盘留下一个吞掉的关闭。
      await windowManager.setPreventClose(false).catchError((Object _) {});
      await _removeTray().catchError((Object _) {});
      debugPrint('后台常驻没装起来，关闭行为保持原样：$error');
    }
  }

  Future<void> _addTray() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(_iconPath);
    await trayManager.setToolTip('${AppConstants.appName} 正在后台保持登录');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主界面'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出 ${AppConstants.appName}'),
        ],
      ),
    );
  }

  Future<void> _removeTray() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }

  /// 只在 preventClose 为真时收得到；此时原生侧已经吞掉这次关闭，藏窗口就行。
  @override
  void onWindowClose() {
    if (!_enabled || _quitting) return;
    onWindowHidden();
    unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() => unawaited(_reveal());

  /// Windows 上右键只发事件，菜单要应用自己弹。
  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_reveal());
      case 'quit':
        unawaited(_quit());
    }
  }

  Future<void> _reveal() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    _quitting = true;
    onKeepAliveInBackground(false);
    try {
      await _removeTray();
      await windowManager.destroy();
    } catch (error) {
      debugPrint('托盘退出失败：$error');
    }
    // 播放与全局热键插件都留有原生线程，只销毁窗口不足以让进程收干净。
    exit(0);
  }
}
