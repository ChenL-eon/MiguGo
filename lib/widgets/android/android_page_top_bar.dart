import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// Android 二级页的紧凑顶栏：48dp 返回键、标题副标题与右侧动作。
class AndroidPageTopBar extends StatelessWidget {
  const AndroidPageTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AndroidSpacing.xxs,
        AndroidSpacing.xxs,
        AndroidSpacing.xs,
        AndroidSpacing.xxs,
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              tooltip: '返回',
              style: IconButton.styleFrom(
                foregroundColor: palette.textPrimary,
                minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                fixedSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 23),
            ),
          const SizedBox(width: AndroidSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AndroidTextStyles.caption(palette.textMuted),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
