import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/player_background.dart';
import '../models/song.dart';
import '../providers/settings_provider.dart';
import 'cover_art.dart';

/// 播放页整屏背景：按设置渲染模糊封面或自定义图片，再压一层暗色遮罩保证白字可读。
class PlayerBackgroundLayer extends StatelessWidget {
  const PlayerBackgroundLayer({super.key, required this.settings, required this.song});

  static const Color baseColor = Color(0xFF101319);

  /// 顶部遮罩接近不透明，原生标题栏取同一颜色即可无缝接上。
  static const Color captionColor = Color(0xFF0A0C10);

  final SettingsProvider settings;
  final Song? song;

  @override
  Widget build(BuildContext context) {
    final sigma = settings.playerBackgroundBlur.toDouble();
    final source = _source();
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: baseColor),
            // 模糊会从画布外取样，四周发虚；放大一点把虚边推出可视区。
            if (sigma > 0)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Transform.scale(scale: 1.18, child: source),
              )
            else
              source,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.12, 0.5, 1],
                  colors: [
                    Color(0xE60A0C10),
                    Color(0xB30A0C10),
                    Color(0x80000000),
                    Color(0xC0000000),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _source() {
    final path = settings.playerBackgroundImage;
    final useCustom =
        settings.playerBackground == PlayerBackground.custom &&
        path != null &&
        path.isNotEmpty;
    if (useCustom) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _coverSource(),
      );
    }
    return _coverSource();
  }

  Widget _coverSource() {
    return CoverArt(
      imageUrl: song?.coverUrlLarge ?? song?.coverUrl,
      seed: song?.name ?? 'MiguGo',
      borderRadius: BorderRadius.zero,
    );
  }
}
