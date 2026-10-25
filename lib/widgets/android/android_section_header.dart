import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// 手机端分组标题，可选右侧动作；标题与动作都保持 48dp 触控高度。
class AndroidSectionHeader extends StatelessWidget {
  const AndroidSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// 文字动作之外自定义右侧控件，例如分组标题旁的圆形播放全部按钮。
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final showAction = actionLabel != null && onAction != null;
    final action = showAction
        ? TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: palette.accent,
              minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
              padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.xs),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: AndroidTextStyles.action(palette.accent)),
                if (actionIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(actionIcon, size: AndroidSizes.smallIcon),
                ],
              ],
            ),
          )
        : null;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AndroidTextStyles.sectionTitle(palette.textPrimary),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AndroidSpacing.xxs),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AndroidTextStyles.caption(palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          ?action,
          ?trailing,
        ],
      ),
    );
  }
}
