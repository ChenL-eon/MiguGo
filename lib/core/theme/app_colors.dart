import 'package:flutter/material.dart';

import '../../models/theme_accent.dart';

/// 语义色板：同一套字段分别提供浅色与深色取值。
///
/// 界面组件统一通过 `context.palette` 读取，而不是写死某一种主题的颜色。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceSoft,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
    required this.mint,
    required this.gold,
    required this.danger,
    required this.onAccent,
    required this.hover,
    required this.fill,
    required this.fillStrong,
    required this.fillSubtle,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceSoft;
  final Color line;
  final Color lineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color accent;
  final Color accentDeep;
  final Color accentSoft;
  final Color mint;
  final Color gold;
  final Color danger;
  final Color onAccent;

  /// 鼠标悬停、轻微填充与阴影，按主题分别使用白或黑叠加。
  final Color hover;
  final Color fill;
  final Color fillStrong;
  final Color fillSubtle;
  final Color shadow;

  static const dark = AppPalette(
    background: Color(0xFF080C14),
    surface: Color(0xFF111827),
    surfaceHigh: Color(0xFF182133),
    surfaceSoft: Color(0xFF0C1220),
    line: Color(0x1AFFFFFF),
    lineStrong: Color(0x2EFFFFFF),
    textPrimary: Color(0xFFF2F5FA),
    textSecondary: Color(0xFF99A6B9),
    textMuted: Color(0xFF647186),
    accent: Color(0xFFFF6BA5),
    accentDeep: Color(0xFFE84C8D),
    accentSoft: Color(0x26FF6BA5),
    mint: Color(0xFF70D6C0),
    gold: Color(0xFFF4BE72),
    danger: Color(0xFFFF6E7A),
    onAccent: Color(0xFF2A0614),
    hover: Color(0x09FFFFFF),
    fill: Color(0x0BFFFFFF),
    fillStrong: Color(0x0FFFFFFF),
    fillSubtle: Color(0x06FFFFFF),
    shadow: Color(0x6B000000),
  );

  /// 播放页沉浸配色：整屏模糊封面上只用白阶，避免和任意封面颜色打架。
  static const immersive = AppPalette(
    background: Color(0xFF101319),
    surface: Color(0x14FFFFFF),
    surfaceHigh: Color(0xF01A1E26),
    surfaceSoft: Color(0x0DFFFFFF),
    line: Color(0x2EFFFFFF),
    lineStrong: Color(0x4DFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xD8FFFFFF),
    textMuted: Color(0x9AFFFFFF),
    accent: Color(0xFFFFFFFF),
    accentDeep: Color(0xFFF0F2F5),
    accentSoft: Color(0x29FFFFFF),
    mint: Color(0xFF8FE3C9),
    gold: Color(0xFFFFD9A0),
    danger: Color(0xFFFFB0B8),
    onAccent: Color(0xFF14171D),
    hover: Color(0x14FFFFFF),
    fill: Color(0x1FFFFFFF),
    fillStrong: Color(0x30FFFFFF),
    fillSubtle: Color(0x12FFFFFF),
    shadow: Color(0x90000000),
  );

  static const light = AppPalette(
    background: Color(0xFFF4F7FC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFEAF0F9),
    line: Color(0x14122844),
    lineStrong: Color(0x26122844),
    textPrimary: Color(0xFF17233B),
    textSecondary: Color(0xFF566378),
    textMuted: Color(0xFF8A95A8),
    accent: Color(0xFFD81B60),
    accentDeep: Color(0xFFAD1457),
    accentSoft: Color(0xFFFCE4EC),
    mint: Color(0xFF0E7C6B),
    gold: Color(0xFF96630F),
    danger: Color(0xFFBE3540),
    onAccent: Color(0xFFFFFFFF),
    hover: Color(0x0A122844),
    fill: Color(0x08122844),
    fillStrong: Color(0x0F122844),
    fillSubtle: Color(0x05122844),
    shadow: Color(0x1F000000),
  );

  static AppPalette lightFor(ThemeAccent accent) => light.copyWith(
    accent: accent.lightAccent,
    accentDeep: accent.lightDeep,
    accentSoft: accent.lightSoft,
    onAccent: const Color(0xFFFFFFFF),
  );

  static AppPalette darkFor(ThemeAccent accent) => dark.copyWith(
    accent: accent.darkAccent,
    accentDeep: accent.darkDeep,
    accentSoft: accent.darkSoft,
    onAccent: accent.darkOnAccent,
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceSoft,
    Color? line,
    Color? lineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentDeep,
    Color? accentSoft,
    Color? mint,
    Color? gold,
    Color? danger,
    Color? onAccent,
    Color? hover,
    Color? fill,
    Color? fillStrong,
    Color? fillSubtle,
    Color? shadow,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentSoft: accentSoft ?? this.accentSoft,
      mint: mint ?? this.mint,
      gold: gold ?? this.gold,
      danger: danger ?? this.danger,
      onAccent: onAccent ?? this.onAccent,
      hover: hover ?? this.hover,
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      fillSubtle: fillSubtle ?? this.fillSubtle,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      surfaceSoft: mix(surfaceSoft, other.surfaceSoft),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      accentDeep: mix(accentDeep, other.accentDeep),
      accentSoft: mix(accentSoft, other.accentSoft),
      mint: mix(mint, other.mint),
      gold: mix(gold, other.gold),
      danger: mix(danger, other.danger),
      onAccent: mix(onAccent, other.onAccent),
      hover: mix(hover, other.hover),
      fill: mix(fill, other.fill),
      fillStrong: mix(fillStrong, other.fillStrong),
      fillSubtle: mix(fillSubtle, other.fillSubtle),
      shadow: mix(shadow, other.shadow),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// 当前主题的语义色板；未注册扩展时按明暗给出安全兜底。
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
  }
}

/// 与主题无关的品牌渐变与占位封面。
class AppColors {
  const AppColors._();

  static const Color lightBackground = Color(0xFFF4F7FC);
  static const Color darkBackground = Color(0xFF080C14);
  static const Color onBrand = Color(0xFFFFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6AA8FF), Color(0xFF2F6BFF)],
  );

  /// 根据文本生成稳定的封面占位渐变，避免网络封面缺失时界面突兀。
  static LinearGradient coverGradient(String seed) {
    const palettes = <List<Color>>[
      [Color(0xFF2D3A55), Color(0xFF6D5B8E)],
      [Color(0xFF3B302E), Color(0xFF8A5A4B)],
      [Color(0xFF213B3A), Color(0xFF4E7D74)],
      [Color(0xFF3B2C3D), Color(0xFF8A526A)],
      [Color(0xFF2B3220), Color(0xFF6E7747)],
      [Color(0xFF262C45), Color(0xFF4B668E)],
    ];
    final palette = palettes[seed.hashCode.abs() % palettes.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: palette,
    );
  }
}
