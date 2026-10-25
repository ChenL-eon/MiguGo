import 'package:flutter/material.dart';

import '../../models/theme_accent.dart';
import 'app_colors.dart';

/// 全局 Material 3 主题，浅色与深色共用同一套排版和组件规范。
class AppTheme {
  const AppTheme._();

  static ThemeData light(ThemeAccent accent) =>
      _build(AppPalette.lightFor(accent), Brightness.light);

  static ThemeData dark(ThemeAccent accent) =>
      _build(AppPalette.darkFor(accent), Brightness.dark);

  /// 播放页专用：整屏模糊背景上需要固定的白阶排版，不跟随应用明暗。
  static ThemeData get immersive => _build(AppPalette.immersive, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
    );

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: isDark ? palette.accent : palette.accentDeep,
      secondary: palette.mint,
      onSecondary: isDark ? const Color(0xFF062320) : Colors.white,
      secondaryContainer: palette.mint.withValues(alpha: isDark ? 0.16 : 0.12),
      onSecondaryContainer: palette.mint,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.surfaceHigh,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.lineStrong,
      outlineVariant: palette.line,
      error: palette.danger,
      onError: Colors.white,
      shadow: palette.shadow,
      scrim: Colors.black54,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: palette.textPrimary, displayColor: palette.textPrimary)
        .copyWith(
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontSize: 36,
            height: 1.16,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 27,
            height: 1.24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13.5, height: 1.55),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      textTheme: textTheme,
      extensions: [palette],
      dividerTheme: DividerThemeData(color: palette.line, thickness: 1, space: 1),
      dividerColor: palette.line,
      iconTheme: IconThemeData(color: palette.textSecondary, size: 21),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.danger),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.lineStrong,
        thumbColor: palette.textPrimary,
        overlayColor: palette.accentSoft,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
        padding: EdgeInsets.zero,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : palette.surfaceSoft;
        }),
        trackOutlineColor: WidgetStateProperty.all(palette.lineStrong),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.textSecondary,
          selectedBackgroundColor: palette.accentSoft,
          selectedForegroundColor: palette.accent,
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.accentSoft,
        disabledColor: palette.surfaceSoft,
        labelStyle: TextStyle(color: palette.textSecondary, fontSize: 12),
        secondaryLabelStyle: TextStyle(
          color: palette.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        checkmarkColor: palette.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: TextStyle(color: palette.textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.line),
        ),
        textStyle: TextStyle(color: palette.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          height: 1.7,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: palette.lineStrong,
          disabledForegroundColor: palette.textMuted,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.lineStrong),
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(palette.lineStrong),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
        interactive: true,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.line,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
