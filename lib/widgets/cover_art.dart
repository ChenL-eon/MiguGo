import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';

/// 统一的封面组件：网络加载失败或加载中时使用按名称生成的渐变占位。
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.imageUrl,
    required this.seed,
    this.size,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.iconSize = 28,
  });

  final String? imageUrl;
  final String seed;
  final double? size;
  final BorderRadius borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.coverGradient(seed)),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.72),
          size: iconSize,
        ),
      ),
    );

    Widget image = fallback;
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        headers: const {'Referer': AppConstants.miguReferer},
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return fallback;
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    final content = ClipRRect(
      borderRadius: borderRadius,
      child: Stack(fit: StackFit.expand, children: [fallback, image]),
    );

    if (size == null) return content;
    return SizedBox(width: size, height: size, child: content);
  }
}
