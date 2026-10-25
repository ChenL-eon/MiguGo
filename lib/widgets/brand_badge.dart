import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 品牌标记：粉色渐变底板与圆角都由这里绘制，SVG 只负责透明底的圆环。
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.size, required this.radius, this.shadow});

  final double size;
  final double radius;
  final List<BoxShadow>? shadow;

  static const _baseGradient = LinearGradient(
    begin: Alignment(-0.656, 0.755),
    end: Alignment(0.656, -0.755),
    colors: [Color(0xFFEF0A67), Color(0xFFFC6097)],
  );

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: _baseGradient),
          child: SvgPicture.asset('assets/svg/MiguGo.svg', fit: BoxFit.cover),
        ),
      ),
    );
  }
}
