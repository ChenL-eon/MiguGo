import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/platform_kind.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/home_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/android/android_section_header.dart';
import '../widgets/android/android_shell_inset.dart';
import '../widgets/cover_art.dart';
import '../widgets/mobile_home_search.dart';
import '../widgets/playing_indicator.dart';
import '../widgets/secondary_page_frame.dart';
import '../widgets/song_tile.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import 'player_page.dart';
import 'playlist_page.dart';

/// 首页：咪咕官方每日推荐与推荐歌单的原生推送页。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isDesktopShell,
    required this.onOpenPlaylists,
    required this.onOpenAbout,
  });

  final bool isDesktopShell;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenAbout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeAutoLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<HomeProvider>().load());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 移动端内联搜索结果滚动到底部附近时自动加载下一页。
  void _maybeAutoLoadMore() {
    if (widget.isDesktopShell || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 320) return;
    final search = context.read<SearchProvider>();
    if (search.query.isEmpty || search.activeTab != SearchTab.songs) return;
    if (!search.songsHasMore || search.songsLoadingMore) return;
    if (search.songsLoadMoreError != null) return;
    unawaited(search.loadMoreSongs());
  }

  void _playSong(List<Song> songs, int index, {bool fromRow = false}) {
    unawaited(context.read<PlayerProvider>().playQueue(songs, index));
    // 桌面端双击歌曲行只起播，人留在当前列表；播放页仍能从底部播放条点开。
    if (fromRow && isDesktopPlatform) return;
    unawaited(openPlayerPage(context));
  }

  void _openPlaylist(PlaylistSummary playlist) {
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => PlaylistPage(playlistId: playlist.id)));
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final player = context.watch<PlayerProvider>();
    final search = context.watch<SearchProvider>();
    final feed = home.feed;
    final showFeed = widget.isDesktopShell || search.query.isEmpty;
    final shellInset = AndroidShellInset.of(context);
    final bottomPadding = shellInset > 0 ? shellInset + AndroidSpacing.lg : 36.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (isAndroidPlatform) {
          return _buildAndroidBody(context, home, player, search);
        }
        final width = constraints.maxWidth;
        final horizontalPadding = width >= 700 ? 40.0 : 20.0;
        return RefreshIndicator(
          onRefresh: home.refresh,
          color: context.palette.accent,
          backgroundColor: context.palette.surfaceHigh,
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                26,
                horizontalPadding,
                bottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        refreshing: home.loading,
                        onRefresh: home.loading ? null : home.refresh,
                        onOpenPlaylists: widget.onOpenPlaylists,
                      ),
                      if (!widget.isDesktopShell) ...[
                        const SizedBox(height: 20),
                        const MobileHomeSearch(),
                      ],
                      const SizedBox(height: 30),
                      if (!showFeed)
                        const SizedBox.shrink()
                      else if (home.loading && feed == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: AppLoadingView(message: '正在获取咪咕今日推荐…'),
                        )
                      else if (feed == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: AppErrorView(
                            message: home.error ?? '今日推荐暂时不可用。',
                            onRetry: home.refresh,
                          ),
                        )
                      else ...[
                        if (home.error != null) ...[
                          _RefreshErrorBanner(
                            message: home.error!,
                            onRetry: home.refresh,
                          ),
                          const SizedBox(height: 18),
                        ],
                        _PlaylistSection(
                          playlists: feed.playlists,
                          onOpen: _openPlaylist,
                        ),
                        const SizedBox(height: 36),
                        _SongColumns(
                          songs: feed.songs,
                          player: player,
                          onPlay: _playSong,
                        ),
                      ],
                      const SizedBox(height: 34),
                      _Footer(onOpenAbout: widget.onOpenAbout),
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

  /// Android 首页：标题行、胶囊搜索、双张主推歌单卡与单列推荐歌曲。
  Widget _buildAndroidBody(
    BuildContext context,
    HomeProvider home,
    PlayerProvider player,
    SearchProvider search,
  ) {
    final searching = search.query.isNotEmpty;
    final shellInset = AndroidShellInset.of(context);
    final bottomPadding = shellInset > 0 ? shellInset + AndroidSpacing.xl : 36.0;

    return RefreshIndicator(
      onRefresh: home.refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.surfaceHigh,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AndroidSpacing.md,
          AndroidSpacing.xs,
          AndroidSpacing.md,
          bottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!searching) ...[
              _AndroidHomeHeader(
                refreshing: home.loading,
                onRefresh: home.loading ? null : home.refresh,
              ),
              const SizedBox(height: AndroidSpacing.md),
            ],
            const MobileHomeSearch(),
            if (searching)
              const SizedBox(height: AndroidSpacing.md)
            else ...[
              const SizedBox(height: AndroidSpacing.xl),
              ..._buildAndroidFeed(context, home, player),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAndroidFeed(
    BuildContext context,
    HomeProvider home,
    PlayerProvider player,
  ) {
    final feed = home.feed;
    if (home.loading && feed == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: AppLoadingView(message: '正在获取咪咕今日推荐…'),
        ),
      ];
    }
    if (feed == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: AppErrorView(
            message: home.error ?? '今日推荐暂时不可用。',
            onRetry: home.refresh,
          ),
        ),
      ];
    }
    final featured = feed.playlists.take(2).toList();
    final more = feed.playlists.skip(2).take(4).toList();
    return [
      if (home.error != null) ...[
        _RefreshErrorBanner(message: home.error!, onRetry: home.refresh),
        const SizedBox(height: AndroidSpacing.lg),
      ],
      if (featured.isNotEmpty) ...[
        _AndroidFeaturedPlaylists(playlists: featured, onOpen: _openPlaylist),
        const SizedBox(height: AndroidSpacing.xl),
      ],
      if (more.isNotEmpty) ...[
        const AndroidSectionHeader(title: '精选歌单', subtitle: '官方推荐 · 每日更新'),
        const SizedBox(height: AndroidSpacing.sm),
        _AndroidPlaylistGrid(playlists: more, onOpen: _openPlaylist),
        const SizedBox(height: AndroidSpacing.xl),
      ],
      _AndroidSongSection(
        songs: feed.songs,
        player: player,
        onPlayAll: feed.songs.isEmpty ? null : () => _playSong(feed.songs, 0),
        onPlayAt: (index) => _playSong(feed.songs, index),
      ),
    ];
  }
}

