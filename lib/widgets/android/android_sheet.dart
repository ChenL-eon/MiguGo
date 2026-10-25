import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// 打开 Android 风格底部操作表。
///
/// 内容默认放在可滚动区域中；需要内部列表自行处理滚动时，把 [scrollable] 设为 false。
Future<T?> showAndroidSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  bool scrollable = true,
  bool isDismissible = true,
  bool enableDrag = true,
  double maxHeightFactor = 0.86,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(
    AndroidSpacing.lg,
    0,
    AndroidSpacing.lg,
    AndroidSpacing.lg,
  ),
}) {
  assert(maxHeightFactor > 0 && maxHeightFactor <= 1);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    barrierLabel: '关闭操作面板',
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final availableHeight =
          media.size.height - media.viewInsets.bottom - media.padding.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AndroidSizes.sheetMaxWidth,
              maxHeight:
                  availableHeight.clamp(0.0, media.size.height) * maxHeightFactor,
            ),
            child: _AndroidSheetFrame(
              title: title,
              subtitle: subtitle,
              contentPadding: contentPadding,
              scrollable: scrollable,
              child: builder(sheetContext),
            ),
          ),
        ),
      );
    },
  );
}

class _AndroidSheetFrame extends StatelessWidget {
  const _AndroidSheetFrame({
    required this.title,
    required this.subtitle,
    required this.contentPadding,
    required this.scrollable,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry contentPadding;
  final bool scrollable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final content = scrollable
        ? SingleChildScrollView(padding: contentPadding, child: child)
        : Padding(padding: contentPadding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AndroidRadius.sheetTop,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: ClipRRect(
        borderRadius: AndroidRadius.sheetTop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AndroidSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AndroidSpacing.lg,
                AndroidSpacing.xs,
                AndroidSpacing.xs,
                0,
              ),
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
                            style: AndroidTextStyles.headline(palette.textPrimary),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AndroidSpacing.xxs),
                          Text(
                            subtitle!,
                            style: AndroidTextStyles.caption(palette.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '关闭',
                    style: IconButton.styleFrom(
                      foregroundColor: palette.textSecondary,
                      minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                      fixedSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(child: content),
          ],
        ),
      ),
    );
  }
}
