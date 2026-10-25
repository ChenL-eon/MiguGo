import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/platform_kind.dart';
import '../models/auth_session.dart';
import '../providers/account_provider.dart';
import '../providers/player_provider.dart';
import 'android/android_feedback.dart';
import 'android/android_sheet.dart';
import 'cover_art.dart';
import 'login_feedback.dart';
import 'native_login_panel.dart';
import 'privacy_policy.dart';
import 'tag_pill.dart';

/// 左下角账号卡片：点开就是原生登录弹窗，登录状态与权限说明同在一处。
class AccountSummaryCard extends StatelessWidget {
  const AccountSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final palette = context.palette;
    final loggedIn = account.hasLogin;
    final statusColor = switch (account.status) {
      AuthStatus.none =>
        account.autoSignOutNotice == null ? palette.textMuted : palette.danger,
      AuthStatus.unverified => account.hasIncompleteLogin ? palette.gold : palette.mint,
      AuthStatus.verified => palette.mint,
      AuthStatus.rejected => palette.danger,
    };
    final statusIcon = switch (account.status) {
      AuthStatus.none =>
        account.autoSignOutNotice == null
            ? Icons.person_outline_rounded
            : Icons.gpp_maybe_outlined,
      AuthStatus.unverified => Icons.shield_outlined,
      AuthStatus.verified => Icons.verified_user_outlined,
      AuthStatus.rejected => Icons.gpp_maybe_outlined,
    };
    final avatarUrl = account.avatarUrl;
    final android = isAndroidPlatform;
    final radius = BorderRadius.circular(android ? 18 : 16);
    final avatarSize = android ? 44.0 : 38.0;

    return Material(
      color: palette.surface.withValues(alpha: 0.66),
      borderRadius: radius,
      child: InkWell(
        onTap: () => openAccountCenter(context),
        borderRadius: radius,
        hoverColor: palette.hover,
        child: Container(
          padding: EdgeInsets.all(android ? AndroidSpacing.sm : 13),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (loggedIn && avatarUrl.isNotEmpty)
                      ClipOval(
                        child: CoverArt(
                          imageUrl: avatarUrl,
                          seed: account.displayName,
                          size: avatarSize,
                          borderRadius: BorderRadius.zero,
                          iconSize: 18,
                        ),
                      )
                    else
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          statusIcon,
                          size: android ? 22 : 19,
                          color: statusColor,
                        ),
                      ),
                    if (account.profileLoading)
                      Positioned.fill(
                        child: ClipOval(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.24),
                            child: const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: android ? 14.5 : 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (loggedIn && account.isVip) ...[
                          const SizedBox(width: 6),
                          TagPill(
                            label: 'VIP',
                            color: palette.gold,
                            icon: Icons.workspace_premium_rounded,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loggedIn
                          ? account.statusLabel
                          : account.autoSignOutNotice == null
                          ? '点击登录，使用自己的账号权益'
                          : account.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: android ? 12 : 10.5,
                        color: !loggedIn && account.autoSignOutNotice == null
                            ? palette.textMuted
                            : statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: android ? 20 : 18,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左下角账号卡片与「我的」页都走这里：弹窗本身就是原生登录页。
Future<void> openAccountCenter(BuildContext context) async {
  await showAccountCenterDialog(context);
}

/// 账号与原生登录弹窗。返回是否刚完成一次原生登录。
///
/// Android 走底部操作表，桌面保持原有居中对话框；两种容器都渲染同一个
/// [_AccountCenterBody]，登录成功时由 body 关闭所在路由。
Future<bool> showAccountCenterDialog(BuildContext context) async {
  String? maskedPhone;
  bool? signedIn;
  if (isAndroidPlatform) {
    signedIn = await showAndroidSheet<bool>(
      context: context,
      title: '账号与登录',
      builder: (sheetContext) => _AccountCenterBody(
        onSignedIn: (phone) {
          maskedPhone = phone;
          Navigator.of(sheetContext).pop(true);
        },
      ),
    );
  } else {
    signedIn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AccountCenterDialog(
        onSignedIn: (phone) {
          maskedPhone = phone;
          Navigator.of(dialogContext).pop(true);
        },
      ),
    );
  }
  if (signedIn != true || !context.mounted) return false;

  final warning = context.read<AccountProvider>().storageWarning;
  if (warning != null) {
    await showLoginStorageWarning(context, warning);
    return true;
  }
  showLoginSnack(context, maskedPhone == null ? '登录成功。' : '登录成功：$maskedPhone');
  return true;
}

/// 桌面弹窗外壳：只负责对话框与滚动容器，内容与 Android 共用。
class _AccountCenterDialog extends StatelessWidget {
  const _AccountCenterDialog({required this.onSignedIn});

  final void Function(String? maskedPhone) onSignedIn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: _AccountCenterBody(onSignedIn: onSignedIn),
        ),
      ),
    );
  }
}

class _AccountCenterBody extends StatefulWidget {
  const _AccountCenterBody({required this.onSignedIn});

