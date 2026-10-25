import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';
import 'android_sheet.dart';

/// 底部面板里的一个单选项。
class AndroidChoiceOption<T> {
  const AndroidChoiceOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.swatch,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;
  final Color? swatch;
}

/// 打开手机习惯的单选面板：整行可点，选中项高亮并打勾，选择后自动关闭。
///
/// 用 [onSelected] 而不是返回值，是为了让 null 也能成为一个合法选项
/// （例如睡眠定时的「不开启」）。
Future<void> showAndroidChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<AndroidChoiceOption<T>> options,
  required T selected,
  required ValueChanged<T> onSelected,
}) {
  return showAndroidSheet<void>(
    context: context,
    title: title,
    subtitle: subtitle,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: AndroidSpacing.xxs),
            child: AndroidChoiceTile(
              option: option,
              selected: option.value == selected,
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                Navigator.of(sheetContext).pop();
                onSelected(option.value);
              },
            ),
          ),
      ],
    ),
  );
}

class AndroidChoiceTile<T> extends StatelessWidget {
  const AndroidChoiceTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AndroidChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AndroidRadius.sm);
    final tile = Container(
      constraints: const BoxConstraints(minHeight: AndroidSizes.touch),
      padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.sm, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: selected ? palette.accent.withValues(alpha: 0.35) : palette.line,
        ),
      ),
      child: Row(
        children: [
          if (option.swatch != null || option.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: AndroidSpacing.xs),
              child: SizedBox(
                width: 20,
                height: 20,
                child: option.swatch == null
                    ? Icon(option.icon, size: 18, color: palette.textSecondary)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: option.swatch,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AndroidTypeScale.listTitle,
                    fontWeight: FontWeight.w600,
                    color: selected ? palette.accent : palette.textPrimary,
                  ),
                ),
                if (option.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    option.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AndroidTypeScale.caption,
                      height: 1.4,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AndroidSpacing.xs),
          if (selected)
            Icon(Icons.check_circle_rounded, size: 20, color: palette.accent)
          else
            const SizedBox(width: 20),
        ],
      ),
    );
    return Material(
      color: selected ? palette.accentSoft : Colors.transparent,
      borderRadius: radius,
      child: InkWell(onTap: onTap, borderRadius: radius, child: tile),
    );
  }
}
