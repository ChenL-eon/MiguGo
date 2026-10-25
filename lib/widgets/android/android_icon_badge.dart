import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// 彩色图标底板，用于我的页与设置页的功能分组。
class AndroidIconBadge extends StatelessWidget {
  const AndroidIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.iconSize = 20,
    this.radius = AndroidRadius.sm,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.palette.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}
