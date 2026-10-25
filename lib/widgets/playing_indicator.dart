import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 当前播放歌曲的跳动音柱。
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    super.key,
    required this.playing,
    this.size = 16,
    this.color,
  });

  final bool playing;
  final double size;
  final Color? color;

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = math.max(2.0, widget.size * 0.16);
    final color = widget.color ?? context.palette.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phases = [0.0, 2.1, 4.2];
          final heights = widget.playing
              ? phases
                    .map(
                      (phase) =>
                          0.28 +
                          0.72 *
                              ((math.sin(_controller.value * math.pi * 2 + phase) + 1) /
                                  2),
                    )
                    .toList()
              : [0.45, 0.8, 0.32];
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: heights
                .map(
                  (height) => Container(
                    width: barWidth,
                    height: widget.size * height,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(barWidth),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
