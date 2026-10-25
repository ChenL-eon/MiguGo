import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../providers/player_provider.dart';
import 'android/android_sheet.dart';
import 'cover_art.dart';
import 'playing_indicator.dart';
import 'song_tile.dart';
import 'state_views.dart';

/// 播放列表入口：Android 走底部操作表，桌面保持原有对话框。
Future<void> showPlayQueueDialog(BuildContext context) async {
  if (isAndroidPlatform) {
    final count = context.read<PlayerProvider>().queue.length;
    await showAndroidSheet<void>(
      context: context,
      title: '播放列表',
      subtitle: count == 0 ? '列表还是空的' : '共 $count 首 · 点击切歌',
      scrollable: false,
      contentPadding: const EdgeInsets.only(top: AndroidSpacing.sm),
      builder: (_) => const _AndroidQueueSheet(),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final player = dialogContext.watch<PlayerProvider>();
      final palette = dialogContext.palette;
      return Dialog(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 20, color: palette.accent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '播放列表（${player.queue.length} 首）',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      color: palette.textMuted,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: player.queue.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          '播放列表还是空的。',
                          style: TextStyle(color: palette.textMuted),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          itemCount: player.queue.length,
                          itemBuilder: (context, index) {
                            final song = player.queue[index];
                            final isCurrent = index == player.currentIndex;
                            return Material(
                              color: isCurrent
                                  ? palette.accentSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  unawaited(player.playQueue(player.queue, index));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: Center(
                                          child: isCurrent
                                              ? PlayingIndicator(
                                                  playing: player.isPlaying,
                                                  size: 12,
                                                )
                                              : Text(
                                                  '${index + 1}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: palette.textMuted,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      CoverArt(
                                        imageUrl: song.coverUrl,
                                        seed: song.name,
                                        size: 40,
                                        borderRadius: BorderRadius.circular(10),
                                        iconSize: 17,
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                color: isCurrent
                                                    ? palette.accent
                                                    : palette.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: palette.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isCurrent)
                                        Icon(
                                          Icons.graphic_eq_rounded,
                                          size: 17,
                                          color: palette.accent,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Android 播放列表：沿用统一单曲行，列表高度随内容收起，超过上限再滚动。
class _AndroidQueueSheet extends StatelessWidget {
  const _AndroidQueueSheet();

  static const double _rowHeight = 72;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    if (queue.isEmpty) {
      return const AppEmptyView(
        icon: Icons.queue_music_rounded,
        title: '播放列表还是空的',
        message: '先从首页或歌单里点一首歌，它就会出现在这里。',
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: queue.length * _rowHeight + AndroidSpacing.xs,
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: queue.length,
        itemBuilder: (context, index) {
          final song = queue[index];
          final isCurrent = index == player.currentIndex;
          return SongTile(
            song: song,
            number: index + 1,
            isCurrent: isCurrent,
            isPlaying: player.isPlaying,
            onTap: () {
              // 轻震动由 SongTile 自身负责，这里不再重复触发。
              Navigator.of(context).maybePop();
              unawaited(player.playQueue(player.queue, index));
            },
          );
        },
      ),
    );
  }
}

Future<void> showVolumeDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final player = dialogContext.watch<PlayerProvider>();
      final palette = dialogContext.palette;
      return AlertDialog(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.line),
        ),
        title: const Text('音量'),
        content: SizedBox(
          width: 320,
          child: Row(
            children: [
              Icon(
                player.volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              Expanded(
                child: Slider(
                  value: player.volume,
                  onChanged: (value) => unawaited(player.setVolume(value)),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(player.volume * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('完成'),
          ),
        ],
      );
    },
  );
}

Future<void> showSpeedDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final player = dialogContext.watch<PlayerProvider>();
      final palette = dialogContext.palette;
      return AlertDialog(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.line),
        ),
        title: const Text('播放倍速'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ChoiceChip(
                label: Text(_speedLabel(speed)),
                selected: (player.speed - speed).abs() < 0.001,
                onSelected: (_) {
                  unawaited(player.setSpeed(speed));
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}

String _speedLabel(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$text×';
}
