import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// Android 首页/搜索结果共用的胶囊搜索框。
///
/// 输入、清空与提交都交给调用方，组件本身不持有搜索状态。
class AndroidSearchField extends StatelessWidget {
  const AndroidSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
    this.hintText = '搜索歌曲、歌手或歌单',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: AndroidRadius.pillAll,
      borderSide: BorderSide(color: palette.line),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      style: AndroidTextStyles.body(palette.textPrimary),
      cursorColor: palette.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: palette.surfaceHigh.withValues(alpha: isDark ? 0.7 : 0.92),
        hintText: hintText,
        hintStyle: AndroidTextStyles.body(palette.textMuted),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Icon(Icons.search_rounded, size: 21, color: palette.textMuted),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 43,
          minHeight: AndroidSizes.touch,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.text.isNotEmpty)
                  IconButton(
                    onPressed: onClear,
                    tooltip: '清空搜索',
                    constraints: const BoxConstraints(
                      minWidth: AndroidSizes.touch,
                      minHeight: AndroidSizes.touch,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: palette.textMuted,
                    icon: const Icon(Icons.close_rounded),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 6),
                  child: Material(
                    color: palette.accent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSubmitted(controller.text),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 19,
                          color: palette.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: AndroidSizes.touch),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: AndroidRadius.pillAll,
          borderSide: BorderSide(
            color: palette.accent.withValues(alpha: 0.68),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
