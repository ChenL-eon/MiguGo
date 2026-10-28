import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/player_provider.dart';

/// 迷你播放条的音量入口：点按喇叭在按钮上方浮出竖向胶囊。
///
/// 胶囊顶部是百分比，下面是竖向滑杆；喇叭图标留在胶囊下方作为开关，
/// 长按或右键可直接静音，拖到 0 也能静音。
class VolumePillButton extends StatefulWidget {
  const VolumePillButton({super.key, required this.player});

  final PlayerProvider player;

  @override
  State<VolumePillButton> createState() => _VolumePillButtonState();
}

class _VolumePillButtonState extends State<VolumePillButton> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _open = false;

  double get _volume => widget.player.volume.clamp(0.0, 1.0).toDouble();

  IconData get _icon {
    if (_volume <= 0.001) return Icons.volume_off_rounded;
    if (_volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void _toggleMute() {
    unawaited(widget.player.setVolume(_volume > 0 ? 0 : 0.8));
  }

  Future<void> _openPill() async {
    if (_open) return;
    final anchorBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Navigator.of(context, rootNavigator: true).overlay?.context
            .findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null || !anchorBox.hasSize) return;
    final origin = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchor = origin & anchorBox.size;

    setState(() => _open = true);
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭音量调节',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) {
        final media = MediaQuery.of(dialogContext);
        final panel = VolumePillPanel.size;
        final left = (anchor.center.dx - panel.width / 2)
            .clamp(
              media.padding.left + 8,
              math.max(
                media.padding.left + 8,
                media.size.width - media.padding.right - panel.width - 8,
              ),
            )
            .toDouble();
        final top = math.max(
          media.padding.top + 8,
          anchor.top - panel.height - 10,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: VolumePillPanel(player: widget.player),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _toggleMute,
      onSecondaryTap: _toggleMute,
      child: SizedBox(
        key: _anchorKey,
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: () => unawaited(_openPill()),
          tooltip: '音量：点击调节，长按静音',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: context.palette.textSecondary,
          iconSize: 20,
          icon: Icon(_icon),
        ),
      ),
    );
  }
}

/// 竖向音量胶囊：顶部百分比 + 竖向滑杆，参考图的浮层形态。
class VolumePillPanel extends StatelessWidget {
  const VolumePillPanel({super.key, required this.player});

  static const Size size = Size(64, 200);

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final value = context.watch<PlayerProvider>().volume.clamp(0.0, 1.0);
    final percent = (value * 100).round();
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.palette.line),
      ),
      child: Column(
        children: [
          Text(
            '$percent%',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: context.palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: VerticalVolumeSlider(
              value: value.toDouble(),
              onChanged: (next) => unawaited(player.setVolume(next)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 无拇指的竖向滑杆：已填充部分与轨道都是圆角，100% 时就是参考图里的整条深色胶囊。
class VerticalVolumeSlider extends StatelessWidget {
  const VerticalVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const double _trackWidth = 14;

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        void update(Offset local) {
          if (height <= 0) return;
          onChanged((1 - local.dy / height).clamp(0.0, 1.0).toDouble());
        }

        final stepUp = (normalized + 0.05).clamp(0.0, 1.0).toDouble();
        final stepDown = (normalized - 0.05).clamp(0.0, 1.0).toDouble();
        return Semantics(
          slider: true,
          label: '音量',
          value: '${(normalized * 100).round()}%',
          increasedValue: '${(stepUp * 100).round()}%',
          decreasedValue: '${(stepDown * 100).round()}%',
          onIncrease: () => onChanged(stepUp),
          onDecrease: () => onChanged(stepDown),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition),
            onVerticalDragStart: (details) => update(details.localPosition),
            onVerticalDragUpdate: (details) => update(details.localPosition),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox(
                width: _trackWidth + 20,
                height: height,
                child: CustomPaint(
                  painter: _VerticalVolumeTrackPainter(
                    value: normalized,
                    active: palette.textPrimary,
                    inactive: palette.fillStrong,
                    trackWidth: _trackWidth,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerticalVolumeTrackPainter extends CustomPainter {
  const _VerticalVolumeTrackPainter({
    required this.value,
    required this.active,
    required this.inactive,
    required this.trackWidth,
  });

  final double value;
  final Color active;
  final Color inactive;
  final double trackWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final radius = Radius.circular(trackWidth / 2);
    final track = RRect.fromLTRBR(
      centerX - trackWidth / 2,
      0,
      centerX + trackWidth / 2,
      size.height,
      radius,
    );
    canvas.drawRRect(track, Paint()..color = inactive);

    final fillHeight = size.height * value;
    if (fillHeight <= 0) return;
    final fill = RRect.fromLTRBR(
      centerX - trackWidth / 2,
      size.height - fillHeight,
      centerX + trackWidth / 2,
      size.height,
      radius,
    );
    canvas.drawRRect(fill, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_VerticalVolumeTrackPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.active != active ||
        oldDelegate.inactive != inactive ||
        oldDelegate.trackWidth != trackWidth;
  }
}
