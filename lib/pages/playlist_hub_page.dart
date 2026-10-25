import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/navigation/app_page_route.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/platform_kind.dart';
import '../models/imported_playlist.dart';
import '../providers/imported_playlist_provider.dart';
import '../widgets/account_center.dart';
import '../widgets/account_music_section.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/android/android_section_header.dart';
import '../widgets/android/android_sheet.dart';
import '../widgets/android/android_shell_inset.dart';
import '../widgets/cover_art.dart';
import '../widgets/external_platform_tag.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import 'imported_playlist_page.dart';
import 'playlist_page.dart';

/// 歌单页外壳：桌面端与 Windows 窄窗使用，Android 把 [PlaylistHubContent] 嵌进「我的」。
class PlaylistHubPage extends StatelessWidget {
  const PlaylistHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    final shellInset = AndroidShellInset.of(context);
    final bottomPadding = shellInset > 0 ? shellInset + AndroidSpacing.lg : 36.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final padding = android ? AndroidSpacing.md : (width >= 700 ? 40.0 : 20.0);
        return Scrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              android ? AndroidSpacing.xs : 26,
              padding,
              bottomPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: const PlaylistHubContent(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 打开外部歌单导入流程：手机端是底部操作表，桌面端是对话框。
///
/// 「我的」里的导入入口与歌单页顶部按钮共用这一段，避免两处行为漂移。
Future<void> openPlaylistImportDialog(BuildContext context) async {
  final imported = context.read<ImportedPlaylistProvider>();
  final ok = isAndroidPlatform
      ? await showAndroidSheet<bool>(
          context: context,
          title: '导入外部歌单',
          subtitle: '支持网易云、QQ音乐、酷狗等平台的公开歌单分享链接',
          isDismissible: false,
          enableDrag: false,
          builder: (_) => const _ImportDialog(),
        )
      : await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _ImportDialog(),
        );
  if (!context.mounted) return;
  // 关掉面板后卡片里的失败原因就看不到了，这里在页面级再补一句。
  // 取消导入不报错，只有确实失败过才提示。
  if (ok != true) {
    final failure = imported.error;
    if (failure != null) _showPlaylistMessage(context, failure, isError: true);
    return;
  }
  final playlist = imported.lastImport;
  _showPlaylistMessage(
    context,
    playlist == null
        ? '歌单导入完成。'
        : '《${playlist.name}》导入完成，匹配 ${playlist.matchedCount} 首。',
  );
}

void _showPlaylistMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  if (!context.mounted) return;
  if (isAndroidPlatform) {
    showAndroidSnack(context, message, isError: isError);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 歌单页正文：账号歌单、外部导入结果与云盘说明。
///
/// Android 的「我的」内嵌时把 [showHeader] 关掉，页面标题由「我的」自己给出。
class PlaylistHubContent extends StatelessWidget {
  const PlaylistHubContent({super.key, this.showHeader = true});

  final bool showHeader;

  void _openImportedPlaylist(BuildContext context, ImportedPlaylist playlist) {
    Navigator.of(context).push(
      AppPageRoute<void>(builder: (_) => ImportedPlaylistPage(playlist: playlist)),
    );
  }

  void _openMiguPlaylist(BuildContext context, String playlistId) {
    Navigator.of(context)
        .push(AppPageRoute<void>(builder: (_) => PlaylistPage(playlistId: playlistId)));
  }

  Future<void> _remove(BuildContext context, ImportedPlaylist playlist) async {
    final provider = context.read<ImportedPlaylistProvider>();
    final confirmed = isAndroidPlatform
        ? await showAndroidConfirm(
            context,
            title: '移除导入歌单',
            message:
                '从本机移除《${playlist.name}》的导入结果？'
                '原平台的歌单不会受影响。',
            confirmLabel: '移除',
            destructive: true,
            icon: Icons.delete_outline_rounded,
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('移除导入歌单'),
              content: Text('从本机移除《${playlist.name}》的导入结果？原平台的歌单不会受影响。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('移除'),
                ),
              ],
            ),
          );
    if (confirmed != true) return;
    await provider.remove(playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    final imported = context.watch<ImportedPlaylistProvider>();
    final lastImport = imported.lastImport;
    final android = isAndroidPlatform;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          if (android)
            _AndroidHubHeader(
              onImport: () => unawaited(openPlaylistImportDialog(context)),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('歌单', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '咪咕账号歌单与外部歌单导入',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: context.palette.textMuted, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => unawaited(openPlaylistImportDialog(context)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.playlist_add_rounded, size: 19),
                  label: const Text('导入歌单'),
                ),
              ],
            ),
        if (lastImport != null && !imported.importing) ...[
          SizedBox(height: showHeader ? (android ? AndroidSpacing.md : 36) : 0),
          _ImportResultCard(
            playlist: lastImport,
            onOpen: () => _openImportedPlaylist(context, lastImport),
          ),
        ],
        SizedBox(height: showHeader ? (android ? AndroidSpacing.xl : 28) : 0),
        AccountMusicSection(
          onLogin: () => unawaited(openAccountCenter(context)),
          onOpenPlaylist: (id) => _openMiguPlaylist(context, id),
        ),
        SizedBox(height: android ? AndroidSpacing.xl : 30),
        if (android)
          AndroidSectionHeader(
            title: '我的导入',
            subtitle: imported.playlists.isEmpty
                ? '结果只保存在本机'
                : '${imported.playlists.length} 个歌单 · 只保存在本机',
            trailing: _ImportTextButton(
              onPressed: () => unawaited(openPlaylistImportDialog(context)),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('我的导入', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 10),
              Text(
                imported.playlists.isEmpty
                    ? '结果只保存在本机'
                    : '${imported.playlists.length} 个歌单 · 只保存在本机',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted, fontSize: 11),
              ),
            ],
          ),
        SizedBox(height: android ? AndroidSpacing.xs : 12),
        _buildSaved(context, imported),
        SizedBox(height: android ? AndroidSpacing.xl : 30),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '咪咕云盘',
              style: android
                  ? AndroidTextStyles.sectionTitle(context.palette.textPrimary)
                  : Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: TagPill(label: '暂未接入', color: context.palette.gold, dense: true),
            ),
          ],
        ),
        SizedBox(height: android ? AndroidSpacing.xs : 12),
        _CloudDiskCard(
          onExplain: () {
            if (android) {
              unawaited(
                showAndroidNotice(
                  context,
                  title: '为什么没有云盘内容',
                  message: AppConstants.cloudDiskNotice,
                  icon: Icons.cloud_off_rounded,
                ),
              );
              return;
            }
            unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => const _CloudDiskNoticeDialog(),
              ),
            );
          },
        ),
        // 嵌进「我的」时由页面自己的说明兜底，避免两段合规文案叠在一起。
        if (showHeader) ...[
          const SizedBox(height: 18),
          Text(
            '账号歌单只读取你登录账号的我喜欢、自建与收藏列表，不会改动账号内容；'
            '导入只读取外部歌单的公开曲目名与歌手。播放与 VIP 权限仍由咪咕官方账号校验，'
            '应用不下载音频，也不保存第三方平台的登录信息。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontSize: android ? 11.5 : 11,
              height: 1.7,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaved(BuildContext context, ImportedPlaylistProvider provider) {
    final android = isAndroidPlatform;
    if (provider.playlists.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.palette.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 22),
          border: Border.all(color: context.palette.line),
        ),
        child: const AppEmptyView(
          title: '还没有导入歌单',
          message: '点右上角“导入歌单”，粘贴网易云、QQ音乐或酷狗的歌单分享链接，\n匹配成功后就会出现在这里。',
          icon: Icons.playlist_add_rounded,
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
          for (final playlist in provider.playlists)
            _SavedPlaylistTile(
              playlist: playlist,
              onOpen: () => _openImportedPlaylist(context, playlist),
              onRemove: () => unawaited(_remove(context, playlist)),
            ),
        ],
      ),
    );
  }
}