class _AndroidHomeHeader extends StatelessWidget {
  const _AndroidHomeHeader({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '推荐',
                  style: AndroidTextStyles.pageTitle(palette.textPrimary),
                ),
              ),
              const SizedBox(height: AndroidSpacing.xxs),
              Text(
                '咪咕每日推荐 · 精选歌单',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AndroidTextStyles.caption(palette.textSecondary),
              ),
            ],
          ),
        ),
        _AndroidHeaderAction(
          icon: Icons.refresh_rounded,
          tooltip: '换一批',
          busy: refreshing,
          onPressed: onRefresh,
        ),
        const SizedBox(width: AndroidSpacing.xs),
        _AndroidHeaderAction(
          icon: Icons.settings_outlined,
          tooltip: '设置',
          onPressed: () => openSettingsPage(context),
        ),
      ],
    );
  }
}

class _AndroidHeaderAction extends StatelessWidget {
  const _AndroidHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceHigh.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(AndroidRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: AndroidSizes.touch,
          height: AndroidSizes.touch,
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
                )
              : Tooltip(
                  message: tooltip,
                  child: Icon(
                    icon,
                    size: AndroidSizes.icon,
                    color: palette.textSecondary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 首页顶部的两张主推歌单卡：封面即底，标题与出处叠在封面上。
class _AndroidFeaturedPlaylists extends StatelessWidget {
  const _AndroidFeaturedPlaylists({required this.playlists, required this.onOpen});

  final List<PlaylistSummary> playlists;
  final void Function(PlaylistSummary playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = playlists.length >= 2 ? 2 : 1;
        const spacing = AndroidSpacing.sm;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Row(
          children: [
            for (var i = 0; i < playlists.length; i++) ...[
              if (i != 0) const SizedBox(width: spacing),
              SizedBox(
                width: itemWidth,
                child: _AndroidHeroCard(
                  playlist: playlists[i],
                  onTap: () => onOpen(playlists[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AndroidHeroCard extends StatelessWidget {
  const _AndroidHeroCard({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final owner = playlist.ownerName.isNotEmpty ? playlist.ownerName : '咪咕精选歌单';
    final meta = playlist.songCount > 0 ? '$owner · ${playlist.songCount} 首' : owner;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AndroidRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverArt(
                imageUrl: playlist.coverUrl,
                seed: playlist.name,
                borderRadius: BorderRadius.circular(AndroidRadius.md),
                iconSize: 34,
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x0D000000), Color(0xA6000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AndroidSpacing.xs),
                    IgnorePointer(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.34),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidPlaylistGrid extends StatelessWidget {
  const _AndroidPlaylistGrid({required this.playlists, required this.onOpen});

  final List<PlaylistSummary> playlists;
  final void Function(PlaylistSummary playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 600 ? 3 : 2;
        const spacing = AndroidSpacing.sm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: AndroidSpacing.md,
          children: [
            for (final playlist in playlists)
              SizedBox(
                width: itemWidth,
                child: _RecommendedPlaylistCard(
                  playlist: playlist,
                  onTap: () => onOpen(playlist),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AndroidSongSection extends StatelessWidget {
  const _AndroidSongSection({
    required this.songs,
    required this.player,
    required this.onPlayAll,
    required this.onPlayAt,
  });

  final List<Song> songs;
  final PlayerProvider player;
  final VoidCallback? onPlayAll;
  final ValueChanged<int> onPlayAt;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AndroidSectionHeader(
          title: '每日推荐',
          subtitle: '为你更新 ${songs.length} 首歌曲',
          trailing: onPlayAll == null ? null : _AndroidRoundPlay(onPlayAll: onPlayAll!),
        ),
        const SizedBox(height: AndroidSpacing.xxs),
        for (var i = 0; i < songs.length; i++)
          SongTile(
            song: songs[i],
            isCurrent: player.currentSong?.contentId == songs[i].contentId,
            isPlaying:
                player.currentSong?.contentId == songs[i].contentId && player.isPlaying,
            showNumber: false,
            onTap: () => onPlayAt(i),
          ),
      ],
    );
  }
}

/// 分组标题右侧的圆形播放按钮，保持 48dp 触控区。
class _AndroidRoundPlay extends StatelessWidget {
  const _AndroidRoundPlay({required this.onPlayAll});

  final VoidCallback onPlayAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: '播放全部',
      excludeSemantics: true,
      child: Material(
        color: palette.accentSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onPlayAll();
          },
          child: SizedBox(
            width: AndroidSizes.touch,
            height: AndroidSizes.touch,
            child: Icon(
              Icons.play_arrow_rounded,
              size: AndroidSizes.icon,
              color: palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.refreshing,
    required this.onRefresh,
    required this.onOpenPlaylists,
  });

  final bool refreshing;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenPlaylists;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: context.palette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'MIGUGO  /  CURATED FOR YOUR DAY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.palette.textMuted,
                      fontSize: 9.5,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '在歌单上，偶遇喜欢',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: 30, letterSpacing: -0.8),
            ),
            const SizedBox(height: 8),
            Text(
              '来自咪咕的每日推荐与精选歌单，登录后会更贴近你的收听口味。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.autorenew_rounded, size: 17),
              label: const Text('换一批'),
            ),
            const SizedBox(width: 2),
            TextButton.icon(
              onPressed: onOpenPlaylists,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('更多歌单'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 10), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: actions),
          ],
        );
      },
    );
  }
}

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isAndroidPlatform) {
      return AndroidInlineError(message: message, onRetry: onRetry);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.palette.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.danger.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: context.palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _SongColumns extends StatelessWidget {
  const _SongColumns({required this.songs, required this.player, required this.onPlay});

  final List<Song> songs;
  final PlayerProvider player;
  final void Function(List<Song> songs, int index, {bool fromRow}) onPlay;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final split = (songs.length / 2).ceil();
    final leftSongs = songs.sublist(0, split);
    final rightSongs = songs.sublist(split);
    final left = _SongColumn(
      eyebrow: 'FRESH SOUNDS',
      title: '新声，先听为快',
      songs: leftSongs,
      player: player,
      onPlayAll: () => onPlay(leftSongs, 0),
      onPlayAt: (index) => onPlay(leftSongs, index, fromRow: true),
    );
    if (rightSongs.isEmpty) return left;
    final right = _SongColumn(
      eyebrow: 'ON REPEAT',
      title: '值得单曲循环',
      songs: rightSongs,
      player: player,
      onPlayAll: () => onPlay(rightSongs, 0),
      onPlayAt: (index) => onPlay(rightSongs, index, fromRow: true),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 30), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 30),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _SongColumn extends StatelessWidget {
  const _SongColumn({
    required this.eyebrow,
    required this.title,
    required this.songs,
    required this.player,
    required this.onPlayAll,
    required this.onPlayAt,
  });

  final String eyebrow;
  final String title;
  final List<Song> songs;
  final PlayerProvider player;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlayAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.palette.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontSize: 20, letterSpacing: -0.3),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onPlayAll,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 17),
              label: const Text('播放全部'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < songs.length; i++)
          _HomeSongRow(
            song: songs[i],
            number: i + 1,
            isCurrent: player.currentSong?.contentId == songs[i].contentId,
            isPlaying:
                player.currentSong?.contentId == songs[i].contentId && player.isPlaying,
            onTap: () => onPlayAt(i),
            doubleTapToPlay: isDesktopPlatform,
          ),
      ],
    );
  }
}

class _HomeSongRow extends StatelessWidget {
  const _HomeSongRow({
    required this.song,
    required this.number,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.doubleTapToPlay,
  });

  final Song song;
  final int number;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  /// 桌面端置 true：双击才起播，浏览列表时不会误触换歌。
  final bool doubleTapToPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: isCurrent ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: doubleTapToPlay ? null : onTap,
          onDoubleTap: doubleTapToPlay ? onTap : null,
          hoverColor: palette.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Center(
                    child: isCurrent
                        ? PlayingIndicator(playing: isPlaying, size: 13)
                        : Text(
                            number.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.textMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                  ),
                ),
                CoverArt(
                  imageUrl: song.coverUrl,
                  seed: song.name,
                  size: 40,
                  borderRadius: BorderRadius.circular(10),
                  iconSize: 18,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w600,
                                color: isCurrent ? palette.accent : palette.textPrimary,
                              ),
                            ),
                          ),
                          if (song.isVipOnly) ...[
                            const SizedBox(width: 6),
                            TagPill(label: 'VIP', color: palette.gold, dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDuration(song.duration),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: palette.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                IgnorePointer(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? palette.accent.withValues(alpha: 0.16)
                          : palette.fill,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent
                            ? palette.accent.withValues(alpha: 0.24)
                            : palette.line,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isCurrent
                        ? PlayingIndicator(playing: isPlaying, size: 12)
                        : Icon(
                            Icons.play_arrow_rounded,
                            size: 17,
                            color: palette.textSecondary,
                          ),
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

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({required this.playlists, required this.onOpen});

  final List<PlaylistSummary> playlists;
  final void Function(PlaylistSummary playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) return const SizedBox.shrink();
    final items = playlists.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CURATED PLAYLISTS',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.palette.textMuted,
            fontSize: 9,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '精选歌单',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 20, letterSpacing: -0.3),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '官方推荐 · 每日更新',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.palette.textMuted, fontSize: 11.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 860
                ? 6
                : width >= 440
                ? 3
                : 2;
            const spacing = 14.0;
            final itemWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: 22,
              children: [
                for (final playlist in items)
                  SizedBox(
                    width: itemWidth,
                    child: _RecommendedPlaylistCard(
                      playlist: playlist,
                      onTap: () => onOpen(playlist),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecommendedPlaylistCard extends StatelessWidget {
  const _RecommendedPlaylistCard({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    final owner = playlist.ownerName.isNotEmpty ? playlist.ownerName : '咪咕精选歌单';
    final meta = playlist.songCount > 0 ? '$owner · ${playlist.songCount} 首' : owner;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(
          padding: EdgeInsets.all(android ? 4 : 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(
                      imageUrl: playlist.coverUrl,
                      seed: playlist.name,
                      borderRadius: BorderRadius.circular(16),
                      iconSize: 30,
                    ),
                    if (playlist.playCountLabel.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.headphones_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3.5),
                              Text(
                                playlist.playCountLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: android ? 13.5 : 13,
                        height: 1.4,
                        fontWeight: android ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                        fontSize: android ? 11.5 : 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onOpenAbout});

  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 14,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'MiguGo · 个人学习练习项目 · 非咪咕官方软件',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.palette.textMuted, fontSize: 11),
                ),
              ),
              TextButton(onPressed: onOpenAbout, child: const Text('关于本项目')),
            ],
          ),
        ),
      ],
    );
  }
}
