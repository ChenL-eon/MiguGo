import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.label,
    this.color,
    this.background,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final Color? background;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.palette.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: background ?? tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 11.5, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: dense ? 9.5 : 10.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
