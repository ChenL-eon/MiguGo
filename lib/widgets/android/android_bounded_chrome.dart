import 'package:flutter/material.dart';

import '../../core/theme/android_tokens.dart';

/// 定高壳层（迷你播放条、底部导航）的字号封顶容器。
///
/// 这两层的高度由 [AndroidSizes] 写死，且主框架用它推算列表底部留白，
/// 所以内部文字只跟随到 [AndroidSizes.chromeMaxTextScale]；页面正文不受影响。
class AndroidBoundedChrome extends StatelessWidget {
  const AndroidBoundedChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final capped = MediaQuery.textScalerOf(context)
        .scale(1.0)
        .clamp(1.0, AndroidSizes.chromeMaxTextScale)
        .toDouble();
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(capped)),
      child: child,
    );
  }
}