  final void Function(String? maskedPhone) onSignedIn;

  @override
  State<_AccountCenterBody> createState() => _AccountCenterBodyState();
}

class _AccountCenterBodyState extends State<_AccountCenterBody> {
  bool _busy = false;

  /// 退出登录：清本机凭据 + 停播放清队列。[closeDialog] 为 false 时留在弹窗里，
  /// 登录表单会因为没有凭据自动出现，这就是「切换账号」。
  Future<void> _signOut({required bool closeDialog}) async {
    const signOutHint =
        '将清除本机保存的登录凭据与账号快照，正在播放的曲目会停止并清空播放列表。'
        '设置、搜索历史与导入的歌单不受影响。\n\n'
        '咪咕没有登出接口，这一步只发生在你这台设备上；'
        '之后播放 VIP 曲目需要重新登录。';
    final confirmed = isAndroidPlatform
        ? await showAndroidConfirm(
            context,
            title: '退出登录',
            message: signOutHint,
            confirmLabel: '确认退出',
            destructive: true,
            icon: Icons.logout_rounded,
          )
        : await showDialog<bool>(
            context: context,
            builder: (confirmContext) => AlertDialog(
              backgroundColor: context.palette.surfaceHigh,
              surfaceTintColor: Colors.transparent,
              title: const Text('退出登录'),
              content: Text(
                signOutHint,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.75,
                  color: context.palette.textSecondary,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(confirmContext).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(confirmContext).pop(true),
                  child: const Text('确认退出'),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;

    final account = context.read<AccountProvider>();
    final player = context.read<PlayerProvider>();
    setState(() => _busy = true);
    await account.signOut();
    await player.clearQueue();
    if (!mounted) return;
    setState(() => _busy = false);

    if (closeDialog) {
      showLoginSnack(context, '已退出登录，本机保存的凭据已清除。');
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final palette = context.palette;
    final statusColor = switch (account.status) {
      AuthStatus.none =>
        account.autoSignOutNotice == null ? palette.textMuted : palette.danger,
      AuthStatus.unverified => account.hasIncompleteLogin ? palette.gold : palette.mint,
      AuthStatus.verified => palette.mint,
      AuthStatus.rejected => palette.danger,
    };
    final statusIcon = switch (account.status) {
      AuthStatus.none =>
        account.autoSignOutNotice == null
            ? Icons.person_outline_rounded
            : Icons.gpp_maybe_outlined,
      AuthStatus.unverified => Icons.shield_outlined,
      AuthStatus.verified => Icons.verified_user_outlined,
      AuthStatus.rejected => Icons.gpp_maybe_outlined,
    };

    final android = isAndroidPlatform;
    final title = account.hasLogin ? '个人中心' : '登录咪咕账号';
    final headerHint = account.hasLogin
        ? '这里只有你自己账号的凭据与状态，退出与换账号都在这一屏。'
        : '请求权限跟随咪咕官方，应用不提供任何提权手段。';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (android) ...[
          Text(title, style: AndroidTextStyles.sectionTitle(palette.textPrimary)),
          const SizedBox(height: AndroidSpacing.xxs),
          Text(headerHint, style: AndroidTextStyles.caption(palette.textMuted)),
          const SizedBox(height: AndroidSpacing.md),
        ] else ...[
          Row(
            children: [
              Icon(Icons.account_circle_outlined, size: 20, color: palette.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                color: palette.textMuted,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            headerHint,
            style: TextStyle(fontSize: 10.5, height: 1.6, color: palette.textMuted),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: android ? AndroidSpacing.md : 14,
            vertical: android ? AndroidSpacing.sm : 12,
          ),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: android ? 0.08 : 0.06),
            borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 12),
            border: Border.all(color: statusColor.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, size: android ? 20 : 18, color: statusColor),
                  SizedBox(width: android ? AndroidSpacing.sm : 9),
                  Expanded(
                    child: Text(
                      account.hasLogin
                          ? '${account.displayName} · ${account.statusLabel}'
                          : account.statusLabel,
                      style: TextStyle(
                        fontSize: android ? 13.5 : 12.5,
                        height: android ? 1.4 : null,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (account.hasLogin)
                    Text(
                      '${account.cookieCount} 项',
                      style: TextStyle(
                        fontSize: android ? AndroidTypeScale.caption : 10.5,
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
              SizedBox(height: android ? AndroidSpacing.xs : 6),
              Text(
                account.statusHint,
                style: TextStyle(
                  fontSize: android ? AndroidTypeScale.caption : 10.5,
                  height: 1.6,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (account.storageWarning != null) ...[
          const SizedBox(height: 10),
          if (android)
            AndroidInlineError(title: '凭据未能写入安全存储', message: account.storageWarning!)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.danger.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.phonelink_lock_outlined, size: 15, color: palette.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      account.storageWarning!,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.6,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        SizedBox(height: android ? AndroidSpacing.lg : 16),
        if (account.hasLogin)
          _PersonalCenterPanel(
            account: account,
            busy: _busy,
            onSwitchAccount: () => unawaited(_signOut(closeDialog: false)),
            onSignOut: () => unawaited(_signOut(closeDialog: true)),
          )
        else
          NativeLoginPanel(onSignedIn: widget.onSignedIn),
        SizedBox(height: android ? AndroidSpacing.lg : 16),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(android ? AndroidSpacing.md : 13),
          decoration: BoxDecoration(
            color: palette.fillSubtle,
            borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 13),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: android ? AndroidSizes.smallIcon : 15,
                color: palette.textMuted,
              ),
              SizedBox(width: android ? AndroidSpacing.sm : 9),
              Expanded(
                child: Text(
                  AppConstants.loginPrivacyHint,
                  style: TextStyle(
                    fontSize: android ? AndroidTypeScale.caption : 10.5,
                    height: 1.7,
                    color: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => showPrivacyPolicyDialog(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: android ? AndroidSpacing.xs : 8,
                    vertical: android ? AndroidSpacing.xxs : 2,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '隐私政策',
                  style: TextStyle(fontSize: android ? AndroidTypeScale.caption : 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (android) return content;

    return Dialog(
      backgroundColor: palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: content,
        ),
      ),
    );
  }
}

/// 已登录时的个人中心：账号资料、凭据状态，以及退出登录与切换账号。
class _PersonalCenterPanel extends StatelessWidget {
  const _PersonalCenterPanel({
    required this.account,
    required this.busy,
    required this.onSwitchAccount,
    required this.onSignOut,
  });

  final AccountProvider account;
  final bool busy;
  final VoidCallback onSwitchAccount;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    final phone = account.profile?.maskedPhone ?? '';
    final checkedAt = account.lastCheckedAt;
    final avatarSize = android ? 48.0 : 44.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(android ? AndroidSpacing.md : 14),
          decoration: BoxDecoration(
            color: palette.fillSubtle,
            borderRadius: BorderRadius.circular(android ? AndroidRadius.sm : 13),
            border: Border.all(color: palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: avatarSize,
                    height: avatarSize,
                    child: ClipOval(
                      child: CoverArt(
                        imageUrl: account.avatarUrl,
                        seed: account.displayName,
                        size: avatarSize,
                        borderRadius: BorderRadius.zero,
                        iconSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: android ? 14.5 : 13.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          phone.isEmpty ? '咪咕未返回手机号' : phone,
                          style: TextStyle(
                            fontSize: android ? AndroidTypeScale.caption : 10.5,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (account.isVip)
                    TagPill(
                      label: 'VIP',
                      color: palette.gold,
                      icon: Icons.workspace_premium_rounded,
                      dense: true,
                    ),
                ],
              ),
              const SizedBox(height: 13),
              _InfoRow(label: '登录凭据', value: '${account.cookieCount} 项，只存在系统安全存储里'),
              _InfoRow(
                label: '登录时间',
                value: account.importedAt == null
                    ? '本次运行内登录'
                    : formatDate(account.importedAt),
              ),
              _InfoRow(
                label: '最近校验',
                value: checkedAt == null ? '尚未校验' : formatDate(checkedAt),
              ),
              _InfoRow(
                label: '播放权益',
                value: account.isVip ? '咪咕按账号权益判定为会员' : '能否播放 VIP 曲目由咪咕按账号权益判定',
              ),
              if (account.profileError != null)
                _InfoRow(
                  label: '账号资料',
                  value: account.profileError!,
                  valueColor: palette.danger,
                ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSwitchAccount,
                style: android ? _panelButtonStyle(palette) : null,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('切换账号'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSignOut,
                style: (android ? _panelButtonStyle(palette) : ButtonStyle()).copyWith(
                  foregroundColor: WidgetStatePropertyAll(palette.danger),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: palette.danger.withValues(alpha: .45)),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('退出登录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '退出只清除本机保存的登录凭据与账号快照，设置、搜索历史与导入的歌单都不动；'
          '咪咕没有登出接口，这一步不会通知服务端。',
          style: TextStyle(
            fontSize: android ? AndroidTypeScale.caption : 10,
            height: 1.7,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

/// 手机弹窗里的次级主操作：48dp 触控高度与胶囊描边。
ButtonStyle _panelButtonStyle(AppPalette palette) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, AndroidSizes.touch),
    padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.md),
    shape: const RoundedRectangleBorder(borderRadius: AndroidRadius.pillAll),
    side: BorderSide(color: palette.lineStrong),
    textStyle: AndroidTextStyles.action(palette.textPrimary),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final android = isAndroidPlatform;
    return Padding(
      padding: EdgeInsets.only(bottom: android ? AndroidSpacing.xs : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: android ? 76 : 62,
            child: Text(
              label,
              style: TextStyle(
                fontSize: android ? AndroidTypeScale.caption : 10.5,
                color: palette.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: android ? AndroidTypeScale.caption : 10.5,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: valueColor ?? palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
