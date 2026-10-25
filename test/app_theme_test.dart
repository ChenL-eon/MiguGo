import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/theme/app_colors.dart';
import 'package:migu_lele/core/theme/app_theme.dart';
import 'package:migu_lele/models/theme_accent.dart';
import 'package:migu_lele/providers/settings_provider.dart';

void main() {
  test('每个主题色都会映射到浅色色板与 ColorScheme', () {
    for (final accent in ThemeAccent.values) {
      final theme = AppTheme.light(accent);
      final palette = theme.extension<AppPalette>();

      expect(palette, isNotNull);
      expect(theme.brightness, Brightness.light);
      expect(palette!.accent, accent.lightAccent);
      expect(palette.accentDeep, accent.lightDeep);
      expect(palette.accentSoft, accent.lightSoft);
      expect(palette.onAccent, const Color(0xFFFFFFFF));
      expect(palette.background, AppPalette.light.background);
      expect(theme.colorScheme.primary, accent.lightAccent);
      expect(theme.colorScheme.onPrimaryContainer, accent.lightDeep);
    }
  });

  test('每个主题色都会映射到深色色板与 ColorScheme', () {
    for (final accent in ThemeAccent.values) {
      final theme = AppTheme.dark(accent);
      final palette = theme.extension<AppPalette>();

      expect(palette, isNotNull);
      expect(theme.brightness, Brightness.dark);
      expect(palette!.accent, accent.darkAccent);
      expect(palette.accentDeep, accent.darkDeep);
      expect(palette.accentSoft, accent.darkSoft);
      expect(palette.onAccent, accent.darkOnAccent);
      expect(palette.background, AppPalette.dark.background);
      expect(theme.colorScheme.primary, accent.darkAccent);
      expect(theme.colorScheme.onPrimaryContainer, accent.darkAccent);
    }
  });

  test('默认主题色是玫粉，未知配置回退到默认值', () {
    expect(SettingsProvider.defaultThemeAccent, ThemeAccent.rose);
    expect(ThemeAccent.fromName(null), ThemeAccent.rose);
    expect(ThemeAccent.fromName('not-a-color'), ThemeAccent.rose);
    expect(ThemeAccent.fromName('violet'), ThemeAccent.violet);
    expect(ThemeAccent.values.first, ThemeAccent.rose);
  });

  test('播放页沉浸主题保持白阶，不受主题色影响', () {
    final palette = AppTheme.immersive.extension<AppPalette>();

    expect(palette, isNotNull);
    expect(palette!.accent, const Color(0xFFFFFFFF));
    expect(AppTheme.immersive.brightness, Brightness.dark);
  });
}
