import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../providers/update_provider.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/brand_badge.dart';
import '../widgets/tag_pill.dart';

/// 关于页：用途声明、账号权限边界与实现说明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _showHint(context, '链接暂未配置');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showHint(context, '无法打开链接');
    }
  }

  void _showHint(BuildContext context, String message) {
    if (isAndroidPlatform) {
      showAndroidSnack(context, message, isError: true);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final padding = android
            ? AndroidSpacing.md
            : (constraints.maxWidth >= 700 ? 40.0 : 20.0);
        return Scrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              android ? AndroidSpacing.xs : 26,
              padding,
              android ? AndroidSpacing.xl : 36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 手机端的标题与副标题已经在二级页顶栏里，不再重复一遍。
                    if (!android) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '关于',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '用途、权限边界与实现说明',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    _AboutHero(
                      onOpenRepository: () =>
                          _openLink(context, AppConstants.githubRepoUrl),
                    ),
                    const SizedBox(height: 14),
                    const _NoticeCard(),
                    const SizedBox(height: 14),
                    _UpdateSection(
                      onOpenRelease: () =>
                          _openLink(context, AppConstants.updatePageUrl),
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      icon: Icons.shield_outlined,
                      title: '合规边界',
                      subtitle: '以下为项目的固定实现边界，不随账号状态改变。',
                      child: Column(
                        children: [
                          const _PolicyItem(
                            icon: Icons.lock_person_outlined,
                            text: AppConstants.accountPolicy,
                          ),
                          const _PolicyDivider(),
                          const _PolicyItem(
                            icon: Icons.open_in_browser_rounded,
                            text: AppConstants.webViewPolicy,
                          ),
                          const _PolicyDivider(),
                          const _PolicyItem(
                            icon: Icons.hub_outlined,
                            text: AppConstants.networkPolicy,
                          ),
                          const _PolicyDivider(),
                          const _PolicyItem(
                            icon: Icons.playlist_add_rounded,
                            text: AppConstants.externalPlaylistNotice,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              TagPill(
                                label: '仅在线流式播放',
                                color: context.palette.mint,
                                dense: true,
                              ),
                              TagPill(
                                label: '不下载音频',
                                color: context.palette.mint,
                                dense: true,
                              ),
                              TagPill(
                                label: '不缓存音频文件',
                                color: context.palette.mint,
                                dense: true,
                              ),
                              TagPill(
                                label: '不逆向签名',
                                color: context.palette.mint,
                                dense: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      icon: Icons.tune_rounded,
                      title: '实现说明',
                      subtitle:
                          '界面与登录表单全部原生自绘；只有选择官方页面登录、'
                          '或 VIP 曲目内嵌官方播放器时才临时使用 WebView，'
                          'VIP 曲目由原生播放器按账号权益取链，'
                          '必要时可切到咪咕官方网页播放器；'
                          '首页推送与外部歌单导入均为原生解析，不加载第三方网页。',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: const [
                              _TechChip(label: 'Flutter'),
                              _TechChip(label: 'Dart'),
                              _TechChip(label: 'Provider'),
                              _TechChip(label: 'dio'),
                              _TechChip(label: 'just_audio'),
                              _TechChip(label: 'WebView（官方页与播放器）'),
                              _TechChip(label: 'Material 3'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const _InfoRow(label: '接口来源', value: '咪咕音乐网页公开接口与官方通行证登录接口'),
                          const SizedBox(height: 8),
                          const _InfoRow(label: '首页推送', value: '咪咕每日推荐模板与首页栏目配置'),
                          const SizedBox(height: 8),
                          const _InfoRow(
                            label: '外部歌单',
                            value: '仅读取公开链接中的曲目名与歌手，再匹配咪咕曲库',
                          ),
                          const SizedBox(height: 8),
                          const _InfoRow(
                            label: '版本检查',
                            value: '匿名读取 GitHub 的公开发布列表比对版本号，不携带账号信息，可关闭',
                          ),
                          const SizedBox(height: 8),
                          const _InfoRow(
                            label: '请求来源头',
                            value: AppConstants.miguReferer,
                            mono: true,
                          ),
                          const SizedBox(height: 8),
                          const _InfoRow(
                            label: '应用版本',
                            value: 'v${AppConstants.appVersion}',
                          ),
                          const SizedBox(height: 8),
                          const _InfoRow(label: '默认主题', value: '跟随系统（可在设置中切换）'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '${AppConstants.appName} · v${AppConstants.appVersion}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '音乐版权归属咪咕及对应版权方 · 仅供本人自用',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.palette.textMuted.withValues(alpha: 0.72),
                              fontSize: 10,
                            ),
                          ),
                        ],
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

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.onOpenRepository});

  final VoidCallback onOpenRepository;

  @override
  Widget build(BuildContext context) {
    final badge = BrandBadge(
      size: 68,
      radius: 21,
      shadow: [
        BoxShadow(
          color: context.palette.accent.withValues(alpha: 0.28),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 25),
            ),
            TagPill(label: '非官方', color: context.palette.gold, dense: true),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '一款开源的第三方咪咕音乐播放器',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.palette.textSecondary,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'MIGUGO · v${AppConstants.appVersion}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.palette.textMuted,
            fontSize: 9,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.palette.line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.palette.accent.withValues(alpha: isDark ? 0.2 : 0.14),
                context.palette.accent.withValues(alpha: isDark ? 0.07 : 0.04),
                context.palette.surfaceHigh.withValues(alpha: isDark ? 0.8 : 0.96),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        badge,
                        const SizedBox(width: 18),
                        Expanded(child: details),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _GitHubButton(onTap: onOpenRepository),
                    ),
                  ],
                )
              : Row(
                  children: [
                    badge,
                    const SizedBox(width: 18),
                    Expanded(child: details),
                    const SizedBox(width: 16),
                    _GitHubButton(onTap: onOpenRepository),
                  ],
                ),
        );
      },
    );
  }
}

