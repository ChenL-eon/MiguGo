import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import 'player_page.dart';
import 'playlist_page.dart';

/// 搜索页：单曲与歌单双 Tab，按需加载、可重试。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _suggestions = ['起风了', '周杰伦', '林俊杰', '华语流行', '经典老歌', '纯音乐'];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.text = context.read<SearchProvider>().query;
    _scrollController.addListener(_maybeAutoLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 移动端滚动到底部附近时自动加载下一页。
  void _maybeAutoLoadMore() {
    if (!mounted || !_scrollController.hasClients) return;
    if (MediaQuery.sizeOf(context).width >= 960) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 280) return;
    final search = context.read<SearchProvider>();
    if (search.activeTab != SearchTab.songs) return;
    if (!search.songsHasMore || search.songsLoadingMore) return;
    if (search.songsLoadMoreError != null) return;
    unawaited(search.loadMoreSongs());
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (_controller.text != query) {
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
    }
    unawaited(context.read<SearchProvider>().submit(query));
  }

  void _useSuggestion(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _submit(value);
  }

  void _clear() {
    _controller.clear();
    context.read<SearchProvider>().clear();
    _focusNode.requestFocus();
  }

  void _playSong(List<Song> songs, int index) {
    unawaited(context.read<PlayerProvider>().playQueue(songs, index));
    // 桌面端双击歌曲行只起播，人留在搜索结果里；播放页仍能从底部播放条点开。
    if (isDesktopPlatform) return;
    unawaited(openPlayerPage(context));
  }

  void _openPlaylist(PlaylistSummary playlist) {
    Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => PlaylistPage(playlistId: playlist.id)));
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final player = context.watch<PlayerProvider>();
    final settings = context.watch<SettingsProvider>();
    final isDesktop = MediaQuery.sizeOf(context).width >= 960;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final padding = width >= 700 ? 40.0 : 20.0;
        return Scrollbar(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(padding, 26, padding, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('搜索', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(width: 16),
                        _SearchTabs(
                          activeTab: search.activeTab,
                          songCount: search.songs.length,
                          playlistCount: search.playlists.length,
                          songsLoaded: search.songs.isNotEmpty,
                          playlistsLoaded: search.playlists.isNotEmpty,
                          onChanged: (tab) => unawaited(search.setTab(tab)),
                        ),
                        if (width >= 640) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '从咪咕公开曲库中查找',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submit,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '搜索歌曲、歌手或歌单',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.search_rounded,
                            color: context.palette.textSecondary,
                            size: 22,
                          ),
                        ),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (value.text.isNotEmpty)
                                  IconButton(
                                    onPressed: _clear,
                                    tooltip: '清空',
                                    visualDensity: VisualDensity.compact,
                                    color: context.palette.textMuted,
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: IconButton(
                                    onPressed: _submit,
                                    tooltip: '搜索',
                                    style: IconButton.styleFrom(
                                      backgroundColor: context.palette.accentSoft,
                                      foregroundColor: context.palette.accent,
                                      fixedSize: const Size(36, 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 19,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildBody(search, player, settings, isDesktop: isDesktop),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    SearchProvider search,
    PlayerProvider player,
    SettingsProvider settings, {
    bool isDesktop = true,
  }) {
    if (search.query.isEmpty) {
      return _SearchLanding(
        suggestions: _suggestions,
        history: settings.searchHistory,
        onClearHistory: settings.clearSearchHistory,
        onSuggestion: _useSuggestion,
      );
    }

    final isSongs = search.activeTab == SearchTab.songs;
    final loading = isSongs ? search.songsLoading : search.playlistsLoading;
    final error = isSongs ? search.songsError : search.playlistsError;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 48),
        child: AppLoadingView(message: isSongs ? '正在搜索单曲…' : '正在搜索歌单…'),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: AppErrorView(message: error, onRetry: () => unawaited(search.retry())),
      );
    }

    if (isSongs) {
      if (search.songs.isEmpty) {
        return AppEmptyView(
          title: '没有找到相关单曲',
          message: '试试更短的关键词，或切换到“歌单”看看。',
          action: OutlinedButton(onPressed: _clear, child: const Text('重新搜索')),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultHeader(
            title: '单曲',
            caption: isDesktop
                ? '第 ${search.songsPage} 页 · 每页 ${SearchProvider.searchPageSize} 首'
                : '已加载 ${search.songs.length} 首 · 点按任意歌曲开始播放',
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surface.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.line),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (var i = 0; i < search.songs.length; i++)
                  SongTile(
                    song: search.songs[i],
                    number: i + 1,
                    isCurrent:
                        player.currentSong?.contentId == search.songs[i].contentId,
                    isPlaying:
                        player.currentSong?.contentId == search.songs[i].contentId &&
                        player.isPlaying,
                    onTap: () => _playSong(search.songs, i),
                    doubleTapToPlay: isDesktopPlatform,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (isDesktop)
            _SongPager(
              page: search.songsPage,
              hasMore: search.songsHasMore,
              onSelect: (page) {
                unawaited(search.goToSongsPage(page));
                if (_scrollController.hasClients) {
                  unawaited(
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    ),
                  );
                }
              },
            )
          else if (search.songsLoadMoreError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '加载更多失败：${search.songsLoadMoreError}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.palette.danger, fontSize: 11.5),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => unawaited(search.loadMoreSongs()),
                  child: const Text('重试'),
                ),
              ],
            )
          else if (search.songsLoadingMore)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '正在加载更多…',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.palette.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else if (search.songsHasMore)
            Center(
              child: Text(
                '继续上滑，自动加载更多',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted, fontSize: 11),
              ),
            )
          else
            Text(
              '已显示全部 ${search.songs.length} 首结果。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.textMuted, fontSize: 11),
            ),
        ],
      );
    }

    if (search.playlists.isEmpty) {
      return AppEmptyView(
        title: '没有找到相关歌单',
        message: '换一个关键词，或切换到“单曲”直接播放。',
        icon: Icons.queue_music_rounded,
        action: OutlinedButton(onPressed: _clear, child: const Text('重新搜索')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultHeader(title: '歌单', caption: '找到 ${search.playlists.length} 个公开歌单'),
        const SizedBox(height: 10),
        for (var i = 0; i < search.playlists.length; i++) ...[
          _PlaylistResultTile(
            playlist: search.playlists[i],
            onTap: () => _openPlaylist(search.playlists[i]),
          ),
          if (i != search.playlists.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SongPager extends StatelessWidget {
  const _SongPager({required this.page, required this.hasMore, required this.onSelect});

  final int page;
  final bool hasMore;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final maxKnownPage = page + (hasMore ? 1 : 0);
    final pages = <int>{
      1,
      page - 1,
      page,
      page + 1,
    }.where((value) => value >= 1 && value <= maxKnownPage).toList()..sort();

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onSelect(page - 1) : null,
            tooltip: '上一页',
            visualDensity: VisualDensity.compact,
            color: context.palette.textSecondary,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          const SizedBox(width: 2),
          for (var i = 0; i < pages.length; i++) ...[
            if (i > 0 && pages[i] - pages[i - 1] > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '…',
                  style: TextStyle(fontSize: 12, color: context.palette.textMuted),
                ),
              ),
            _PageChip(
              page: pages[i],
              selected: pages[i] == page,
              onTap: () => onSelect(pages[i]),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 2),
          IconButton(
            onPressed: hasMore ? () => onSelect(page + 1) : null,
            tooltip: '下一页',
            visualDensity: VisualDensity.compact,
            color: context.palette.textSecondary,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _PageChip extends StatelessWidget {
  const _PageChip({required this.page, required this.selected, required this.onTap});

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.palette.accent : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: selected ? Colors.transparent : context.palette.line),
      ),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        hoverColor: context.palette.hover,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Text(
              '$page',
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? context.palette.onAccent
                    : context.palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchTabs extends StatelessWidget {
  const _SearchTabs({
    required this.activeTab,
    required this.songCount,
    required this.playlistCount,
    required this.songsLoaded,
    required this.playlistsLoaded,
    required this.onChanged,
  });

  final SearchTab activeTab;
  final int songCount;
  final int playlistCount;
  final bool songsLoaded;
  final bool playlistsLoaded;
  final ValueChanged<SearchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabChip(
            label: '单曲',
            count: songsLoaded ? songCount : null,
            selected: activeTab == SearchTab.songs,
            onTap: () => onChanged(SearchTab.songs),
          ),
          const SizedBox(width: 4),
          _TabChip(
            label: '歌单',
            count: playlistsLoaded ? playlistCount : null,
            selected: activeTab == SearchTab.playlists,
            onTap: () => onChanged(SearchTab.playlists),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? context.palette.accent
                      : context.palette.textSecondary,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: selected
                        ? context.palette.accent.withValues(alpha: 0.75)
                        : context.palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.palette.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _SearchLanding extends StatelessWidget {
  const _SearchLanding({
    required this.suggestions,
    required this.history,
    required this.onClearHistory,
    required this.onSuggestion,
  });

  final List<String> suggestions;
  final List<String> history;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (history.isNotEmpty) ...[
          const SizedBox(height: 26),
          Row(
            children: [
              Text(
                '最近搜索',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onClearHistory,
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.textMuted,
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final query in history)
                _SuggestionChip(
                  label: query,
                  icon: Icons.history_rounded,
                  onTap: () => onSuggestion(query),
                ),
            ],
          ),
          const SizedBox(height: 26),
        ] else
          const SizedBox(height: 26),
        Text(
          '试试这些',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final suggestion in suggestions)
              _SuggestionChip(label: suggestion, onTap: () => onSuggestion(suggestion)),
          ],
        ),
        const SizedBox(height: 36),
        const _SearchTip(),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
    this.icon = Icons.north_west_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        hoverColor: context.palette.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: context.palette.textMuted),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTip extends StatelessWidget {
  const _SearchTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.accent.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: context.palette.accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: context.palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'VIP 歌曲会在列表中标注。免费歌曲和已登录账号的 VIP 歌曲都用原生播放器；'
              '如果咪咕没有为某首曲目发放地址，可在播放页点“官方页面播放”，'
              '由内嵌的咪咕官方网页播放器完成登录与鉴权。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: 11.5,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistResultTile extends StatelessWidget {
  const _PlaylistResultTile({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.palette.hover,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.line),
          ),
          child: Row(
            children: [
              CoverArt(
                imageUrl: playlist.coverUrl,
                seed: playlist.name,
                size: 62,
                borderRadius: BorderRadius.circular(12),
                iconSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${playlist.songCount} 首 · ${playlist.playCountLabel} 播放',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: context.palette.textSecondary,
                      ),
                    ),
                    if (playlist.tags.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final tag in playlist.tags.take(3))
                            TagPill(
                              label: tag,
                              color: context.palette.mint,
                              dense: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.palette.fill,
                  border: Border.all(color: context.palette.line),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
