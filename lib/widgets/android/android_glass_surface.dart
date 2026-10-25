import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// 手机端的磨砂面板，用于悬浮底栏、迷你播放条等少量层级。
///
/// 模糊只作用于面板背后，内容与投影仍然保持清晰；桌面端不要引用此组件。
class AndroidGlassSurface extends StatelessWidget {
  const AndroidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = AndroidRadius.card,
    this.blurSigma = 20,
    this.tint,
    this.borderColor,
    this.padding = EdgeInsets.zero,
    this.shadows,
  }) : assert(blurSigma >= 0);

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color? tint;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedShadows =
        shadows ??
        [
          // 远层是「浮起来」的那圈淡影。偏移要接近两倍模糊半径，最浓的地方
          // 才会落到面板下沿之外；贴边那道灰带就是这么来的。
          BoxShadow(
            color: palette.shadow.withValues(alpha: isDark ? 0.26 : 0.035),
            blurRadius: 14,
            offset: const Offset(0, 11),
          ),
          // 近层补一点贴合的接触影，只剩远层时边缘会发虚、像没贴住屏幕。
          BoxShadow(
            color: palette.shadow.withValues(alpha: isDark ? 0.18 : 0.025),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: resolvedShadows),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint ?? palette.surface.withValues(alpha: isDark ? 0.78 : 0.82),
                borderRadius: borderRadius,
                border: Border.all(color: borderColor ?? palette.line),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