/// 「我的导入」标题右侧的导入入口，保持 48dp 触控高度。
class _ImportTextButton extends StatelessWidget {
  const _ImportTextButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.palette.accent,
        minimumSize: const Size(AndroidSizes.touch, AndroidSizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.xs),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text('导入歌单', style: AndroidTextStyles.action(context.palette.accent)),
    );
  }
}

class _AndroidHubHeader extends StatelessWidget {
  const _AndroidHubHeader({required this.onImport});

  final VoidCallback onImport;

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
                  '歌单',
                  style: AndroidTextStyles.pageTitle(palette.textPrimary),
                ),
              ),
              const SizedBox(height: AndroidSpacing.xxs),
              Text(
                '账号歌单与外部歌单导入',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AndroidTextStyles.caption(palette.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AndroidSpacing.sm),
        FilledButton.icon(
          onPressed: onImport,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: const Icon(Icons.playlist_add_rounded, size: 20),
          label: const Text('导入歌单'),
        ),
      ],
    );
  }
}

class _CloudDiskCard extends StatelessWidget {
  const _CloudDiskCard({required this.onExplain});

  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final tint = context.palette.gold;
    final android = isAndroidPlatform;
    return Material(
      color: context.palette.surface.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: android ? onExplain : null,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            android ? 14 : 16,
            android ? 12 : 14,
            android ? 10 : 12,
            android ? 12 : 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 20),
            border: Border.all(color: context.palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: android ? 44 : 48,
                height: android ? 44 : 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(android ? 12 : 14),
                  border: Border.all(color: tint.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.cloud_outlined, size: android ? 22 : 24, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '云盘歌曲暂未接入',
                      style: android
                          ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                          : Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '云盘列表与播放地址由咪咕官方客户端私有签名下发，'
                      '本软件不模拟签名，因此不读取云盘内容。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textMuted,
                        fontSize: android ? 12 : 11.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              if (android)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.palette.textMuted,
                )
              else ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onExplain, child: const Text('了解原因')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudDiskNoticeDialog extends StatelessWidget {
  const _CloudDiskNoticeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('为什么没有云盘内容'),
      content: Text(
        AppConstants.cloudDiskNotice,
        style: const TextStyle(fontSize: 13, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _localError = '剪贴板里没有文本，请先复制歌单分享链接。');
      return;
    }
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _localError = null);
  }

