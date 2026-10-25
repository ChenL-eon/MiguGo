import 'package:flutter/material.dart';

/// 桌面歌词的可选颜色；深色浮层下都保持足够对比度。
enum DesktopLyricsColor {
  white('白色', Color(0xFFFFFFFF)),
  gold('金色', Color(0xFFFFD166)),
  mint('薄荷', Color(0xFF7BE3C3)),
  blue('天蓝', Color(0xFF8BC4FF)),
  pink('粉色', Color(0xFFFFA8C5)),
  silver('银灰', Color(0xFFB9BEC9));

  const DesktopLyricsColor(this.label, this.color);

  final String label;
  final Color color;

  static DesktopLyricsColor fromName(
    String? name, {
    DesktopLyricsColor fallback = DesktopLyricsColor.white,
  }) {
    return values.firstWhere((value) => value.name == name, orElse: () => fallback);
  }
}

/// 桌面歌词的描边；默认不描边。
enum DesktopLyricsStroke {
  none('无', null),
  black('黑色', Color(0xE6000000)),
  white('白色', Color(0xE6FFFFFF)),
  blue('蓝色', Color(0xE62F6BFF)),
  red('红色', Color(0xE6E05562));

  const DesktopLyricsStroke(this.label, this.color);

  final String label;

  /// 为空表示不描边，原生侧收到 alpha 为 0 的颜色后跳过描边绘制。
  final Color? color;

  static DesktopLyricsStroke fromName(String? name) {
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => DesktopLyricsStroke.none,
    );
  }
}
