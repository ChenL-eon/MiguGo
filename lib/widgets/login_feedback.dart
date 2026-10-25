import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import 'android/android_feedback.dart';

/// 登录相关页面共用的提示条与提示动作。
///
/// 登录页与官方登录窗口都会用到同一套状态条样式，
/// 抽出来避免两处各写一份。

void showLoginSnack(BuildContext context, String message, {bool isError = false}) {
  if (!context.mounted) return;
  if (isAndroidPlatform) {
    showAndroidSnack(context, message, isError: isError);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 17,
              color: isError ? context.palette.danger : context.palette.mint,
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// 凭证未能写入系统安全存储时的说明；本次运行仍可用。
Future<void> showLoginStorageWarning(BuildContext context, String warning) async {
  if (!context.mounted) return;
  final message = '$warning\n\n本次运行内仍可使用；重启应用后需要重新登录。';
  if (isAndroidPlatform) {
    await showAndroidNotice(
      context,
      title: '登录信息未能写入安全存储',
      message: message,
      icon: Icons.phonelink_lock_outlined,
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: context.palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: context.palette.line),
        ),
        title: const Text('登录信息未能写入安全存储'),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: context.palette.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

class LoginInfoBanner extends StatelessWidget {
  const LoginInfoBanner({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.65,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoginStatusBanner extends StatelessWidget {
  const LoginStatusBanner({super.key, required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final tone = isError ? context.palette.danger : context.palette.gold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 15,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.65,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginMethodStep extends StatelessWidget {
  const LoginMethodStep({
    super.key,
    required this.index,
    required this.title,
    required this.description,
  });

  final String index;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              index,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: context.palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.65,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
