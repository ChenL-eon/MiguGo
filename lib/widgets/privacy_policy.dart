import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import 'android/android_sheet.dart';

/// 隐私政策正文：按 [AppConstants.privacyPolicy] 的顺序原样渲染小标题与说明。
/// 登录面板的详情窗口与「关于」页共用这一份，避免两处说明各自漂移。
class PrivacyPolicySections extends StatelessWidget {
  const PrivacyPolicySections({super.key});

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final notice in AppConstants.privacyPolicy)
          Padding(
            padding: EdgeInsets.only(bottom: android ? AndroidSpacing.md : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: TextStyle(
                    fontSize: android ? AndroidTypeScale.listTitle : 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
                SizedBox(height: android ? 6 : 5),
                SelectableText(
                  notice.body,
                  style: TextStyle(
                    fontSize: android ? AndroidTypeScale.body : 12,
                    height: 1.75,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PrivacyPolicyBody extends StatelessWidget {
  const _PrivacyPolicyBody();

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppConstants.privacyPolicyIntro,
          style: TextStyle(
            fontSize: android ? AndroidTypeScale.body : 11.5,
            height: 1.75,
            color: android ? context.palette.textSecondary : context.palette.textMuted,
          ),
        ),
        SizedBox(height: android ? AndroidSpacing.md : 14),
        const PrivacyPolicySections(),
      ],
    );
  }
}

/// 隐私政策详情窗口。从登录面板里打开时叠在面板之上，关闭后回到登录面板。
Future<void> showPrivacyPolicyDialog(BuildContext context) {
  if (isAndroidPlatform) {
    return showAndroidSheet<void>(
      context: context,
      title: '隐私政策',
      subtitle: '长按正文可选中复制',
      builder: (_) => const _PrivacyPolicyBody(),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      title: const Text('隐私政策'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: SingleChildScrollView(child: const _PrivacyPolicyBody()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
