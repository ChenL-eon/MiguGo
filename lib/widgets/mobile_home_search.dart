import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../pages/player_page.dart';
import '../pages/playlist_page.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/android/android_search_field.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/state_views.dart';

/// 移动端首页内联搜索：输入关键词后直接在当前页面展示结果。
class MobileHomeSearch extends StatefulWidget {
  const MobileHomeSearch({super.key});

  @override
  State<MobileHomeSearch> createState() => _MobileHomeSearchState();
}

class _MobileHomeSearchState extends State<MobileHomeSearch> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final SearchProvider _search;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _search = context.read<SearchProvider>();
    _lastQuery = _search.query;
    _controller.text = _lastQuery;
    _search.addListener(_syncFromProvider);
  }

  @override
  void dispose() {
    _search.removeListener(_syncFromProvider);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 系统返回键会清空搜索，这里同步输入框，避免残留上一次的关键词。
  void _syncFromProvider() {
    final query = _search.query;
    if (query.isEmpty && _lastQuery.isNotEmpty) {
      _controller.clear();
    }
    _lastQuery = query;
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

  void _clear() {
    _controller.clear();
    context.read<SearchProvider>().clear();
    _focusNode.requestFocus();
  }

  /// 空态里的「重新搜索」：Android 用整宽胶囊主按钮，桌面保持描边样式。
  Widget _emptyAction(BuildContext context) {
    if (!isAndroidPlatform) {
      return OutlinedButton(onPressed: _clear, child: const Text('重新搜索'));
    }
    return FilledButton.tonalIcon(
      onPressed: () {
        unawaited(HapticFeedback.selectionClick());
        _clear();
      },
      style: FilledButton.styleFrom(
        backgroundColor: context.palette.accentSoft,
        foregroundColor: context.palette.accent,
        minimumSize: const Size(160, AndroidSizes.touch),
        shape: const RoundedRectangleBorder(borderRadius: AndroidRadius.pillAll),
        textStyle: AndroidTextStyles.action(context.palette.accent),
      ),
      icon: const Icon(Icons.search_rounded, size: AndroidSizes.smallIcon),
      label: const Text('重新搜索'),
    );
  }

  void _playSong(List<Song> songs, int index) {
    unawaited(context.read<PlayerProvider>().playQueue(songs, index));
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
    final android = isAndroidPlatform;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (android)
          AndroidSearchField(
            controller: _controller,
            focusNode: _focusNode,
            onSubmitted: _submit,
            onClear: _clear,
          )
        else
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
                          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        if (search.query.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SearchResultTabs(
            tab: search.activeTab,
            onChanged: (tab) => unawaited(search.setTab(tab)),
          ),
          const SizedBox(height: 14),
          _buildResults(search, player),
        ],
      ],
    );
  }

  Widget _buildResults(SearchProvider search, PlayerProvider player) {
    final isSongs = search.activeTab == SearchTab.songs;
    final loading = isSongs ? search.songsLoading : search.playlistsLoading;
    final error = isSongs ? search.songsError : search.playlistsError;

    if (loading) {
      if (isAndroidPlatform) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AndroidSpacing.lg),
          child: AppLoadingView(message: '正在搜索…'),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (error != null) {
      return AppErrorView(message: error, onRetry: () => unawaited(search.retry()));
    }

    if (isSongs) {
      if (search.songs.isEmpty) {
        return AppEmptyView(
          title: '没有找到相关单曲',
          message: '换一个关键词，或切换到“歌单”看看。',
          action: _emptyAction(context),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultCaption(title: '单曲', caption: '已加载 ${search.songs.length} 首 · 点按开始播放'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.palette.surface.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.line),
            ),
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
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (search.songsLoadMoreError != null)
            if (isAndroidPlatform)
              AndroidInlineError(
                title: '加载更多失败',
                message: search.songsLoadMoreError!,
                onRetry: () => unawaited(search.loadMoreSongs()),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '加载更多失败：${search.songsLoadMoreError}',
                      style: TextStyle(fontSize: 11.5, color: context.palette.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(search.loadMoreSongs()),
                    child: const Text('重试'),
                  ),
                ],
              )
          else if (search.songsLoadingMore)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      );
    }

    if (search.playlists.isEmpty) {
      return AppEmptyView(
        title: '没有找到相关歌单',
        message: '换一个关键词，或切换到“单曲”直接播放。',
        icon: Icons.queue_music_rounded,
        action: _emptyAction(context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultCaption(title: '歌单', caption: '找到 ${search.playlists.length} 个公开歌单'),
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

class _SearchResultTabs extends StatelessWidget {
  const _SearchResultTabs({required this.tab, required this.onChanged});

  final SearchTab tab;
  final ValueChanged<SearchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    Widget chip(String label, SearchTab value) {
      final child = _TabChip(
        label: label,
        selected: tab == value,
        onTap: () => onChanged(value),
        expanded: android,
      );
      return android ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 13),
        border: Border.all(color: context.palette.line),
      ),
      child: Row(
        mainAxisSize: android ? MainAxisSize.max : MainAxisSize.min,
        children: [
          chip('单曲', SearchTab.songs),
          const SizedBox(width: 4),
          chip('歌单', SearchTab.playlists),
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
    this.expanded = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Material(
      color: selected ? context.palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(android ? 11 : 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(android ? 11 : 10),
        child: Container(
          constraints: android
              ? const BoxConstraints(minHeight: AndroidSizes.touch)
              : null,
          height: expanded ? (android ? AndroidSizes.touch : 42.0) : null,
          alignment: android || expanded ? Alignment.center : null,
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: expanded ? 0 : (android ? AndroidSpacing.xs : 8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: android ? 13.5 : 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? context.palette.accent : context.palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCaption extends StatelessWidget {
  const _ResultCaption({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: android
              ? AndroidTextStyles.sectionTitle(context.palette.textPrimary)
              : Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontSize: android ? 11.5 : 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistResultTile extends StatelessWidget {
  const _PlaylistResultTile({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    final radius = BorderRadius.circular(android ? AndroidRadius.md : 16);
    return Material(
      color: context.palette.surface.withValues(alpha: 0.55),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.palette.hover,
        child: Container(
          padding: EdgeInsets.all(android ? 12 : 11),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: context.palette.line),
          ),
          child: Row(
            children: [
              CoverArt(
                imageUrl: playlist.coverUrl,
                seed: playlist.name,
                size: android ? AndroidSizes.listCover : 58,
                borderRadius: BorderRadius.circular(android ? 14 : 12),
                iconSize: 22,
              ),
              SizedBox(width: android ? 14 : 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: android
                          ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${playlist.songCount} 首 · ${playlist.playCountLabel} 播放',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
