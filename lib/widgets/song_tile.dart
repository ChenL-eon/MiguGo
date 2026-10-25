import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/platform_kind.dart';
import '../models/song.dart';
import 'cover_art.dart';
import 'playing_indicator.dart';
import 'tag_pill.dart';

/// 单曲行：歌名、歌手、专辑、时长，以及当前播放状态。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.number,
    this.isCurrent = false,
    this.isPlaying = false,
    this.showCover = true,
    this.showNumber = true,
    this.doubleTapToPlay = false,
  });

  final Song song;
  final VoidCallback onTap;

  /// 桌面端置 true：单击只留下悬停/选中反馈，双击才起播。
  final bool doubleTapToPlay;
  final int? number;
  final bool isCurrent;
  final bool isPlaying;
  final bool showCover;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final compact = android || constraints.maxWidth < 560;
        final showDuration = android || !compact;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isCurrent ? context.palette.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: doubleTapToPlay
                  ? null
                  : () {
                      // 手机上点歌单行会起播，用一次轻震动确认操作已经被接住。
                      if (android) {
                        unawaited(HapticFeedback.selectionClick());
                      }
                      onTap();
                    },
              onDoubleTap: doubleTapToPlay ? onTap : null,
              hoverColor: context.palette.hover,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? (android ? 10 : 8) : 12,
                  vertical: android ? 10 : 9,
                ),
                child: Row(
                  children: [
                    if (!compact && showNumber)
                      SizedBox(
                        width: 30,
                        child: Center(
                          child: isCurrent
                              ? PlayingIndicator(playing: isPlaying, size: 14)
                              : Text(
                                  number?.toString().padLeft(2, '0') ?? '',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: context.palette.textMuted),
                                ),
                        ),
                      ),
                    if (showCover) ...[
                      CoverArt(
                        imageUrl: song.coverUrl,
                        seed: song.name,
                        size: android ? AndroidSizes.listCover : (compact ? 44 : 48),
                        borderRadius: BorderRadius.circular(12),
                        iconSize: 20,
                      ),
                      const SizedBox(width: 11),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  song.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontSize: android ? 14.5 : null,
                                        fontWeight: android ? FontWeight.w600 : null,
                                        color: isCurrent
                                            ? context.palette.accent
                                            : context.palette.textPrimary,
                                      ),
                                ),
                              ),
                              if (song.isVipOnly) ...[
                                const SizedBox(width: 7),
                                TagPill(
                                  label: 'VIP',
                                  color: context.palette.gold,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${song.artist}  ·  ${song.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: android ? 12 : 12.5,
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showDuration) ...[
                      const SizedBox(width: 8),
                      Text(
                        formatDuration(song.duration),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontSize: android ? 10.5 : null,
                          color: context.palette.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    IgnorePointer(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? context.palette.accent.withValues(alpha: 0.16)
                              : context.palette.fill,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCurrent
                                ? context.palette.accent.withValues(alpha: 0.24)
                                : context.palette.line,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: isCurrent
                            ? PlayingIndicator(playing: isPlaying, size: 12)
                            : Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                                color: context.palette.textSecondary,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
