import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../models/playback_mode.dart';
import '../providers/desktop_lyrics_provider.dart';
import '../providers/player_provider.dart';
import 'cover_art.dart';
import 'player_queue_dialog.dart';
import 'volume_slider.dart';

/// 底部迷你播放条：左侧歌曲信息，中间上一首/播放/下一首，
/// 右侧播放顺序、音量浮层、播放列表、倍速与桌面歌词。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final isDesktop = MediaQuery.sizeOf(context).width >= 960;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 20 : 10,
        4,
        isDesktop ? 20 : 10,
        isDesktop ? 14 : 8,
      ),
      child: Material(
        color: context.palette.surfaceHigh.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          hoverColor: context.palette.hover,
          child: SizedBox(
            height: 74,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final wide = width >= 860;
                      final showPrevious = width >= 430;
                      return Row(
                        children: [
                          Expanded(
                            child: _SongSummary(player: player, compact: width < 460),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showPrevious)
                                _MiniIconButton(
                                  icon: Icons.skip_previous_rounded,
                                  tooltip: '上一首',
                                  onPressed: () => unawaited(player.previous()),
                                ),
                              _PlayButton(player: player),
                              _MiniIconButton(
                                icon: Icons.skip_next_rounded,
                                tooltip: '下一首',
                                onPressed: () => unawaited(player.next()),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _RightControls(player: player, wide: wide),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MiniProgress(player: player),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SongSummary extends StatelessWidget {
  const _SongSummary({required this.player, required this.compact});

  final PlayerProvider player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final song = player.currentSong!;
    return Row(
      children: [
        CoverArt(
          imageUrl: song.coverUrl,
          seed: song.name,
          size: compact ? 44 : 48,
          borderRadius: BorderRadius.circular(13),
          iconSize: 20,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: compact ? 13 : 14),
              ),
              const SizedBox(height: 3),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 11.5, color: context.palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightControls extends StatelessWidget {
  const _RightControls({required this.player, required this.wide});

  final PlayerProvider player;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(player: player),
        VolumePillButton(player: player),
        if (wide) ...[
          _MiniIconButton(
            icon: Icons.playlist_play_rounded,
            tooltip: '播放列表',
            onPressed: () => unawaited(showPlayQueueDialog(context)),
          ),
          _SpeedButton(player: player),
          if (Platform.isWindows) const _DesktopLyricsButton(),
        ] else ...[
          _MiniIconButton(
            icon: Icons.playlist_play_rounded,
            tooltip: '播放列表',
            onPressed: () => unawaited(showPlayQueueDialog(context)),
          ),
          const _MoreControls(),
        ],
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final active = (player.speed - 1).abs() > 0.001;
    return PopupMenuButton<double>(
      tooltip: '播放倍速：${_speedLabel(player.speed)}，点击切换',
      padding: EdgeInsets.zero,
      onSelected: (value) => unawaited(player.setSpeed(value)),
      itemBuilder: (context) => [
        for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem<double>(
            value: speed,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: (player.speed - speed).abs() < 0.001
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: context.palette.accent,
                        )
                      : null,
                ),
                Text(_speedLabel(speed), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        // 倍速用数字本身当图标，比任何仪表符号都少一层歧义。
        child: Text(
          _speedLabel(player.speed),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? context.palette.accent : context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DesktopLyricsButton extends StatelessWidget {
  const _DesktopLyricsButton();

  @override
  Widget build(BuildContext context) {
    final lyrics = context.watch<DesktopLyricsProvider>();
    return _MiniIconButton(
      icon: lyrics.enabled ? Icons.subtitles_rounded : Icons.subtitles_outlined,
      tooltip: lyrics.enabled ? '退出桌面歌词' : '桌面歌词',
      color: lyrics.enabled ? context.palette.accent : null,
      onPressed: lyrics.busy ? null : () => unawaited(lyrics.toggle()),
    );
  }
}

class _MoreControls extends StatelessWidget {
  const _MoreControls();

  Future<void> _handle(BuildContext context, String value) async {
    switch (value) {
      case 'speed':
        await showSpeedDialog(context);
      case 'lyrics':
        await context.read<DesktopLyricsProvider>().toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多播放控制',
      padding: EdgeInsets.zero,
      onSelected: (value) => unawaited(_handle(context, value)),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'speed',
          child: Row(
            children: [
              Icon(Icons.av_timer_rounded, size: 18),
              SizedBox(width: 10),
              Text('倍速播放', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (Platform.isWindows)
          const PopupMenuItem(
            value: 'lyrics',
            child: Row(
              children: [
                Icon(Icons.subtitles_outlined, size: 18),
                SizedBox(width: 10),
                Text('桌面歌词', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    if (player.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(11),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IconButton(
        onPressed: () => unawaited(player.togglePlayPause()),
        tooltip: player.isPlaying ? '暂停' : '播放',
        style: IconButton.styleFrom(
          backgroundColor: context.palette.accent,
          foregroundColor: context.palette.onAccent,
          fixedSize: const Size(42, 42),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 25,
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: color ?? context.palette.textSecondary,
      iconSize: 22,
      icon: Icon(icon),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final icon = switch (player.mode) {
      PlaybackMode.listLoop => Icons.repeat_rounded,
      PlaybackMode.singleLoop => Icons.repeat_one_rounded,
      PlaybackMode.shuffle => Icons.shuffle_rounded,
    };
    final active = player.mode != PlaybackMode.listLoop;
    return IconButton(
      onPressed: () => unawaited(player.cyclePlaybackMode()),
      tooltip: '${player.mode.label}，点击切换',
      visualDensity: VisualDensity.compact,
      color: active ? context.palette.accent : context.palette.textSecondary,
      iconSize: 20,
      icon: Icon(icon),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnapshot) {
        final duration =
            durationSnapshot.data ?? player.currentSong?.duration ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final value = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: context.palette.accent.withValues(alpha: 0.8),
              ),
            );
          },
        );
      },
    );
  }
}

String _speedLabel(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$text×';
}
