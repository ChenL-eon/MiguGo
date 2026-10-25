import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// 主题底色 + 两处柔和光晕，作为全局背景。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.showGlow = true});

  final Widget child;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final glow = showGlow && settings.ambientGlowEnabled;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: context.palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (glow) ...[
            Positioned(
              top: -220,
              right: -160,
              child: _Glow(
                color: context.palette.accent.withValues(alpha: dark ? 0.16 : 0.1),
                size: 620,
              ),
            ),
            Positioned(
              bottom: -260,
              left: -200,
              child: _Glow(
                color: context.palette.mint.withValues(alpha: dark ? 0.09 : 0.07),
                size: 560,
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}
