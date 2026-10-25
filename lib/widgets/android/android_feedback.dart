import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';
import 'android_shell_inset.dart';

/// Android 端统一的交互反馈：提示条、确认框与行内错误。
///
/// 桌面端仍使用原有 SnackBar 与 AlertDialog，这里只提供手机习惯的样式，
/// 由调用处按平台分支，避免影响桌面布局。

/// 底部浮动提示条。
///
/// 壳层的悬浮底栏画在 Stack 里，SnackBar 拿不到 [AndroidShellInset]，
/// 因此在调用处读取留白并换算成底部外边距；
/// 推入式页面与操作表没有悬浮栏，退回系统安全区高度。
void showAndroidSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  IconData? icon,
  SnackBarAction? action,
}) {
  final inset = AndroidShellInset.of(context);
  final bottom = inset > 0
      ? inset + AndroidSpacing.xs
      : MediaQuery.of(context).viewPadding.bottom + AndroidSpacing.xs;
  final palette = context.palette;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.surfaceHigh,
        duration: Duration(milliseconds: isError ? 4200 : 2600),
        margin: EdgeInsets.fromLTRB(AndroidSpacing.lg, 0, AndroidSpacing.lg, bottom),
        padding: const EdgeInsets.symmetric(
          horizontal: AndroidSpacing.md,
          vertical: AndroidSpacing.sm,
        ),
        action: action,
        content: Row(
          children: [
            Icon(
              icon ??
                  (isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded),
              size: AndroidSizes.smallIcon,
              color: isError
                  ? palette.danger
                  : (icon == null ? palette.mint : palette.textSecondary),
            ),
            const SizedBox(width: AndroidSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: AndroidTypeScale.body,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  if (isError) unawaited(HapticFeedback.errorNotification());
}

/// Android 风格的确认框，返回 true 表示用户点击了主操作。
Future<bool> showAndroidConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _AndroidDialog(
        icon: icon,
        tone: destructive ? dialogContext.palette.danger : dialogContext.palette.accent,
        title: title,
        message: message,
        actions: [
          _AndroidDialogButton(
            label: cancelLabel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          _AndroidDialogButton(
            label: confirmLabel,
            filled: true,
            danger: destructive,
            onPressed: () {
              unawaited(HapticFeedback.selectionClick());
              Navigator.of(dialogContext).pop(true);
            },
          ),
        ],
      );
    },
  );
  return result == true;
}

/// 只用于告知的对话框，确认后关闭。
Future<void> showAndroidNotice(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '知道了',
  IconData icon = Icons.info_outline_rounded,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AndroidDialog(
        icon: icon,
        tone: dialogContext.palette.accent,
        title: title,
        message: message,
        actions: [
          _AndroidDialogButton(
            label: confirmLabel,
            filled: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

/// 列表、页面内部的行内错误条：比整页错误态轻，比重试按钮重。
class AndroidInlineError extends StatelessWidget {
  const AndroidInlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
    this.onDismiss,
    this.title,
  });

  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AndroidSpacing.sm,
        AndroidSpacing.xs,
        AndroidSpacing.xs,
        AndroidSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AndroidRadius.sm),
        border: Border.all(color: palette.danger.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: AndroidSizes.smallIcon,
                  color: palette.danger,
                ),
              ),
              const SizedBox(width: AndroidSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: AndroidTypeScale.caption,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: AndroidTypeScale.caption,
                        height: 1.55,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  tooltip: '关闭提示',
                  iconSize: 16,
                  style: IconButton.styleFrom(
                    foregroundColor: palette.textMuted,
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          if (onRetry != null || onDismiss != null)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AndroidSpacing.xxs,
                children: [
                  if (onRetry != null)
                    TextButton(
                      onPressed: () {
                        unawaited(HapticFeedback.selectionClick());
                        onRetry!();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: palette.danger,
                        minimumSize: const Size(64, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AndroidRadius.pillAll,
                        ),
                      ),
                      child: Text(retryLabel),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AndroidDialog extends StatelessWidget {
  const _AndroidDialog({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AndroidSpacing.xl,
        vertical: AndroidSpacing.lg,
      ),
      elevation: 6,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AndroidRadius.lg)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 336),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AndroidSpacing.lg,
            AndroidSpacing.lg,
            AndroidSpacing.lg,
            AndroidSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AndroidRadius.sm),
                ),
                child: Icon(icon, size: 20, color: tone),
              ),
              const SizedBox(height: AndroidSpacing.md),
              Text(title, style: AndroidTextStyles.sectionTitle(palette.textPrimary)),
              const SizedBox(height: AndroidSpacing.xs),
              Text(
                message,
                style: TextStyle(
                  fontSize: AndroidTypeScale.body,
                  height: 1.65,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: AndroidSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, action) in actions.indexed) ...[
                      if (index > 0) const SizedBox(width: AndroidSpacing.xs),
                      action,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidDialogButton extends StatelessWidget {
  const _AndroidDialogButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!filled) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.textSecondary,
          backgroundColor: palette.fillSubtle,
          minimumSize: const Size(72, AndroidSizes.touch),
          padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AndroidRadius.pillAll),
          textStyle: AndroidTextStyles.action(palette.textSecondary),
        ),
        child: Text(label),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: danger ? palette.danger : palette.accent,
        foregroundColor: palette.onAccent,
        minimumSize: const Size(84, AndroidSizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: AndroidRadius.pillAll),
        textStyle: AndroidTextStyles.action(palette.onAccent),
      ),
      child: Text(label),
    );
  }
}
