import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/account_library.dart';
import '../models/playlist.dart';
import '../providers/account_provider.dart';
import 'android/android_feedback.dart';
import 'android/android_skeleton.dart';
import 'cover_art.dart';

/// 歌单页顶部的「我的音乐」：登录后展示账号的我喜欢、自建与收藏歌单。
class AccountMusicSection extends StatefulWidget {
  const AccountMusicSection({
    super.key,
    required this.onLogin,
    required this.onOpenPlaylist,
  });

  final VoidCallback onLogin;
  final void Function(String playlistId) onOpenPlaylist;

  @override
  State<AccountMusicSection> createState() => _AccountMusicSectionState();
}

class _AccountMusicSectionState extends State<AccountMusicSection> {
  @override
  void initState() {
    super.initState();
    // 启动时如果账号已登录，进来就把歌单补上；失败会落到重试卡片。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final account = context.read<AccountProvider>();
      if (account.hasLogin && account.library == null && !account.libraryLoading) {
        unawaited(account.refreshLibrary());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final library = account.library;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          account: account,
          onRefresh: () => unawaited(account.refreshLibrary(force: true)),
        ),
        const SizedBox(height: 12),
        if (!account.hasLogin)
          _LoginCard(onLogin: widget.onLogin)
        else if (library == null && account.libraryLoading)
          const _LoadingCard()
        else if (library == null && account.libraryError != null)
          _ErrorCard(
            message: account.libraryError!,
            onRetry: () => unawaited(account.refreshLibrary(force: true)),
          )
        else if (library == null)
          _IdleCard(onLoad: () => unawaited(account.refreshLibrary()))
        else if (library.isEmpty)
          const _EmptyCard()
        else
          ..._buildContent(library),
      ],
    );
  }

  List<Widget> _buildContent(AccountLibrary library) {
    final favorite = library.favoritePlaylist;
    return [
      if (favorite != null)
        _FavoriteCard(
          playlist: favorite,
          onTap: () => widget.onOpenPlaylist(favorite.id),
        ),
      if (library.createdPlaylists.isNotEmpty) ...[
        if (favorite != null) const SizedBox(height: 18),
        _PlaylistGroup(
          title: '自建歌单',
          playlists: library.createdPlaylists,
          onOpenPlaylist: widget.onOpenPlaylist,
        ),
      ],
      if (library.collectedPlaylists.isNotEmpty) ...[
        const SizedBox(height: 18),
        _PlaylistGroup(
          title: '收藏的歌单',
          playlists: library.collectedPlaylists,
          onOpenPlaylist: widget.onOpenPlaylist,
        ),
      ],
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.account, required this.onRefresh});

  final AccountProvider account;
  final VoidCallback onRefresh;

  String _subtitle() {
    if (!account.hasLogin) return '登录后自动同步';
    final library = account.library;
    final parts = <String>[
      if (library?.favoritePlaylist != null) '我喜欢',
      if (library != null && library.createdPlaylists.isNotEmpty)
        '自建 ${library.createdPlaylists.length}',
      if (library != null && library.collectedPlaylists.isNotEmpty)
        '收藏 ${library.collectedPlaylists.length}',
    ];
    if (parts.isEmpty) return '与 ${account.displayName} 的咪咕账号同步';
    return '${parts.join(' · ')} · ${account.displayName}';
  }

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '我的音乐',
          style: android
              ? AndroidTextStyles.sectionTitle(context.palette.textPrimary)
              : Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              _subtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textMuted,
                fontSize: android ? 11.5 : 11,
              ),
            ),
          ),
        ),
        if (account.hasLogin)
          IconButton(
            onPressed: account.libraryLoading ? null : onRefresh,
            tooltip: '刷新账号歌单',
            visualDensity: android ? VisualDensity.standard : VisualDensity.compact,
            style: android
                ? IconButton.styleFrom(
                    minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
                    padding: EdgeInsets.zero,
                  )
                : null,
            color: context.palette.textMuted,
            icon: account.libraryLoading
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh_rounded, size: android ? 21 : 19),
          ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return _SectionCard(
      child: Row(
        children: [
          _IconBadge(icon: Icons.favorite_rounded, tint: context.palette.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录后自动读取账号歌单',
                  style: android
                      ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                      : Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '我喜欢的音乐、自建歌单与收藏的歌单会显示在这里，只读不改动账号内容。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textMuted,
                    fontSize: android ? 12 : 11.5,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onLogin,
            style: android
                ? FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  )
                : null,
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    if (isAndroidPlatform) {
      // 手机端用骨架占住列表版面，数据到位后不会跳版。
      return _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '正在读取账号歌单…',
              style: AndroidTextStyles.caption(context.palette.textSecondary),
            ),
            const SizedBox(height: AndroidSpacing.md),
            const AndroidSkeleton(
              child: Column(
                children: [
                  _SkeletonRow(),
                  SizedBox(height: AndroidSpacing.sm),
                  _SkeletonRow(),
                  SizedBox(height: AndroidSpacing.sm),
                  _SkeletonRow(),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _SectionCard(
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.palette.accent,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '正在读取账号歌单…',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: 44, height: 44, radius: AndroidRadius.xs),
        SizedBox(width: AndroidSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(height: 12, width: 176),
              SizedBox(height: 6),
              SkeletonLine(height: 10, width: 104),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (isAndroidPlatform) {
      return AndroidInlineError(message: message, onRetry: onRetry);
    }
    return _SectionCard(
      tint: palette.danger,
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
                fontSize: 11.5,
                height: 1.55,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.onLoad});

  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          _IconBadge(icon: Icons.library_music_rounded, tint: context.palette.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '登录凭据已保存，还没有读取账号歌单。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.textSecondary, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onLoad, child: const Text('读取')),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          _IconBadge(icon: Icons.queue_music_rounded, tint: context.palette.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这个账号还没有歌单', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '在咪咕音乐里喜欢歌曲、创建或收藏歌单后，回来刷新即可。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 11.5,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    final tint = palette.danger;
    final radius = BorderRadius.circular(android ? AndroidRadius.md : 20);
    final meta = playlist.songCount > 0
        ? '${playlist.songCount} 首 · 账号收藏的单曲'
        : '账号收藏的单曲';
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: tint.withValues(alpha: 0.22)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: 0.16),
              palette.surfaceHigh.withValues(alpha: 0.82),
            ],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          hoverColor: palette.hover,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CoverArt(
                  imageUrl: playlist.coverUrl,
                  seed: playlist.name,
                  size: 64,
                  borderRadius: BorderRadius.circular(16),
                  iconSize: 25,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.favorite_rounded, size: 15, color: tint),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: android
                                  ? AndroidTextStyles.listTitle(palette.textPrimary)
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          fontSize: android ? 12 : 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 20, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistGroup extends StatelessWidget {
  const _PlaylistGroup({
    required this.title,
    required this.playlists,
    required this.onOpenPlaylist,
  });

  final String title;
  final List<PlaylistSummary> playlists;
  final void Function(String playlistId) onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: android
                  ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                  : Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            Text(
              '${playlists.length} 个',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textMuted,
                fontSize: android ? 11.5 : 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (android)
          _PlaylistRowList(playlists: playlists, onOpenPlaylist: onOpenPlaylist)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 860
                  ? 4
                  : width >= 440
                  ? 3
                  : 2;
              final itemWidth = (width - 14 * (columns - 1)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 18,
                children: [
                  for (final playlist in playlists)
                    SizedBox(
                      width: itemWidth,
                      child: _PlaylistCard(
                        playlist: playlist,
                        onTap: () => onOpenPlaylist(playlist.id),
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

/// 手机端的歌单行列表：封面 + 名称 + 曲目数，一行一个，单手好点。
class _PlaylistRowList extends StatelessWidget {
  const _PlaylistRowList({required this.playlists, required this.onOpenPlaylist});

  final List<PlaylistSummary> playlists;
  final void Function(String playlistId) onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AndroidSpacing.xxs),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(AndroidRadius.md),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < playlists.length; i++) ...[
            _PlaylistRowTile(
              playlist: playlists[i],
              onTap: () => onOpenPlaylist(playlists[i].id),
            ),
            if (i != playlists.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Divider(height: 1, color: palette.line),
              ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistRowTile extends StatelessWidget {
  const _PlaylistRowTile({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = playlist.songCount > 0 ? '${playlist.songCount} 首歌' : '暂无曲目数';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AndroidRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          child: Row(
            children: [
              CoverArt(
                imageUrl: playlist.coverUrl,
                seed: playlist.name,
                size: AndroidSizes.listCover,
                borderRadius: BorderRadius.circular(12),
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AndroidTextStyles.listTitle(palette.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AndroidTextStyles.caption(palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final owner = playlist.ownerName.isNotEmpty ? playlist.ownerName : '咪咕歌单';
    final meta = playlist.songCount > 0 ? '$owner · ${playlist.songCount} 首' : owner;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CoverArt(
                  imageUrl: playlist.coverUrl,
                  seed: playlist.name,
                  borderRadius: BorderRadius.circular(16),
                  iconSize: 30,
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
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary, fontSize: 10.5),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    final color = tint ?? palette.surface;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        android ? 14 : 16,
        android ? 12 : 14,
        android ? 10 : 12,
        android ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tint == null ? 0.48 : 0.07),
        borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
        border: Border.all(
          color: tint == null ? palette.line : tint!.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, size: 23, color: tint),
    );
  }
}
