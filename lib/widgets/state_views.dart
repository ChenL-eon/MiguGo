import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import 'android/android_icon_badge.dart';
import 'android/android_skeleton.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.message = '正在加载…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    if (isAndroidPlatform) {
      return _AndroidLoadingView(message: message);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '加载失败',
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (isAndroidPlatform) {
      return _AndroidStateView(
        icon: Icons.cloud_off_rounded,
        tone: context.palette.danger,
        title: title,
        message: message,
        action: onRetry == null ? null : _AndroidRetryButton(onPressed: onRetry!),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: context.palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.palette.line),
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  color: context.palette.textSecondary,
                  size: 25,
                ),
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textSecondary, height: 1.6),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.search_off_rounded,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    if (isAndroidPlatform) {
      return _AndroidStateView(
        icon: icon,
        tone: context.palette.accent,
        title: title,
        message: message,
        action: action,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: context.palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.palette.line),
                ),
                child: Icon(icon, color: context.palette.textSecondary, size: 25),
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textSecondary, height: 1.6),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Android 的加载态：先给骨架占住版面，再用一行说明交代在等什么。
class _AndroidLoadingView extends StatelessWidget {
  const _AndroidLoadingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AndroidSkeleton(child: _SkeletonSongRows()),
        const SizedBox(height: AndroidSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AndroidTextStyles.caption(palette.textSecondary),
        ),
      ],
    );
  }
}

class _SkeletonSongRows extends StatelessWidget {
  const _SkeletonSongRows();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 3; index++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AndroidSpacing.xs),
            child: Row(
              children: [
                SkeletonBox(width: 48, height: 48, radius: AndroidRadius.xs),
                SizedBox(width: AndroidSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(height: 13, width: 190),
                      SizedBox(height: 7),
                      SkeletonLine(height: 11, width: 112),
                    ],
                  ),
                ),
                SizedBox(width: AndroidSpacing.sm),
                SkeletonLine(height: 11, width: 34),
              ],
            ),
          ),
      ],
    );
  }
}

/// Android 的整页空态 / 错误态：图标底板 + 标题 + 说明 + 可选操作。
class _AndroidStateView extends StatelessWidget {
  const _AndroidStateView({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AndroidSpacing.md,
          vertical: AndroidSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AndroidIconBadge(
                icon: icon,
                color: tone,
                size: 52,
                iconSize: AndroidSizes.largeIcon,
                radius: AndroidRadius.md,
              ),
              const SizedBox(height: AndroidSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AndroidTextStyles.sectionTitle(palette.textPrimary),
              ),
              const SizedBox(height: AndroidSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AndroidTextStyles.body(palette.textSecondary)
                    .copyWith(height: 1.65),
              ),
              if (action != null) ...[
                const SizedBox(height: AndroidSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidRetryButton extends StatelessWidget {
  const _AndroidRetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OutlinedButton.icon(
      onPressed: () {
        unawaited(HapticFeedback.selectionClick());
        onPressed();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accent,
        backgroundColor: palette.surfaceHigh,
        side: BorderSide(color: palette.lineStrong),
        minimumSize: const Size(124, AndroidSizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AndroidRadius.pillAll),
        textStyle: AndroidTextStyles.action(palette.accent),
      ),
      icon: const Icon(Icons.refresh_rounded, size: AndroidSizes.smallIcon),
      label: const Text('重试'),
    );
  }
}
