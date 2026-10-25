import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/audio_quality.dart';
import 'package:migu_lele/models/lyrics_style.dart';
import 'package:migu_lele/models/player_background.dart';
import 'package:migu_lele/models/theme_accent.dart';
import 'package:migu_lele/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认跟随系统主题、玫粉主题色且常用开关为开启状态', () async {
    final settings = SettingsProvider();
    await settings.load();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.themeAccent, ThemeAccent.rose);
    expect(settings.ambientGlowEnabled, isTrue);
    expect(settings.lyricsAutoScrollEnabled, isTrue);
    expect(settings.inAppSpaceShortcutEnabled, isTrue);
    expect(settings.globalSpaceHotkeyEnabled, isFalse);
    expect(settings.rememberVolume, isTrue);
    expect(settings.recordSearchHistoryEnabled, isTrue);
    expect(settings.searchHistory, isEmpty);
    expect(settings.volume, 1);
    expect(settings.audioQuality, AudioQuality.hq);
    expect(settings.playbackSpeed, 1);
    expect(settings.desktopLyricsDoubleLine, isTrue);
    expect(settings.desktopLyricsColor, DesktopLyricsColor.white);
    expect(settings.desktopLyricsFontPt, 22);
    expect(settings.desktopLyricsTopmost, isTrue);
    expect(settings.desktopLyricsLocked, isFalse);
    expect(settings.desktopLyricsPanelAlpha, 0);
    expect(
      settings.desktopLyricsUnplayedColor,
      SettingsProvider.defaultDesktopLyricsUnplayedColor,
    );
    expect(settings.desktopLyricsStroke, DesktopLyricsStroke.none);
  });

  test('主题与开关会持久化并在重启后恢复', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setAmbientGlowEnabled(false);
    await settings.setLyricsAutoScrollEnabled(false);
    await settings.setInAppSpaceShortcutEnabled(false);
    await settings.setGlobalSpaceHotkeyEnabled(true);

    final restored = SettingsProvider();
    await restored.load();

    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.ambientGlowEnabled, isFalse);
    expect(restored.lyricsAutoScrollEnabled, isFalse);
    expect(restored.inAppSpaceShortcutEnabled, isFalse);
    expect(restored.globalSpaceHotkeyEnabled, isTrue);
  });

  test('主题色会持久化，恢复默认后回到玫粉', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setThemeAccent(ThemeAccent.violet);

    final restored = SettingsProvider();
    await restored.load();
    expect(restored.themeAccent, ThemeAccent.violet);

    await restored.resetToDefaults();
    expect(restored.themeAccent, SettingsProvider.defaultThemeAccent);

    final afterReset = SettingsProvider();
    await afterReset.load();
    expect(afterReset.themeAccent, ThemeAccent.rose);
  });

  test('播放音质选择会持久化并在重启后恢复', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setAudioQuality(AudioQuality.sq);

    final restored = SettingsProvider();
    await restored.load();

    expect(restored.audioQuality, AudioQuality.sq);
  });

  test('搜索历史去重、优先最近一条并限制为 10 条', () async {
    final settings = SettingsProvider();
    await settings.load();

    for (var i = 0; i < 12; i++) {
      await settings.addSearchHistory('关键词 $i');
    }
    await settings.addSearchHistory('关键词 5');

    expect(settings.searchHistory.length, SettingsProvider.maxSearchHistory);
    expect(settings.searchHistory.first, '关键词 5');
    expect(settings.searchHistory.where((item) => item == '关键词 5').length, 1);

    await settings.clearSearchHistory();
    expect(settings.searchHistory, isEmpty);
  });

  test('关闭记录后不再写入搜索历史', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setRecordSearchHistoryEnabled(false);

    await settings.addSearchHistory('不该被记录');
    expect(settings.searchHistory, isEmpty);
  });

  test('记住音量开关控制音量持久化', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setRememberVolume(false);
    await settings.saveVolume(0.4);

    final withoutMemory = SettingsProvider();
    await withoutMemory.load();
    expect(withoutMemory.volume, 1);

    await settings.setRememberVolume(true);
    await settings.saveVolume(0.4);

    final withMemory = SettingsProvider();
    await withMemory.load();
    expect(withMemory.volume, closeTo(0.4, 0.0001));
  });

  test('播放倍速与桌面歌词样式会持久化并在重启后恢复', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setPlaybackSpeed(1.25);
    await settings.setDesktopLyricsDoubleLine(false);
    await settings.setDesktopLyricsColor(DesktopLyricsColor.gold);
    await settings.setDesktopLyricsUnplayedColor(DesktopLyricsColor.pink);
    await settings.setDesktopLyricsStroke(DesktopLyricsStroke.black);
    await settings.setDesktopLyricsFontPt(34);
    await settings.setDesktopLyricsTopmost(false);
    await settings.setDesktopLyricsLocked(true);
    await settings.setDesktopLyricsPanelAlpha(40);
    await settings.setDesktopLyricsPosition([120, 640]);

    final restored = SettingsProvider();
    await restored.load();

    expect(restored.playbackSpeed, 1.25);
    expect(restored.desktopLyricsDoubleLine, isFalse);
    expect(restored.desktopLyricsColor, DesktopLyricsColor.gold);
    expect(restored.desktopLyricsUnplayedColor, DesktopLyricsColor.pink);
    expect(restored.desktopLyricsStroke, DesktopLyricsStroke.black);
    expect(restored.desktopLyricsFontPt, 34);
    expect(restored.desktopLyricsTopmost, isFalse);
    expect(restored.desktopLyricsLocked, isTrue);
    expect(restored.desktopLyricsPanelAlpha, 40);
    expect(restored.desktopLyricsPosition, [120, 640]);
  });

  test('数值偏好写成 int 或 double 都能读取', () async {
    // 偏好文件是外部可编辑的 JSON，1.0 很可能被存成 1；严格 getDouble/getInt 会抛异常。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_volume_v1': 1,
      'playback_speed_v1': 2,
      'desktop_lyrics_font_pt_v2': 26.0,
      'desktop_lyrics_panel_alpha_v1': 40.0,
    });

    final settings = SettingsProvider();
    await settings.load();

    expect(settings.volume, 1);
    expect(settings.playbackSpeed, 2);
    expect(settings.desktopLyricsFontPt, 26);
    expect(settings.desktopLyricsPanelAlpha, 40);
  });

  test('播放倍速会被限制在 0.5× 到 2× 之间', () async {
    final settings = SettingsProvider();
    await settings.load();

    await settings.setPlaybackSpeed(9);
    expect(settings.playbackSpeed, 2);

    await settings.setPlaybackSpeed(0.1);
    expect(settings.playbackSpeed, 0.5);
  });

  test('恢复默认设置会重置倍速与桌面歌词样式', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setPlaybackSpeed(2);
    await settings.setDesktopLyricsDoubleLine(false);
    await settings.setDesktopLyricsColor(DesktopLyricsColor.pink);
    await settings.setDesktopLyricsUnplayedColor(DesktopLyricsColor.gold);
    await settings.setDesktopLyricsStroke(DesktopLyricsStroke.blue);
    await settings.setDesktopLyricsFontPt(16);
    await settings.setDesktopLyricsLocked(true);
    await settings.setDesktopLyricsPanelAlpha(180);
    await settings.setDesktopLyricsPosition([80, 200]);

    await settings.resetToDefaults();

    expect(settings.playbackSpeed, 1);
    expect(settings.desktopLyricsLocked, isFalse);
    expect(settings.desktopLyricsPanelAlpha, 0);
    expect(settings.desktopLyricsPosition, isNull);
    expect(settings.desktopLyricsDoubleLine, isTrue);
    expect(settings.desktopLyricsColor, DesktopLyricsColor.white);
    expect(settings.desktopLyricsFontPt, 22);
    expect(settings.desktopLyricsTopmost, isTrue);
    expect(
      settings.desktopLyricsUnplayedColor,
      SettingsProvider.defaultDesktopLyricsUnplayedColor,
    );
    expect(settings.desktopLyricsStroke, DesktopLyricsStroke.none);
  });

  test('Android 歌词字号档位限幅、持久化并在恢复默认后归零', () async {
    final settings = SettingsProvider();
    await settings.load();

    expect(settings.androidLyricFontStep, 0);
    expect(settings.androidLyricTranslationVisible, isTrue);

    await settings.setAndroidLyricFontStep(9);
    expect(settings.androidLyricFontStep, SettingsProvider.maxAndroidLyricFontStep);
    expect(settings.androidLyricCanGrowFont, isFalse);

    await settings.setAndroidLyricFontStep(-9);
    expect(settings.androidLyricFontStep, SettingsProvider.minAndroidLyricFontStep);
    expect(settings.androidLyricCanShrinkFont, isFalse);

    await settings.setAndroidLyricTranslationVisible(false);

    final restored = SettingsProvider();
    await restored.load();
    expect(restored.androidLyricFontStep, SettingsProvider.minAndroidLyricFontStep);
    expect(restored.androidLyricTranslationVisible, isFalse);

    await restored.resetToDefaults();

    final afterReset = SettingsProvider();
    await afterReset.load();
    expect(afterReset.androidLyricFontStep, 0);
    expect(afterReset.androidLyricTranslationVisible, isTrue);
  });

  test('本机存了越界的歌词字号档位时按上下限读取', () async {
    SharedPreferences.setMockInitialValues({
      'android_lyric_font_step_v1': 99,
      'android_lyric_translation_v1': false,
    });

    final settings = SettingsProvider();
    await settings.load();

    expect(settings.androidLyricFontStep, SettingsProvider.maxAndroidLyricFontStep);
    expect(settings.androidLyricCanGrowFont, isFalse);
    expect(settings.androidLyricTranslationVisible, isFalse);
  });

  test('播放页背景设置会持久化并裁剪模糊范围', () async {
    final settings = SettingsProvider();
    await settings.load();

    expect(settings.playerBackground, PlayerBackground.cover);
    expect(settings.playerBackgroundBlur, SettingsProvider.defaultPlayerBackgroundBlur);
    expect(settings.playerBackgroundImage, isNull);

    await settings.setPlayerBackground(PlayerBackground.custom);
    await settings.setPlayerBackgroundBlur(999);
    await settings.setPlayerBackgroundImage(r'C:\pics\bg.jpg');

    expect(settings.playerBackgroundBlur, SettingsProvider.maxPlayerBackgroundBlur);

    final restored = SettingsProvider();
    await restored.load();
    expect(restored.playerBackground, PlayerBackground.custom);
    expect(restored.playerBackgroundBlur, SettingsProvider.maxPlayerBackgroundBlur);
    expect(restored.playerBackgroundImage, r'C:\pics\bg.jpg');

    await restored.setPlayerBackgroundBlur(-5);
    expect(restored.playerBackgroundBlur, SettingsProvider.minPlayerBackgroundBlur);

    await restored.setPlayerBackgroundImage('   ');
    expect(restored.playerBackgroundImage, isNull);

    await restored.resetToDefaults();
    expect(restored.playerBackground, PlayerBackground.cover);
    expect(restored.playerBackgroundBlur, SettingsProvider.defaultPlayerBackgroundBlur);
    expect(restored.playerBackgroundImage, isNull);
  });

  test('恢复默认设置会重置主题但保留搜索历史', () async {
    final settings = SettingsProvider();
    await settings.load();
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setThemeAccent(ThemeAccent.amber);
    await settings.setAmbientGlowEnabled(false);
    await settings.setAudioQuality(AudioQuality.sq);
    await settings.addSearchHistory('保留我');

    await settings.resetToDefaults();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.themeAccent, ThemeAccent.rose);
    expect(settings.ambientGlowEnabled, isTrue);
    expect(settings.audioQuality, AudioQuality.hq);
    expect(settings.searchHistory, ['保留我']);

    final restored = SettingsProvider();
    await restored.load();
    expect(restored.themeMode, ThemeMode.system);
    expect(restored.searchHistory, ['保留我']);
  });
}
