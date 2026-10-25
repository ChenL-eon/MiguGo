import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 音量条：迷你播放条与播放页共用同一套圆角轨道与描边拇指。
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.accent;
    final normalized = value.clamp(0.0, 1.0).toDouble();
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 5,
        trackShape: const RoundedRectSliderTrackShape(),
        activeTrackColor: accent,
        inactiveTrackColor: context.palette.fillStrong,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        thumbShape: _VolumeThumbShape(color: accent),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
        overlayColor: accent.withValues(alpha: 0.14),
        valueIndicatorColor: accent,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Slider(
        value: normalized,
        label: '${(normalized * 100).round()}%',
        onChanged: onChanged,
      ),
    );
  }
}

/// 白底描边的圆点拇指：浅色与深色主题下都能看清拖动位置。
class _VolumeThumbShape extends SliderComponentShape {
  const _VolumeThumbShape({required this.color});

  final Color color;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 7.4, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      7.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.35),
    );
    canvas.drawCircle(center, 5.2, Paint()..color = color);
  }
}