  Future<void> _import(ImportedPlaylistProvider provider) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _localError = '请先粘贴歌单分享链接。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _localError = null);
    final ok = await provider.importFromLink(text);
    if (!mounted || !ok) return;
    Navigator.of(context).pop(true);
  }

  void _clearError(ImportedPlaylistProvider provider) {
    if (_localError != null) {
      setState(() => _localError = null);
    } else {
      provider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imported = context.watch<ImportedPlaylistProvider>();
    final card = _ImportCard(
      controller: _controller,
      importing: imported.importing,
      stage: imported.stage,
      progressCurrent: imported.progressCurrent,
      progressTotal: imported.progressTotal,
      progressLabel: imported.progressLabel,
      error: _localError ?? imported.error,
      onPaste: _paste,
      onImport: () => _import(imported),
      onCancel: imported.cancel,
      onClearError: () => _clearError(imported),
      onClose: () => Navigator.of(context).pop(false),
    );
    // 操作表自带标题与关闭按钮，这里只保留卡片内容。
    if (isAndroidPlatform) {
      return PopScope(canPop: !imported.importing, child: card);
    }
    return PopScope(
      canPop: !imported.importing,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(child: card),
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.controller,
    required this.importing,
    required this.stage,
    required this.progressCurrent,
    required this.progressTotal,
    required this.progressLabel,
    required this.error,
    required this.onPaste,
    required this.onImport,
    required this.onCancel,
    required this.onClearError,
    required this.onClose,
  });

  final TextEditingController controller;
  final bool importing;
  final ImportStage stage;
  final int progressCurrent;
  final int progressTotal;
  final String progressLabel;
  final String? error;
  final Future<void> Function() onPaste;
  final Future<void> Function() onImport;
  final VoidCallback onCancel;
  final VoidCallback onClearError;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(android ? 0 : 20),
      decoration: android
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.palette.line),
              color: context.palette.surfaceHigh,
              boxShadow: [
                BoxShadow(
                  color: context.palette.shadow.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (android)
            const SizedBox(height: AndroidSpacing.sm)
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.palette.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: context.palette.accent.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(
                    Icons.playlist_add_rounded,
                    size: 22,
                    color: context.palette.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导入外部歌单', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        '支持网易云、QQ音乐、酷狗的歌单分享链接',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TagPill(
                  label: '公开链接',
                  color: context.palette.mint,
                  icon: Icons.link_rounded,
                  dense: true,
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: importing ? null : onClose,
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  color: context.palette.textMuted,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          SizedBox(height: android ? AndroidSpacing.xs : 18),
          TextField(
            controller: controller,
            enabled: !importing,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => unawaited(onImport()),
            style: TextStyle(fontSize: android ? 15 : 13.5),
            decoration: InputDecoration(
              hintText: '粘贴歌单分享链接，例如 https://music.163.com/playlist?id=…',
              hintStyle: TextStyle(
                fontSize: android ? 13 : 12.5,
                color: context.palette.textSecondary,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.public_rounded,
                  color: context.palette.textSecondary,
                  size: android ? 22 : 20,
                ),
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  if (value.text.isEmpty || importing) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    onPressed: controller.clear,
                    tooltip: '清空链接',
                    visualDensity: VisualDensity.compact,
                    color: context.palette.textMuted,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagPill(label: '网易云音乐', color: context.palette.danger, dense: true),
              TagPill(label: 'QQ音乐', color: context.palette.gold, dense: true),
              TagPill(label: '酷狗音乐', color: context.palette.mint, dense: true),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final buttons = <Widget>[
                // 导入中途把「粘贴」位换成「取消」：大歌单动辄几百首，
                // 用户要能停下来，而不是等它跑完或干脆关掉整个应用。
                if (importing)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 17),
                    label: const Text('取消导入'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => unawaited(onPaste()),
                    icon: const Icon(Icons.content_paste_rounded, size: 17),
                    label: const Text('从剪贴板粘贴'),
                  ),
                FilledButton.icon(
                  onPressed: importing ? null : () => unawaited(onImport()),
                  icon: importing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 19),
                  label: Text(importing ? '正在导入…' : '开始导入'),
                ),
              ];
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buttons[1],
                    const SizedBox(height: 8),
                    buttons[0],
                    if (android) ...[
                      const SizedBox(height: AndroidSpacing.xs),
                      Text(
                        '最多匹配 ${ImportedPlaylistProvider.maxScanTracks} 首',
                        style: AndroidTextStyles.caption(context.palette.textSecondary),
                      ),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  buttons[0],
                  const SizedBox(width: 10),
                  buttons[1],
                  const Spacer(),
                  Text(
                    '最多匹配 ${ImportedPlaylistProvider.maxScanTracks} 首',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                      fontSize: android ? AndroidTypeScale.caption : 10.5,
                    ),
                  ),
                ],
              );
            },
          ),
          if (importing) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progressTotal > 0 ? progressCurrent / progressTotal : null,
                minHeight: 5,
                backgroundColor: context.palette.fillStrong,
                color: context.palette.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              stage == ImportStage.matching && progressTotal > 0
                  ? '正在逐首匹配咪咕曲库… $progressCurrent / $progressTotal'
                  : (progressLabel.isEmpty ? '正在导入…' : progressLabel),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: android ? AndroidTypeScale.body : 11.5,
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            if (android)
              AndroidInlineError(message: error!, onDismiss: onClearError)
            else
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                decoration: BoxDecoration(
                  color: context.palette.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.palette.danger.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: context.palette.danger,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.55,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClearError,
                      tooltip: '关闭提示',
                      visualDensity: VisualDensity.compact,
                      color: context.palette.textMuted,
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.shield_outlined,
                  size: android ? 16 : 13,
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  AppConstants.externalPlaylistNotice,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                    fontSize: android ? AndroidTypeScale.caption : 10.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportResultCard extends StatelessWidget {
  const _ImportResultCard({required this.playlist, required this.onOpen});

  final ImportedPlaylist playlist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tint = context.palette.mint;
    final android = isAndroidPlatform;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        android ? 14 : 16,
        android ? 12 : 14,
        android ? 8 : 12,
        android ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(android ? AndroidRadius.md : 18),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 20, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '《${playlist.name}》导入完成',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: android
                      ? AndroidTextStyles.listTitle(context.palette.textPrimary)
                      : Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '匹配 ${playlist.matchedCount} 首 · 未匹配 ${playlist.unmatchedCount} 首',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                    fontSize: android ? 12 : 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('打开歌单')),
        ],
      ),
    );
  }
}

