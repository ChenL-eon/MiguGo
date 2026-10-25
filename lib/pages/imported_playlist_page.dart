import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/external_playlist_urls.dart';
import '../core/utils/formatters.dart';
import '../core/utils/platform_kind.dart';
import '../models/imported_playlist.dart';
import '../providers/player_provider.dart';
import '../widgets/ambient_background.dart';
import '../widgets/android/android_mini_player.dart';
import '../widgets/android/android_page_top_bar.dart';
import '../widgets/android/android_section_header.dart';
import '../widgets/cover_art.dart';
import '../widgets/external_platform_tag.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import 'player_page.dart';

/// 已导入歌单详情：只展示成功匹配到的咪咕曲目。
class ImportedPlaylistPage extends StatelessWidget {
  const ImportedPlaylistPage({super.key, required this.playlist});

  final ImportedPlaylist playlist;

  void _openPlayer(BuildContext context) {
    unawaited(openPlayerPage(context));
  }

  void _playSong(BuildContext context, int index, {bool fromRow = false}) {
    if (playlist.songs.isEmpty) return;
    unawaited(context.read<PlayerProvider>().playQueue(playlist.songs, index));
    // 桌面端双击歌曲行只起播，人留在导入歌单里；播放页仍能从底部播放条点开。
    if (fromRow && isDesktopPlatform) return;
    _openPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final android = isAndroidPlatform;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (android)
                AndroidPageTopBar(
                  title: '导入歌单',
                  subtitle: '${playlist.platform.label} · 本机保存',
                  onBack: () => Navigator.of(context).maybePop(),
                  actions: [
                    TagPill(
                      label: '仅在线播放',
                      color: context.palette.mint,
                      icon: Icons.cloud_outlined,
                      dense: true,
                    ),
                    const SizedBox(width: AndroidSpacing.sm),
                  ],
                )
              else
                _TopBar(
                  platformLabel: playlist.platform.label,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              Expanded(child: _buildBody(context, player)),
              if (android)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AndroidSpacing.sm,
                    0,
                    AndroidSpacing.sm,
                    // 与壳层导航胶囊同一档留白，玻璃投影的最浓处才落得进屏幕内。
                    AndroidSpacing.md,
                  ),
                  child: AndroidMiniPlayer(onOpen: () => _openPlayer(context)),
                )
              else
                MiniPlayer(onOpen: () => _openPlayer(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PlayerProvider player) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final padding = android
            ? AndroidSpacing.md
            : (constraints.maxWidth >= 700 ? 36.0 : 18.0);
        return Scrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              android ? AndroidSpacing.xs : 4,
              padding,
              android ? AndroidSpacing.xl : 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hero(
                      playlist: playlist,
                      onPlayAll: playlist.songs.isEmpty
                          ? null
                          : () => _playSong(context, 0),
                    ),
                    if (playlist.limitNote.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _LimitNote(message: playlist.limitNote),
                    ],
                    SizedBox(height: android ? AndroidSpacing.lg : 24),
                    if (android)
                      AndroidSectionHeader(
                        title: '匹配到的歌曲',
                        subtitle: '${playlist.matchedCount} 首',
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '匹配到的歌曲',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${playlist.matchedCount} 首',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: android ? AndroidSpacing.xs : 10),
                    _buildSongs(context, player),
                    if (playlist.unmatchedTitles.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _UnmatchedSection(titles: playlist.unmatchedTitles),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      '这些曲目来自咪咕曲库，播放权限跟随咪咕官方账号；'
                      'VIP 曲目可在播放页用内嵌的官方网页播放器收听。'
                      '应用不提供下载或本地音频保存。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textMuted,
                        fontSize: isAndroidPlatform ? 11.5 : 11,
                        height: 1.7,
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

  Widget _buildSongs(BuildContext context, PlayerProvider player) {
    final android = isAndroidPlatform;
    if (playlist.songs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: context.palette.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
          border: Border.all(color: context.palette.line),
        ),
        child: const AppEmptyView(
          title: '没有匹配到歌曲',
          message: '可以重新导入这个歌单，或换一个歌单试试。',
          icon: Icons.music_off_rounded,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(android ? AndroidSpacing.xxs : 6),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
        border: Border.all(color: context.palette.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < playlist.songs.length; i++)
            SongTile(
              song: playlist.songs[i],
              number: i + 1,
              isCurrent: player.currentSong?.contentId == playlist.songs[i].contentId,
              isPlaying:
                  player.currentSong?.contentId == playlist.songs[i].contentId &&
                  player.isPlaying,
              onTap: () => _playSong(context, i, fromRow: true),
              doubleTapToPlay: isDesktopPlatform,
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.platformLabel, required this.onBack});

  final String platformLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: '返回',
            style: IconButton.styleFrom(
              backgroundColor: context.palette.fill,
              foregroundColor: context.palette.textSecondary,
              fixedSize: const Size(40, 40),
              side: BorderSide(color: context.palette.line),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '导入歌单',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                '$platformLabel · 本机保存',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          TagPill(
            label: '仅在线播放',
            color: context.palette.mint,
            icon: Icons.cloud_outlined,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.playlist, required this.onPlayAll});

  final ImportedPlaylist playlist;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final wide = constraints.maxWidth >= 700;
        final coverSize = wide ? 150.0 : (android ? 92.0 : 96.0);
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(wide ? 24 : (android ? 14 : 16)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 24),
            border: Border.all(color: context.palette.line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.palette.accent.withValues(alpha: 0.1),
                context.palette.surfaceHigh.withValues(alpha: 0.86),
                context.palette.surfaceSoft.withValues(alpha: 0.9),
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(
                imageUrl: playlist.coverUrl,
                seed: playlist.name,
                size: coverSize,
                borderRadius: BorderRadius.circular(18),
                iconSize: coverSize * 0.26,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: wide ? 25 : 18,
                        height: 1.35,
                        fontWeight: android ? FontWeight.w700 : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ExternalPlatformTag(platform: playlist.platform, dense: !wide),
                        _MetaItem(
                          icon: Icons.check_circle_outline_rounded,
                          label: '匹配 ${playlist.matchedCount} 首',
                        ),
                        _MetaItem(
                          icon: Icons.travel_explore_rounded,
                          label: '扫描 ${playlist.scannedTracks} 首',
                        ),
                        if (playlist.totalTracks > playlist.scannedTracks)
                          _MetaItem(
                            icon: Icons.library_music_outlined,
                            label: '原歌单 ${playlist.totalTracks} 首',
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${formatDate(playlist.importedAt)} 导入 · '
                      '未匹配 ${playlist.unmatchedCount} 首',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textMuted,
                        fontSize: android ? 12 : 11,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onPlayAll,
                      style: android
                          ? FilledButton.styleFrom(minimumSize: const Size(0, 46))
                          : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('播放全部'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: android ? 14 : 13, color: context.palette.textMuted),
        const SizedBox(width: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.palette.textSecondary,
            fontSize: android ? 12 : 11.5,
          ),
        ),
      ],
    );
  }
}

class _LimitNote extends StatelessWidget {
  const _LimitNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tint = context.palette.gold;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: isAndroidPlatform ? 12 : 11,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 15, color: tint),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: isAndroidPlatform ? 12 : 11.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnmatchedSection extends StatelessWidget {
  const _UnmatchedSection({required this.titles});

  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            Icons.remove_circle_outline_rounded,
            size: android ? 22 : 20,
            color: context.palette.textMuted,
          ),
          title: Text(
            '未匹配的歌曲（${titles.length}）',
            style: android
                ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                : Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            '这些曲目没有在咪咕曲库找到对应版本，已跳过。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontSize: android ? 12 : 10.5,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          children: [
            for (final title in titles)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '· $title',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                      fontSize: android ? 12 : 11.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
