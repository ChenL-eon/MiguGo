import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../providers/account_provider.dart';
import '../providers/desktop_lyrics_provider.dart';
import '../widgets/account_center.dart';
import '../widgets/android/android_shell_inset.dart';
import '../widgets/secondary_page_frame.dart';
import 'playlist_hub_page.dart';
import 'playlist_page.dart';

/// 移动端「我的」：账号卡、收听统计、歌单中心与设置入口。
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    if (isAndroidPlatform) return _androidBody(context, account);
    return _desktopBody(context, account);
  }

  /// Android 的「我的」：歌单页内容整块并进来，设置沉到底部。
  ///
  /// 「关于」在 Android 上收进设置页底部，这里不再单独摆一格。
  Widget _androidBody(BuildContext context, AccountProvider account) {
    final palette = context.palette;
    final shellInset = AndroidShellInset.of(context);
    final bottomPadding = shellInset > 0 ? shellInset + AndroidSpacing.lg : 36.0;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AndroidSpacing.md,
          AndroidSpacing.xs,
          AndroidSpacing.md,
          bottomPadding,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AndroidMineHeader(),
                const SizedBox(height: AndroidSpacing.md),
                const AccountSummaryCard(),
                _ProfileErrorRow(account: account),
                const SizedBox(height: AndroidSpacing.lg),
                _AndroidMineStats(account: account),
                const SizedBox(height: AndroidSpacing.xl),
                const PlaylistHubContent(showHeader: false),
                const SizedBox(height: AndroidSpacing.lg),
                _MineGroup(
                  children: [
                    _MineActionTile(
                      icon: Icons.tune_rounded,
                      title: '设置',
                      subtitle: '外观、播放、歌词、搜索与快捷键',
                      onTap: () => openSettingsPage(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '登录信息只保存在本机安全存储中，仅随公开请求发送给咪咕。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted, fontSize: 11.5, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Windows 与窄窗保持原来的「我的」结构，包括账号与播放权限入口。
  Widget _desktopBody(BuildContext context, AccountProvider account) {
    final lyrics = context.watch<DesktopLyricsProvider>();
    final isWindows = Platform.isWindows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth >= 700 ? 40.0 : 20.0;
        return Scrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, 26, padding, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('我的', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '账号、设置与关于',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const AccountSummaryCard(),
                    _ProfileErrorRow(account: account),
                    const SizedBox(height: 22),
                    _MineGroup(
                      children: [
                        _MineActionTile(
                          icon: Icons.shield_outlined,
                          title: '账号与播放权限',
                          subtitle: account.hasLogin
                              ? '管理登录信息，查看当前播放权限说明'
                              : '登录咪咕账号后使用自己的权益',
                          onTap: () => unawaited(openAccountCenter(context)),
                        ),
                        if (isWindows)
                          _MineActionTile(
                            icon: Icons.lyrics_outlined,
                            title: '桌面歌词',
                            subtitle: lyrics.enabled
                                ? '已开启，窗口正在显示置顶歌词'
                                : '把当前窗口切换为置顶歌词浮层',
                            trailing: lyrics.enabled
                                ? const Icon(Icons.check_circle_rounded)
                                : null,
                            onTap: lyrics.busy
                                ? null
                                : () => unawaited(lyrics.toggle()),
                          ),
                        _MineActionTile(
                          icon: Icons.tune_rounded,
                          title: '设置',
                          subtitle: '外观、播放、歌词、搜索与快捷键',
                          onTap: () => openSettingsPage(context),
                        ),
                        _MineActionTile(
                          icon: Icons.info_outline_rounded,
                          title: '关于 MiguGo',
                          subtitle: '用途声明、合规边界与实现说明',
                          onTap: () => openAboutPage(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '登录信息只保存在本机安全存储中，仅随公开请求发送给咪咕。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 10.5,
                        height: 1.6,
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

/// 账号资料读取失败时的提示行，两端共用。
class _ProfileErrorRow extends StatelessWidget {
  const _ProfileErrorRow({required this.account});

  final AccountProvider account;

  @override
  Widget build(BuildContext context) {
    if (!account.hasLogin || account.profileError == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              account.profileError!,
              style: TextStyle(fontSize: 10.5, color: context.palette.textMuted),
            ),
          ),
          TextButton(
            onPressed: account.profileLoading
                ? null
                : () => unawaited(account.refreshProfile()),
            child: const Text('重新读取'),
          ),
        ],
      ),
    );
  }
}

class _AndroidMineHeader extends StatelessWidget {
  const _AndroidMineHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '我的',
                  style: AndroidTextStyles.pageTitle(palette.textPrimary),
                ),
              ),
              const SizedBox(height: AndroidSpacing.xxs),
              Text('账号、歌单与设置', style: AndroidTextStyles.caption(palette.textSecondary)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => openSettingsPage(context),
          tooltip: '设置',
          style: IconButton.styleFrom(
            foregroundColor: palette.textSecondary,
            minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.settings_outlined, size: AndroidSizes.icon),
        ),
      ],
    );
  }
}

/// 「我的」顶部的收听统计：只列真实读得到的收藏与歌单数量。
///
/// 本应用不下载音频、也没有播放历史，因此参考图里的本地、已下载与最近都不做。
class _AndroidMineStats extends StatelessWidget {
  const _AndroidMineStats({required this.account});

  final AccountProvider account;

  @override
  Widget build(BuildContext context) {
    final library = account.library;
    final favorite = library?.favoritePlaylist;
    final favoriteCount = favorite?.songCount ?? 0;
    final playlistCount = library == null
        ? 0
        : library.createdPlaylists.length + library.collectedPlaylists.length;
    // 未登录时读数没有意义，直接写成「未登录」并省掉单位。
    final signedIn = account.hasLogin;
    final valuePrefix = signedIn ? null : '未登录';

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.favorite_rounded,
            label: '收藏',
            value: valuePrefix ?? (library == null ? null : '$favoriteCount'),
            unit: signedIn ? '首' : '',
            onTap: favorite == null
                ? (account.hasLogin
                      ? null
                      : () => unawaited(openAccountCenter(context)))
                : () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => PlaylistPage(playlistId: favorite.id),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: AndroidSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: Icons.queue_music_rounded,
            label: '歌单',
            value: valuePrefix ?? (library == null ? null : '$playlistCount'),
            unit: signedIn ? '个' : '',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.unit,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String unit;

  /// 读数；null 表示还没读到，用占位符而不是编造数字。
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(AndroidRadius.md),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: palette.accent),
              const SizedBox(width: 6),
              Text(label, style: AndroidTextStyles.caption(palette.textSecondary)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value ?? '—',
                style: AndroidTextStyles.headline(palette.textPrimary)
                    .copyWith(fontSize: 21),
              ),
              const SizedBox(width: 4),
              Text(
                value == null ? '' : unit,
                style: AndroidTextStyles.caption(palette.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AndroidRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, hoverColor: palette.hover, child: card),
    );
  }
}

class _MineGroup extends StatelessWidget {
  const _MineGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Container(
      padding: EdgeInsets.all(android ? AndroidSpacing.xxs : 6),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
        border: Border.all(color: context.palette.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, color: context.palette.line),
          ],
        ],
      ),
    );
  }
}

class _MineActionTile extends StatelessWidget {
  const _MineActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            android ? 10 : 12,
            android ? 9 : 12,
            android ? 8 : 10,
            android ? 9 : 12,
          ),
          child: Row(
            children: [
              Container(
                width: android ? 40 : 36,
                height: android ? 40 : 36,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(android ? 12 : 11),
                ),
                child: Icon(icon, size: android ? 20 : 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: android ? 14.5 : 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: android ? 12 : 10.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: android ? 20 : 19,
                    color: palette.textMuted,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