class _GitHubButton extends StatelessWidget {
  const _GitHubButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Material(
      color: Colors.white,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 6, 13, 6),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/github_mark.png',
                  width: 20,
                  height: 20,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'GitHub',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.palette.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateSection extends StatelessWidget {
  const _UpdateSection({required this.onOpenRelease});

  /// 检查本身留在应用里；只有查到新版本才给一个打开发布页的入口。
  final VoidCallback onOpenRelease;

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateProvider>();
    final latest = update.last;
    return _SectionCard(
      icon: Icons.system_update_alt_rounded,
      title: '更新',
      subtitle: '检查新版本，也可以让应用在启动时自动检查。',
      child: Column(
        children: [
          _UpdateRow(
            icon: Icons.refresh_rounded,
            title: '检查更新',
            description: _describeCheck(update),
            trailing: _InlineActionButton(
              icon: Icons.refresh_rounded,
              label: '立即检查',
              busy: update.checking,
              onTap: () => unawaited(update.check()),
            ),
          ),
          if (latest?.hasUpdate ?? false) ...[
            const _PolicyDivider(),
            _UpdateRow(
              icon: Icons.download_outlined,
              title: '新版本 v${latest!.latestVersion}',
              description: '本机 v${AppConstants.appVersion} 不是最新，打开发布页取安装包。',
              trailing: _InlineActionButton(
                icon: Icons.open_in_new_rounded,
                label: '打开发布页',
                onTap: onOpenRelease,
              ),
            ),
          ],
          const _PolicyDivider(),
          _UpdateRow(
            icon: Icons.rocket_launch_outlined,
            title: '启动时自动检查',
            description: '启动时自动检查一次是否有新版本。',
            trailing: Switch.adaptive(
              value: update.autoCheck,
              onChanged: (value) => unawaited(update.setAutoCheck(value)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

String _describeCheck(UpdateProvider update) {
  if (update.checking) return '正在检查…';
  final failure = update.failure;
  if (failure != null) return failure;
  final last = update.last;
  if (last == null) return '尚未检查更新';
  final at = update.checkedAt;
  final suffix = at == null ? '' : '（${_checkedAtLabel(at)}检查）';
  if (last.hasUpdate) return '发现新版本 v${last.latestVersion}$suffix';
  return '已是最新版本 v${AppConstants.appVersion}$suffix';
}

String _checkedAtLabel(DateTime at) {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay
      ? '${two(at.hour)}:${two(at.minute)} '
      : '${at.year}-${two(at.month)}-${two(at.day)} ';
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: context.palette.fillSubtle,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: context.palette.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.accent;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 17,
              height: 17,
              child: busy
                  ? CircularProgressIndicator(strokeWidth: 2, color: accent)
                  : Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.gold.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.gold.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 18, color: context.palette.gold),
              const SizedBox(width: 8),
              Text(
                '用途与版权声明',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 11),
          SelectableText(
            AppConstants.aboutNotice,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textPrimary,
              fontSize: 13,
              height: 1.85,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.palette.accent),
              const SizedBox(width: 9),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PolicyItem extends StatelessWidget {
  const _PolicyItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: context.palette.fillSubtle,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: context.palette.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              fontSize: 12.5,
              height: 1.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _PolicyDivider extends StatelessWidget {
  const _PolicyDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 13),
      child: Divider(height: 1),
    );
  }
}

class _TechChip extends StatelessWidget {
  const _TechChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.palette.fillSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: context.palette.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: context.palette.textMuted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 11.5,
              color: context.palette.textSecondary,
              fontFamily: mono ? 'Consolas' : null,
            ),
          ),
        ),
      ],
    );
  }
}
