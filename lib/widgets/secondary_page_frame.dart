import 'package:flutter/material.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../pages/about_page.dart';
import '../pages/settings_page.dart';
import 'ambient_background.dart';
import 'android/android_page_top_bar.dart';
import 'app_window_caption.dart';

/// 进入设置二级页：首页齿轮与「我的」底部入口共用。
void openSettingsPage(BuildContext context) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => const SecondaryPageFrame(
        title: '设置',
        subtitle: '所有改动即时生效并保存在本机',
        child: SettingsPage(),
      ),
    ),
  );
}

/// 进入关于二级页：桌面端从首页页脚进入，手机端从设置页底部进入。
void openAboutPage(BuildContext context) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => const SecondaryPageFrame(
        title: '关于',
        subtitle: '用途、权限边界与实现说明',
        child: AboutPage(),
      ),
    ),
  );
}

/// 二级页面外壳：从“我的”进入设置/关于时提供返回入口与统一背景。
///
/// 手机端换成 [AndroidPageTopBar]，标题交给顶栏，页面内不再重复画大标题；
/// 桌面端保持原来的自绘标题栏 + 悬浮返回按钮。
class SecondaryPageFrame extends StatelessWidget {
  const SecondaryPageFrame({super.key, required this.child, this.title, this.subtitle});

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: AmbientBackground(
        child: isAndroidPlatform ? _androidBody(context) : _desktopBody(context),
      ),
    );
  }

  Widget _androidBody(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AndroidPageTopBar(
            title: title ?? '',
            subtitle: subtitle,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _desktopBody(BuildContext context) {
    return Column(
      children: [
        const AppWindowCaption(),
        Expanded(
          child: SafeArea(
            top: !AppWindowCaption.managed,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(padding: const EdgeInsets.only(top: 46), child: child),
                ),
                Positioned(
                  top: 4,
                  left: 8,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '返回',
                    style: IconButton.styleFrom(
                      backgroundColor: context.palette.surfaceHigh.withValues(
                        alpha: 0.9,
                      ),
                      foregroundColor: context.palette.textPrimary,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
