import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/external_playlist_urls.dart';
import 'tag_pill.dart';

/// 外部平台统一标识，颜色与平台主色保持一致。
class ExternalPlatformTag extends StatelessWidget {
  const ExternalPlatformTag({super.key, required this.platform, this.dense = true});

  final ExternalPlatform platform;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = switch (platform) {
      ExternalPlatform.netease => context.palette.danger,
      ExternalPlatform.qqMusic => context.palette.gold,
      ExternalPlatform.kugou => context.palette.mint,
    };
    return TagPill(label: platform.label, color: color, dense: dense);
  }
}
