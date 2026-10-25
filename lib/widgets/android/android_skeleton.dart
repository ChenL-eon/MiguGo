import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';

/// 骨架屏的呼吸容器：同一区域的占位块共用一个动画节奏。
class AndroidSkeleton extends StatefulWidget {
  const AndroidSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<AndroidSkeleton> createState() => _AndroidSkeletonState();
}

class _AndroidSkeletonState extends State<AndroidSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(
      begin: 0.48,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// 基础占位块，颜色沿用当前主题的轻填充色。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AndroidRadius.xs,
    this.color,
  });

  final double? width;
  final double? height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? context.palette.fillStrong,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 文本行占位，默认高度对应 12px 辅助文字。
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = AndroidTypeScale.caption,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: width, height: height, radius: radius);
  }
}
