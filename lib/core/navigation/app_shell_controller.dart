import 'package:flutter/foundation.dart';

/// 主框架当前选中的导航页与临时登录页状态。
///
/// 登录页位于主框架之上，登录完成后通过它切回首页再关闭登录页；
/// 临时 WebView 打开期间同时暂停应用内空格快捷键，避免输入被播放器截获。
class AppShellController extends ChangeNotifier {
  static const int settingsIndex = 3;

  int _index = 0;
  int _webLoginDepth = 0;
  int _desktopLyricsFocusTick = 0;

  int get index => _index;

  /// 每次自增都代表一次“滚到桌面歌词分组”的请求，设置页据此定位。
  int get desktopLyricsFocusTick => _desktopLyricsFocusTick;

  bool get webLoginActive => _webLoginDepth > 0;

  void select(int index) {
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }

  /// 浮层控制条上的设置按钮：切到设置页并定位到桌面歌词分组。
  void focusDesktopLyricsSettings() {
    _index = settingsIndex;
    _desktopLyricsFocusTick++;
    notifyListeners();
  }

  void enterWebLogin() {
    _webLoginDepth++;
    notifyListeners();
  }

  void leaveWebLogin() {
    if (_webLoginDepth == 0) return;
    _webLoginDepth--;
    notifyListeners();
  }
}
