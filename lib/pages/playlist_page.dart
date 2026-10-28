import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/ambient_background.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/android/android_mini_player.dart';
import '../widgets/android/android_page_top_bar.dart';
import '../widgets/android/android_section_header.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import 'player_page.dart';

/// 歌单详情页：展示公开歌单元信息与分页歌曲列表。
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeAutoLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<PlaylistProvider>().load(widget.playlistId));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Android 滚动到列表末端附近时自动续页，不再要求点「加载更多」。
  void _maybeAutoLoadMore() {
    if (!isAndroidPlatform || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 320) return;
    final playlistState = context.read<PlaylistProvider>();
    if (!playlistState.hasMore ||
        playlistState.loadingMore ||
        playlistState.loadMoreError != null) {
      return;
    }
    unawaited(playlistState.loadMore());
  }

  void _openPlayer() {
    unawaited(openPlayerPage(context));
  }

  void _playSong(List<Song> songs, int index, {bool fromRow = false}) {
    unawaited(context.read<PlayerProvider>().playQueue(songs, index));
    // 桌面端双击歌曲行只起播，人留在歌单里；播放页仍能从底部播放条点开。
    if (fromRow && isDesktopPlatform) return;
    _openPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final playlistState = context.watch<PlaylistProvider>();
    final player = context.watch<PlayerProvider>();
    final android = isAndroidPlatform;
    final refresh = playlistState.loading
        ? null
        : () => unawaited(playlistState.load(widget.playlistId, force: true));

    return Scaffold(
      backgroundColor: context.palette.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (android)
                AndroidPageTopBar(
                  title: '歌单',
                  subtitle: '咪咕公开歌单',
                  onBack: () => Navigator.of(context).maybePop(),
                  actions: [
                    IconButton(
                      onPressed: refresh,
                      tooltip: '刷新歌单',
                      style: IconButton.styleFrom(
                        foregroundColor: context.palette.textSecondary,
                        minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 22),
                    ),
                  ],
                )
              else
                _PlaylistTopBar(
                  onBack: () => Navigator.of(context).maybePop(),
                  onRefresh: refresh,
                ),
              Expanded(child: _buildBody(playlistState, player)),
              if (android)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AndroidSpacing.sm,
                    0,
                    AndroidSpacing.sm,
                    // 与壳层导航胶囊同一档留白，玻璃投影的最浓处才落得进屏幕内。
                    AndroidSpacing.md,
                  ),
                  child: AndroidMiniPlayer(onOpen: _openPlayer),
                )
              else
                MiniPlayer(onOpen: _openPlayer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PlaylistProvider playlistState, PlayerProvider player) {
    final playlist = playlistState.playlist;
    if (playlistState.loading && playlist == null) {
      return const AppLoadingView(message: '正在加载歌单…');
    }
    if (playlistState.error != null && playlist == null) {
      return AppErrorView(
        message: playlistState.error!,
        onRetry: () => unawaited(playlistState.retry()),
      );
    }
    if (playlist == null) {
      return AppEmptyView(
        title: '歌单不存在',
        message: '请检查歌单 ID 是否正确。',
        icon: Icons.queue_music_rounded,
        action: OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('返回'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final padding = android
            ? AndroidSpacing.md
            : (constraints.maxWidth >= 700 ? 36.0 : 18.0);
        return RefreshIndicator(
          onRefresh: playlistState.retry,
          color: context.palette.accent,
          backgroundColor: context.palette.surfaceHigh,
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
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
                      _PlaylistHero(
                        playlist: playlist,
                        totalCount: playlistState.totalCount > 0
                            ? playlistState.totalCount
                            : playlist.songCount,
                        onPlayAll: playlistState.songs.isEmpty
                            ? null
                            : () => _playSong(playlistState.songs, 0),
                      ),
                      SizedBox(height: android ? AndroidSpacing.lg : 26),
                      if (android)
                        AndroidSectionHeader(
                          title: '歌曲',
                          subtitle: playlistState.loading
                              ? '正在刷新歌单…'
                              : '已加载 ${playlistState.songs.length} 首'
                                    '${playlistState.totalCount > 0 ? ' / ${playlistState.totalCount}' : ''}',
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('歌曲', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                playlistState.loading
                                    ? '正在刷新歌单…'
                                    : '已加载 ${playlistState.songs.length} 首'
                                          '${playlistState.totalCount > 0 ? ' / ${playlistState.totalCount}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: android ? AndroidSpacing.xs : 10),
                      _buildSongs(playlistState, player),
                      const SizedBox(height: 18),
                      Text(
                        '歌单内容来自咪咕公开接口，仅供在线试听。VIP 歌曲的播放权限'
                        '完全以咪咕官方账号校验结果为准，可在播放页用内嵌的官方网页播放器收听；'
                        '应用不提供下载或本地音频保存。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textMuted,
                          fontSize: android ? 11.5 : 11,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongs(PlaylistProvider playlistState, PlayerProvider player) {
    final android = isAndroidPlatform;
    if (playlistState.songs.isEmpty) {
      if (playlistState.loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: AppLoadingView(message: '正在加载歌曲…'),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: context.palette.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
          border: Border.all(color: context.palette.line),
        ),
        child: const AppEmptyView(
          title: '暂时没有可播放的歌曲',
          message: '这个歌单可能已下架或内容受限，可以换一个歌单试试。',
          icon: Icons.music_off_rounded,
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(android ? AndroidSpacing.xxs : 6),
          decoration: BoxDecoration(
            color: context.palette.surface.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
            border: Border.all(color: context.palette.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < playlistState.songs.length; i++)
                SongTile(
                  song: playlistState.songs[i],
                  number: i + 1,
                  isCurrent:
                      player.currentSong?.contentId == playlistState.songs[i].contentId,
                  isPlaying:
                      player.currentSong?.contentId ==
                          playlistState.songs[i].contentId &&
                      player.isPlaying,
                  onTap: () => _playSong(playlistState.songs, i, fromRow: true),
                  doubleTapToPlay: isDesktopPlatform,
                ),
            ],
          ),
        ),
        if (playlistState.loadMoreError != null) ...[
          const SizedBox(height: 14),
          if (android)
            AndroidInlineError(
              message: playlistState.loadMoreError!,
              onRetry: () => unawaited(playlistState.loadMore()),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: context.palette.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.palette.danger.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: context.palette.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      playlistState.loadMoreError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(playlistState.loadMore()),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
        ],
        if (playlistState.hasMore) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: playlistState.loadingMore
                  ? null
                  : () => unawaited(playlistState.loadMore()),
              style: android
                  ? OutlinedButton.styleFrom(
                      minimumSize: const Size(140, AndroidSizes.touch),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AndroidRadius.pillAll,
                      ),
                    )
                  : null,
              icon: playlistState.loadingMore
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded, size: 19),
              label: Text(playlistState.loadingMore ? '正在加载…' : '加载更多'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaylistTopBar extends StatelessWidget {
  const _PlaylistTopBar({required this.onBack, required this.onRefresh});

  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          _RoundAction(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            onPressed: onBack,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '歌单',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                '咪咕公开歌单',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          _RoundAction(
            icon: Icons.refresh_rounded,
            tooltip: '刷新歌单',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: context.palette.fill,
        foregroundColor: context.palette.textSecondary,
        fixedSize: const Size(40, 40),
        side: BorderSide(color: context.palette.line),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.playlist,
    required this.totalCount,
    required this.onPlayAll,
  });

  final PlaylistSummary playlist;
  final int totalCount;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final wide = constraints.maxWidth >= 700;
        final coverSize = wide ? 178.0 : (android ? 104.0 : 118.0);
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
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Cover(playlist: playlist, size: coverSize),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _PlaylistInfo(
                        playlist: playlist,
                        totalCount: totalCount,
                        onPlayAll: onPlayAll,
                        wide: true,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Cover(playlist: playlist, size: coverSize),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _PlaylistIdentity(
                            playlist: playlist,
                            totalCount: totalCount,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    if (playlist.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        playlist.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.palette.textSecondary,
                          fontSize: 12,
                          height: 1.65,
                        ),
                      ),
                    ],
                    if (playlist.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _Tags(tags: playlist.tags),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: _PlayAllButton(onPressed: onPlayAll),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PlaylistInfo extends StatelessWidget {
  const _PlaylistInfo({
    required this.playlist,
    required this.totalCount,
    required this.onPlayAll,
    required this.wide,
  });

  final PlaylistSummary playlist;
  final int totalCount;
  final VoidCallback? onPlayAll;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlaylistIdentity(playlist: playlist, totalCount: totalCount, compact: false),
        if (playlist.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            playlist.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              fontSize: 12.5,
              height: 1.7,
            ),
          ),
        ],
        if (playlist.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Tags(tags: playlist.tags),
        ],
        const SizedBox(height: 20),
        _PlayAllButton(onPressed: onPlayAll),
      ],
    );
  }
}

class _PlaylistIdentity extends StatelessWidget {
  const _PlaylistIdentity({
    required this.playlist,
    required this.totalCount,
    required this.compact,
  });

  final PlaylistSummary playlist;
  final int totalCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    final playCount = playlist.playCountLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          playlist.name,
          maxLines: compact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: compact ? 18 : 25,
            height: 1.35,
            fontWeight: android ? FontWeight.w700 : null,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetaItem(icon: Icons.library_music_outlined, label: '$totalCount 首'),
            if (playCount.isNotEmpty && playCount != '--')
              _MetaItem(icon: Icons.headphones_rounded, label: '$playCount 播放'),
            if (playlist.ownerName.isNotEmpty)
              _MetaItem(icon: Icons.person_outline_rounded, label: playlist.ownerName),
          ],
        ),
      ],
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

class _Tags extends StatelessWidget {
  const _Tags({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags.take(5))
          TagPill(label: tag, color: context.palette.mint, dense: true),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.playlist, required this.size});

  final PlaylistSummary playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
      ),
      child: CoverArt(
        imageUrl: playlist.coverUrl,
        seed: playlist.name,
        size: size,
        borderRadius: BorderRadius.circular(18),
        iconSize: size * 0.26,
      ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return FilledButton.icon(
      onPressed: onPressed,
      style: android ? FilledButton.styleFrom(minimumSize: const Size(0, 46)) : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: const Text('播放全部'),
    );
  }
}