class _SavedPlaylistTile extends StatelessWidget {
  const _SavedPlaylistTile({
    required this.playlist,
    required this.onOpen,
    required this.onRemove,
  });

  final ImportedPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final android = isAndroidPlatform;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          hoverColor: context.palette.hover,
          child: Padding(
            padding: EdgeInsets.fromLTRB(android ? 8 : 10, 9, 2, 9),
            child: Row(
              children: [
                CoverArt(
                  imageUrl: playlist.coverUrl,
                  seed: playlist.name,
                  size: android ? AndroidSizes.listCover : 52,
                  borderRadius: BorderRadius.circular(android ? 14 : 13),
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: android
                                  ? AndroidTextStyles.listTitle(
                                      context.palette.textPrimary,
                                    )
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ExternalPlatformTag(platform: playlist.platform),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '匹配 ${playlist.matchedCount} / ${playlist.scannedTracks} 首'
                        ' · ${formatDate(playlist.importedAt)} 导入',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textMuted,
                          fontSize: android ? 11.5 : 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onRemove,
                  tooltip: '移除导入结果',
                  color: context.palette.textMuted,
                  style: android
                      ? IconButton.styleFrom(
                          minimumSize: const Size(
                            AndroidSizes.touch,
                            AndroidSizes.touch,
                          ),
                          padding: EdgeInsets.zero,
                        )
                      : null,
                  icon: Icon(Icons.delete_outline_rounded, size: android ? 21 : 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
