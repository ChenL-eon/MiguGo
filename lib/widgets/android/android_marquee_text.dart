import 'dart:async';

import 'package:flutter/material.dart';

/// 单行文本在空间不足时缓慢横向滚动，空间足够或系统关闭动画时保持静态。
class AndroidMarqueeText extends StatelessWidget {
  const AndroidMarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 26,
    this.gap = 40,
    this.startDelay = const Duration(milliseconds: 1200),
  }) : assert(velocity > 0),
       assert(gap >= 0);

  final String text;
  final TextStyle? style;

  /// 每秒滚动的逻辑像素。
  final double velocity;
  final double gap;
  final Duration startDelay;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textWidth = painter.width;
    final textHeight = painter.height;
    painter.dispose();

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            if (!constraints.hasBoundedWidth || textWidth <= maxWidth || reduceMotion) {
              return Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: effectiveStyle,
              );
            }
            return _AndroidMarqueeRun(
              text: text,
              style: effectiveStyle,
              textWidth: textWidth,
              width: maxWidth,
              height: textHeight,
              velocity: velocity,
              gap: gap,
              startDelay: startDelay,
            );
          },
        ),
      ),
    );
  }
}

class _AndroidMarqueeRun extends StatefulWidget {
  const _AndroidMarqueeRun({
    required this.text,
    required this.style,
    required this.textWidth,
    required this.width,
    required this.height,
    required this.velocity,
    required this.gap,
    required this.startDelay,
  });

  final String text;
  final TextStyle style;
  final double textWidth;
  final double width;
  final double height;
  final double velocity;
  final double gap;
  final Duration startDelay;

  @override
  State<_AndroidMarqueeRun> createState() => _AndroidMarqueeRunState();
}

class _AndroidMarqueeRunState extends State<_AndroidMarqueeRun>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _startTimer;

  double get _distance => widget.textWidth + widget.gap;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _restart();
  }

  @override
  void didUpdateWidget(covariant _AndroidMarqueeRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.textWidth != widget.textWidth ||
        oldWidget.width != widget.width ||
        oldWidget.gap != widget.gap ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.startDelay != widget.startDelay) {
      _restart();
    }
  }

  void _restart() {
    _startTimer?.cancel();
    _controller.stop();
    _controller.value = 0;
    final durationMs = ((_distance / widget.velocity) * 1000)
        .round()
        .clamp(2000, 30000)
        .toInt();
    _controller.duration = Duration(milliseconds: durationMs);
    _startTimer = Timer(widget.startDelay, () {
      if (!mounted) return;
      _controller.repeat();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_distance * _controller.value, 0),
                child: child,
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                SizedBox(width: widget.gap),
                Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
