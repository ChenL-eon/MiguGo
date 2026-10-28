import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';
import '../../models/audio_quality.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../cover_art.dart';
import '../player_queue_dialog.dart';
import 'android_bounded_chrome.dart';
import 'android_choice.dart';
import 'android_glass_surface.dart';
import 'android_marquee_text.dart';
import 'android_ring_progress.dart';
import 'android_sheet.dart';

/// Android 迷你播放条：封面外圈显示播放进度，右侧只保留播放、队列与更多。
///
/// 倍速、音质与定时收进底部操作表，避免在 60dp 高度里堆叠过多图标。
class AndroidMiniPlayer extends StatelessWidget {
  const AndroidMiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = AndroidGlassSurface(
      borderRadius: BorderRadius.circular(AndroidRadius.xl),
      blurSigma: 22,
      tint: palette.surfaceHigh.withValues(alpha: isDark ? 0.84 : 0.9),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AndroidRadius.xl),
          child: SizedBox(
            height: AndroidSizes.miniPlayerHeight,
            child: Row(
              children: [
                const SizedBox(width: AndroidSpacing.xs),
                _MiniRingCover(player: player),
                const SizedBox(width: AndroidSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AndroidMarqueeText(
                        song.name,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                        velocity: 24,
                      ),
                      const SizedBox(height: 3),
                      AndroidMarqueeText(
                        song.artist,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: palette.textSecondary,
                        ),
                        velocity: 20,
                        startDelay: const Duration(milliseconds: 1800),
                      ),
                    ],
                  ),
                ),
                _MiniPlayButton(player: player),
                _MiniActionButton(
                  icon: Icons.playlist_play_rounded,
                  tooltip: '播放列表',
                  onPressed: () => unawaited(showPlayQueueDialog(context)),
                ),
                _MiniActionButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多播放控制',
                  onPressed: () => unawaited(showAndroidPlaybackSheet(context)),
                ),
                const SizedBox(width: AndroidSpacing.xxs),
              ],
            ),
          ),
        ),
      ),
    );
    return AndroidBoundedChrome(child: panel);
  }
}

/// 打开播放控制的底部操作表：倍速、音质与睡眠定时。
///
/// 播放顺序在播放页控制排上直接切换，音量交给系统音量键，这里不再重复摆放。
Future<void> showAndroidPlaybackSheet(BuildContext context) {
  return showAndroidSheet<void>(
    context: context,
    title: '播放控制',
    subtitle: '调整倍速、音质与睡眠定时',
    builder: (_) => const _PlaybackOptionsSheet(),
  );
}

class _MiniRingCover extends StatelessWidget {
  const _MiniRingCover({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final song = player.currentSong!;
    final palette = context.palette;
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? song.duration;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return SizedBox(
              width: 52,
              height: 52,
              child: AndroidRingProgress(
                value: progress,
                color: palette.accent,
                track: palette.fillStrong,
                child: Center(
                  child: CoverArt(
                    imageUrl: song.coverUrl,
                    seed: song.name,
                    size: 46,
                    borderRadius: BorderRadius.circular(13),
                    iconSize: 20,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniPlayButton extends StatelessWidget {
  const _MiniPlayButton({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: AndroidSizes.touch,
      height: AndroidSizes.touch,
      child: Center(
        child: player.isLoading
            ? SizedBox(
                width: 34,
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
              )
            : Material(
                color: palette.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    unawaited(player.togglePlayPause());
                  },
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 23,
                      color: palette.onAccent,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 21,
      style: IconButton.styleFrom(
        foregroundColor: context.palette.textSecondary,
        minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
        fixedSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon),
    );
  }
}

/// 播放控制操作表的宫格：两列排布，每格「图标 + 名称 + 当前值」，点开是单选面板。
class _PlaybackOptionsSheet extends StatelessWidget {
  const _PlaybackOptionsSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final settings = context.watch<SettingsProvider>();
    final tiles = [
      _ControlTile(
        icon: Icons.speed_rounded,
        label: '倍速',
        value: _speedLabel(player.speed),
        highlighted: (player.speed - 1).abs() > 0.001,
        onTap: () => unawaited(
          showAndroidChoiceSheet<double>(
            context,
            title: '播放倍速',
            subtitle: '变速只影响本机播放，不改变音质。',
            selected: player.speed,
            options: [
              for (final speed in SettingsProvider.playbackSpeedOptions)
                AndroidChoiceOption<double>(value: speed, label: _speedLabel(speed)),
            ],
            onSelected: (speed) => unawaited(player.setSpeed(speed)),
          ),
        ),
      ),
      _ControlTile(
        icon: Icons.high_quality_rounded,
        label: '音质',
        value: settings.audioQuality.shortLabel,
        onTap: () => unawaited(
          showAndroidChoiceSheet<AudioQuality>(
            context,
            title: '播放音质',
            subtitle:
                '优先请求所选音质，账号没有该档权益时自动回退；'
                '至臻 24bit 需曲目提供且账号有对应权益，下一首开始生效。',
            selected: settings.audioQuality,
            options: [
              for (final quality in AudioQuality.values)
                AndroidChoiceOption<AudioQuality>(
                  value: quality,
                  label: quality.label,
                  description: quality.detail,
                ),
            ],
            onSelected: (quality) => unawaited(settings.setAudioQuality(quality)),
          ),
        ),
      ),
      _ControlTile(
        icon: Icons.mode_night_rounded,
        label: '定时',
        value: _sleepLabel(player.sleepDuration),
        highlighted: player.hasSleepTimer,
        onTap: () => unawaited(
          showAndroidChoiceSheet<Duration?>(
            context,
            title: '睡眠定时',
            subtitle: '到时间后自动暂停，适合睡前听歌。',
            selected: player.hasSleepTimer ? player.sleepDuration : null,
            options: [
              for (final option in PlayerProvider.sleepTimerOptions)
                AndroidChoiceOption<Duration?>(
                  value: option.delay,
                  label: option.label,
                ),
            ],
            onSelected: player.setSleepTimer,
          ),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AndroidSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row * 2 < tiles.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AndroidSpacing.xs),
              child: Row(
                children: [
                  Expanded(child: tiles[row * 2]),
                  const SizedBox(width: AndroidSpacing.xs),
                  Expanded(
                    child: row * 2 + 1 < tiles.length
                        ? tiles[row * 2 + 1]
                        : const SizedBox(height: _ControlTile.height),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 操作表里的一个宫格按钮。
class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.highlighted = false,
  });

  static const double height = 96;

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AndroidRadius.md);
    return Semantics(
      button: true,
      label: '$label $value',
      child: Material(
        // 播放页的沉浸式色板里 accent 就是白色，只换字色看不出「已生效」，
        // 所以选中态额外给一层底色与描边。
        color: highlighted ? palette.accentSoft : palette.fillSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: highlighted
              ? BorderSide(color: palette.accent.withValues(alpha: 0.35))
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          borderRadius: radius,
          child: SizedBox(
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: AndroidSizes.largeIcon,
                  color: highlighted ? palette.accent : palette.textPrimary,
                ),
                const SizedBox(height: AndroidSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: highlighted ? palette.accent : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _speedLabel(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$text×';
}

String _sleepLabel(Duration? delay) {
  if (delay == null) return '关闭';
  for (final option in PlayerProvider.sleepTimerOptions) {
    if (option.delay == delay) return option.label;
  }
  return '${delay.inMinutes} 分钟';
}
