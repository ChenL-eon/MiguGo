import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 圆形进度环：一整圈轨道加从十二点方向顺时针推进的进度弧。
///
/// 迷你播放条的封面外圈与底部导航中间的唱片用同一个环，避免两处弧度不一致。
class AndroidRingProgress extends StatelessWidget {
  const AndroidRingProgress({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.strokeWidth = 2.4,
    this.trackStrokeWidth = 2,
    this.child,
  });

  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;
  final double trackStrokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingProgressPainter(
        value: value,
        color: color,
        track: track,
        strokeWidth: strokeWidth,
        trackStrokeWidth: trackStrokeWidth,
      ),
      child: child,
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  const _RingProgressPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.strokeWidth,
    required this.trackStrokeWidth,
  });

  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;
  final double trackStrokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 3) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackStrokeWidth
        ..color = track,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.track != track ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.trackStrokeWidth != trackStrokeWidth;
  }
}
