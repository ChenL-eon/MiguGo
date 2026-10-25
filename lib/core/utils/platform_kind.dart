import 'dart:io';

import 'package:flutter/foundation.dart';

/// 桌面端判定：Windows / macOS / Linux 这类有鼠标的环境。
///
/// 桌面端列表行用双击播放，避免浏览列表时误触换歌；触屏端仍然单击即播。
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Android 专属 UI 的入口判定。
///
/// 手机布局只认平台，不认窗口宽度：Windows 最小窗口约 920 宽，
/// 若按宽度切换会让窄窗误用手机样式。
bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;
