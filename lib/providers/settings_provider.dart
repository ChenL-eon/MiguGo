import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_quality.dart';
import '../models/lyrics_style.dart';
import '../models/playback_mode.dart';
import '../models/player_background.dart';
import '../models/theme_accent.dart';

/// 本地设置：全部选项都会立即生效并持久化。
class SettingsProvider extends ChangeNotifier {
  static const _themeModeKey = 'theme_mode_v2';
  static const _themeAccentKey = 'theme_accent_v1';
  static const _ambientGlowKey = 'ambient_glow_v1';
  static const _playbackModeKey = 'playback_mode_v1';
  static const _audioQualityKey = 'audio_quality_v1';
  static const _rememberVolumeKey = 'remember_volume_v1';
  static const _volumeKey = 'saved_volume_v1';
  static const _lyricsAutoScrollKey = 'lyrics_auto_scroll_v1';
  static const _androidLyricFontStepKey = 'android_lyric_font_step_v1';
  static const _androidLyricTranslationKey = 'android_lyric_translation_v1';
  static const _playbackSpeedKey = 'playback_speed_v1';
  static const _desktopLyricsDoubleLineKey = 'desktop_lyrics_double_line_v1';
  static const _desktopLyricsColorKey = 'desktop_lyrics_color_v1';
  static const _desktopLyricsUnplayedColorKey = 'desktop_lyrics_unplayed_color_v1';
  static const _desktopLyricsStrokeKey = 'desktop_lyrics_stroke_v1';
  static const _desktopLyricsFontPtKey = 'desktop_lyrics_font_pt_v2';
  static const _desktopLyricsTopmostKey = 'desktop_lyrics_topmost_v1';
  static const _desktopLyricsLockedKey = 'desktop_lyrics_locked_v1';
  static const _desktopLyricsPanelAlphaKey = 'desktop_lyrics_panel_alpha_v1';
  static const _desktopLyricsPositionKey = 'desktop_lyrics_position_v1';
  static const _inAppSpaceKey = 'in_app_space_shortcut_v1';
  static const _spaceHotkeyKey = 'global_space_hotkey_v1';
  static const _recordSearchHistoryKey = 'record_search_history_v1';
  static const _searchHistoryKey = 'search_history_v1';
  static const _playerBackgroundKey = 'player_background_v1';
  static const _playerBackgroundBlurKey = 'player_background_blur_v1';
  static const _playerBackgroundImageKey = 'player_background_image_v1';
  static const _backgroundKeepAliveKey = 'background_keep_alive_v1';

  static const ThemeMode defaultThemeMode = ThemeMode.system;
  static const ThemeAccent defaultThemeAccent = ThemeAccent.rose;
  static const int maxSearchHistory = 10;
  static const List<double> playbackSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const int minDesktopLyricsFontPt = 12;
  static const int maxDesktopLyricsFontPt = 40;
  static const int defaultDesktopLyricsFontPt = 22;
  static const int minAndroidLyricFontStep = -2;
  static const int maxAndroidLyricFontStep = 3;
  static const int defaultDesktopLyricsPanelAlpha = 0;
  static const int maxDesktopLyricsPanelAlpha = 200;
  static const DesktopLyricsColor defaultDesktopLyricsUnplayedColor =
      DesktopLyricsColor.silver;
  static const int minPlayerBackgroundBlur = 0;
  static const int maxPlayerBackgroundBlur = 80;
  static const int defaultPlayerBackgroundBlur = 40;

  SharedPreferences? _preferences;
  ThemeMode _themeMode = defaultThemeMode;
  ThemeAccent _themeAccent = defaultThemeAccent;
  bool _ambientGlowEnabled = true;
  PlaybackMode _playbackMode = PlaybackMode.listLoop;
  AudioQuality _audioQuality = AudioQuality.hq;
  bool _rememberVolume = true;
  double _volume = 1;
  bool _lyricsAutoScrollEnabled = true;
  int _androidLyricFontStep = 0;
  bool _androidLyricTranslationVisible = true;
  double _playbackSpeed = 1;
  bool _desktopLyricsDoubleLine = true;
  DesktopLyricsColor _desktopLyricsColor = DesktopLyricsColor.white;
  DesktopLyricsColor _desktopLyricsUnplayedColor = defaultDesktopLyricsUnplayedColor;
  DesktopLyricsStroke _desktopLyricsStroke = DesktopLyricsStroke.none;
  int _desktopLyricsFontPt = defaultDesktopLyricsFontPt;
  bool _desktopLyricsTopmost = true;
  bool _desktopLyricsLocked = false;
  int _desktopLyricsPanelAlpha = defaultDesktopLyricsPanelAlpha;
  List<int>? _desktopLyricsPosition;
  bool _inAppSpaceShortcutEnabled = true;
  bool _globalSpaceHotkeyEnabled = false;
  bool _recordSearchHistoryEnabled = true;
  List<String> _searchHistory = const [];
  PlayerBackground _playerBackground = PlayerBackground.cover;
  int _playerBackgroundBlur = defaultPlayerBackgroundBlur;
  String? _playerBackgroundImage;
  bool _backgroundKeepAliveEnabled = false;
  bool _loaded = false;

  bool get loaded => _loaded;
  ThemeMode get themeMode => _themeMode;
  ThemeAccent get themeAccent => _themeAccent;
  bool get ambientGlowEnabled => _ambientGlowEnabled;
  PlaybackMode get playbackMode => _playbackMode;
  AudioQuality get audioQuality => _audioQuality;
  bool get rememberVolume => _rememberVolume;
  double get volume => _volume;
  bool get lyricsAutoScrollEnabled => _lyricsAutoScrollEnabled;

  /// Android 歌词页的字号档位：0 为基准，A−/A+ 各走一格。
  int get androidLyricFontStep => _androidLyricFontStep;
  bool get androidLyricTranslationVisible => _androidLyricTranslationVisible;
  bool get androidLyricCanGrowFont => _androidLyricFontStep < maxAndroidLyricFontStep;
  bool get androidLyricCanShrinkFont => _androidLyricFontStep > minAndroidLyricFontStep;
  double get playbackSpeed => _playbackSpeed;
  bool get desktopLyricsDoubleLine => _desktopLyricsDoubleLine;
  DesktopLyricsColor get desktopLyricsColor => _desktopLyricsColor;
  DesktopLyricsColor get desktopLyricsUnplayedColor => _desktopLyricsUnplayedColor;
  DesktopLyricsStroke get desktopLyricsStroke => _desktopLyricsStroke;
  int get desktopLyricsFontPt => _desktopLyricsFontPt;
  bool get desktopLyricsTopmost => _desktopLyricsTopmost;
  bool get desktopLyricsLocked => _desktopLyricsLocked;
  int get desktopLyricsPanelAlpha => _desktopLyricsPanelAlpha;

  /// 浮层左上角的物理像素坐标，仅由原生窗口拖动后写回。
  List<int>? get desktopLyricsPosition => _desktopLyricsPosition;

  bool get inAppSpaceShortcutEnabled => _inAppSpaceShortcutEnabled;
  bool get globalSpaceHotkeyEnabled => _globalSpaceHotkeyEnabled;
  bool get recordSearchHistoryEnabled => _recordSearchHistoryEnabled;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  PlayerBackground get playerBackground => _playerBackground;
  int get playerBackgroundBlur => _playerBackgroundBlur;

  /// 自定义背景图片的本地绝对路径；未选择或文件已失效时为 null。
  String? get playerBackgroundImage => _playerBackgroundImage;

  /// 关闭主窗口后是否常驻托盘继续保活登录态。只在 Windows 有意义，默认关。
  bool get backgroundKeepAliveEnabled => _backgroundKeepAliveEnabled;

  Future<void> load() async {
    if (_loaded) return;
    _preferences = await SharedPreferences.getInstance();

    final storedTheme = _preferences?.getString(_themeModeKey);
    _themeMode = switch (storedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => defaultThemeMode,
    };
    _themeAccent = ThemeAccent.fromName(_preferences?.getString(_themeAccentKey));
    _ambientGlowEnabled = _preferences?.getBool(_ambientGlowKey) ?? true;
    final storedMode = _preferences?.getString(_playbackModeKey);
    _playbackMode = PlaybackMode.values.firstWhere(
      (mode) => mode.name == storedMode,
      orElse: () => PlaybackMode.listLoop,
    );
    _audioQuality = AudioQuality.fromName(_preferences?.getString(_audioQualityKey));
    _rememberVolume = _preferences?.getBool(_rememberVolumeKey) ?? true;
    _volume = _readDouble(_volumeKey, 1).clamp(0.0, 1.0);
    _lyricsAutoScrollEnabled = _preferences?.getBool(_lyricsAutoScrollKey) ?? true;
    _androidLyricFontStep = _readInt(
      _androidLyricFontStepKey,
      0,
    ).clamp(minAndroidLyricFontStep, maxAndroidLyricFontStep);
    _androidLyricTranslationVisible =
        _preferences?.getBool(_androidLyricTranslationKey) ?? true;
    _playbackSpeed = _readDouble(_playbackSpeedKey, 1).clamp(0.5, 2.0);
    _desktopLyricsDoubleLine =
        _preferences?.getBool(_desktopLyricsDoubleLineKey) ?? true;
    _desktopLyricsColor = DesktopLyricsColor.fromName(
      _preferences?.getString(_desktopLyricsColorKey),
    );
    _desktopLyricsUnplayedColor = DesktopLyricsColor.fromName(
      _preferences?.getString(_desktopLyricsUnplayedColorKey),
      fallback: defaultDesktopLyricsUnplayedColor,
    );
    _desktopLyricsStroke = DesktopLyricsStroke.fromName(
      _preferences?.getString(_desktopLyricsStrokeKey),
    );
    _desktopLyricsFontPt = _readInt(
      _desktopLyricsFontPtKey,
      defaultDesktopLyricsFontPt,
    ).clamp(minDesktopLyricsFontPt, maxDesktopLyricsFontPt);
    _desktopLyricsTopmost = _preferences?.getBool(_desktopLyricsTopmostKey) ?? true;
    _desktopLyricsLocked = _preferences?.getBool(_desktopLyricsLockedKey) ?? false;
    _desktopLyricsPanelAlpha = _readInt(
      _desktopLyricsPanelAlphaKey,
      defaultDesktopLyricsPanelAlpha,
    ).clamp(0, maxDesktopLyricsPanelAlpha);
    _desktopLyricsPosition = _readPosition();
    _inAppSpaceShortcutEnabled = _preferences?.getBool(_inAppSpaceKey) ?? true;
    _globalSpaceHotkeyEnabled = _preferences?.getBool(_spaceHotkeyKey) ?? false;
    _recordSearchHistoryEnabled =
        _preferences?.getBool(_recordSearchHistoryKey) ?? true;
    _searchHistory = _readHistory();
    _playerBackground = PlayerBackground.fromName(
      _preferences?.getString(_playerBackgroundKey),
    );
    _playerBackgroundBlur = _readInt(
      _playerBackgroundBlurKey,
      defaultPlayerBackgroundBlur,
    ).clamp(minPlayerBackgroundBlur, maxPlayerBackgroundBlur);
    _playerBackgroundImage = _readOptionalString(_playerBackgroundImageKey);
    _backgroundKeepAliveEnabled =
        _preferences?.getBool(_backgroundKeepAliveKey) ?? false;

    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _preferences?.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  Future<void> setThemeAccent(ThemeAccent accent) async {
    if (_themeAccent == accent) return;
    _themeAccent = accent;
    await _preferences?.setString(_themeAccentKey, accent.name);
    notifyListeners();
  }

  Future<void> setAmbientGlowEnabled(bool enabled) async {
    if (_ambientGlowEnabled == enabled) return;
    _ambientGlowEnabled = enabled;
    await _preferences?.setBool(_ambientGlowKey, enabled);
    notifyListeners();
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    if (_playbackMode == mode) return;
    _playbackMode = mode;
    await _preferences?.setString(_playbackModeKey, mode.name);
    notifyListeners();
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    if (_audioQuality == quality) return;
    _audioQuality = quality;
    await _preferences?.setString(_audioQualityKey, quality.name);
    notifyListeners();
  }

  Future<void> setRememberVolume(bool enabled) async {
    if (_rememberVolume == enabled) return;
    _rememberVolume = enabled;
    await _preferences?.setBool(_rememberVolumeKey, enabled);
    if (!enabled) {
      await _preferences?.remove(_volumeKey);
    }
    notifyListeners();
  }

  /// 播放器在音量变化时调用；只在“记住音量”开启时落盘。
  Future<void> saveVolume(double value) async {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    if ((_volume - normalized).abs() > 0.0001) {
      _volume = normalized;
      notifyListeners();
    }
    if (_rememberVolume) {
      await _preferences?.setDouble(_volumeKey, normalized);
    }
  }

  Future<void> setLyricsAutoScrollEnabled(bool enabled) async {
    if (_lyricsAutoScrollEnabled == enabled) return;
    _lyricsAutoScrollEnabled = enabled;
    await _preferences?.setBool(_lyricsAutoScrollKey, enabled);
    notifyListeners();
  }

  Future<void> setAndroidLyricFontStep(int step) async {
    final normalized = step.clamp(minAndroidLyricFontStep, maxAndroidLyricFontStep);
    if (_androidLyricFontStep == normalized) return;
    _androidLyricFontStep = normalized;
    await _preferences?.setInt(_androidLyricFontStepKey, normalized);
    notifyListeners();
  }

  Future<void> setAndroidLyricTranslationVisible(bool visible) async {
    if (_androidLyricTranslationVisible == visible) return;
    _androidLyricTranslationVisible = visible;
    await _preferences?.setBool(_androidLyricTranslationKey, visible);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final normalized = speed.clamp(0.5, 2.0).toDouble();
    if ((_playbackSpeed - normalized).abs() < 0.001) return;
    _playbackSpeed = normalized;
    await _preferences?.setDouble(_playbackSpeedKey, normalized);
    notifyListeners();
  }

  Future<void> setDesktopLyricsDoubleLine(bool enabled) async {
    if (_desktopLyricsDoubleLine == enabled) return;
    _desktopLyricsDoubleLine = enabled;
    await _preferences?.setBool(_desktopLyricsDoubleLineKey, enabled);
    notifyListeners();
  }

  Future<void> setDesktopLyricsColor(DesktopLyricsColor color) async {
    if (_desktopLyricsColor == color) return;
    _desktopLyricsColor = color;
    await _preferences?.setString(_desktopLyricsColorKey, color.name);
    notifyListeners();
  }

  Future<void> setDesktopLyricsUnplayedColor(DesktopLyricsColor color) async {
    if (_desktopLyricsUnplayedColor == color) return;
    _desktopLyricsUnplayedColor = color;
    await _preferences?.setString(_desktopLyricsUnplayedColorKey, color.name);
    notifyListeners();
  }

  Future<void> setDesktopLyricsStroke(DesktopLyricsStroke stroke) async {
    if (_desktopLyricsStroke == stroke) return;
    _desktopLyricsStroke = stroke;
    await _preferences?.setString(_desktopLyricsStrokeKey, stroke.name);
    notifyListeners();
  }

  Future<void> setDesktopLyricsFontPt(int size) async {
    final normalized = size.clamp(minDesktopLyricsFontPt, maxDesktopLyricsFontPt);
    if (_desktopLyricsFontPt == normalized) return;
    _desktopLyricsFontPt = normalized;
    await _preferences?.setInt(_desktopLyricsFontPtKey, normalized);
    notifyListeners();
  }

  Future<void> setDesktopLyricsTopmost(bool enabled) async {
    if (_desktopLyricsTopmost == enabled) return;
    _desktopLyricsTopmost = enabled;
    await _preferences?.setBool(_desktopLyricsTopmostKey, enabled);
    notifyListeners();
  }

  Future<void> setDesktopLyricsLocked(bool enabled) async {
    if (_desktopLyricsLocked == enabled) return;
    _desktopLyricsLocked = enabled;
    await _preferences?.setBool(_desktopLyricsLockedKey, enabled);
    notifyListeners();
  }

  Future<void> setDesktopLyricsPanelAlpha(int alpha) async {
    final normalized = alpha.clamp(0, maxDesktopLyricsPanelAlpha);
    if (_desktopLyricsPanelAlpha == normalized) return;
    _desktopLyricsPanelAlpha = normalized;
    await _preferences?.setInt(_desktopLyricsPanelAlphaKey, normalized);
    notifyListeners();
  }

  Future<void> setDesktopLyricsPosition(List<int>? position) async {
    final current = _desktopLyricsPosition;
    if (position == null || position.length < 2) {
      if (current == null) return;
      _desktopLyricsPosition = null;
      await _preferences?.remove(_desktopLyricsPositionKey);
      notifyListeners();
      return;
    }
    if (current != null && current[0] == position[0] && current[1] == position[1]) {
      return;
    }
    _desktopLyricsPosition = [position[0], position[1]];
    await _preferences?.setString(
      _desktopLyricsPositionKey,
      '${position[0]},${position[1]}',
    );
    notifyListeners();
  }

  Future<void> setInAppSpaceShortcutEnabled(bool enabled) async {
    if (_inAppSpaceShortcutEnabled == enabled) return;
    _inAppSpaceShortcutEnabled = enabled;
    await _preferences?.setBool(_inAppSpaceKey, enabled);
    notifyListeners();
  }

  Future<void> setGlobalSpaceHotkeyEnabled(bool enabled) async {
    if (_globalSpaceHotkeyEnabled == enabled) return;
    _globalSpaceHotkeyEnabled = enabled;
    await _preferences?.setBool(_spaceHotkeyKey, enabled);
    notifyListeners();
  }

  Future<void> setRecordSearchHistoryEnabled(bool enabled) async {
    if (_recordSearchHistoryEnabled == enabled) return;
    _recordSearchHistoryEnabled = enabled;
    await _preferences?.setBool(_recordSearchHistoryKey, enabled);
    notifyListeners();
  }

  Future<void> setBackgroundKeepAliveEnabled(bool enabled) async {
    if (_backgroundKeepAliveEnabled == enabled) return;
    _backgroundKeepAliveEnabled = enabled;
    await _preferences?.setBool(_backgroundKeepAliveKey, enabled);
    notifyListeners();
  }

  Future<void> addSearchHistory(String query) async {
    if (!_recordSearchHistoryEnabled) return;
    final value = query.trim();
    if (value.isEmpty) return;
    final next = [
      value,
      ..._searchHistory.where((item) => item != value),
    ].take(maxSearchHistory).toList();
    if (_listEquals(next, _searchHistory)) return;
    _searchHistory = next;
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    if (_searchHistory.isEmpty) return;
    _searchHistory = const [];
    await _preferences?.remove(_searchHistoryKey);
    notifyListeners();
  }

  Future<void> setPlayerBackground(PlayerBackground value) async {
    if (_playerBackground == value) return;
    _playerBackground = value;
    await _preferences?.setString(_playerBackgroundKey, value.name);
    notifyListeners();
  }

  Future<void> setPlayerBackgroundBlur(int value) async {
    final normalized = value.clamp(minPlayerBackgroundBlur, maxPlayerBackgroundBlur);
    if (_playerBackgroundBlur == normalized) return;
    _playerBackgroundBlur = normalized;
    await _preferences?.setInt(_playerBackgroundBlurKey, normalized);
    notifyListeners();
  }

  Future<void> setPlayerBackgroundImage(String? path) async {
    final value = path?.trim();
    final next = (value == null || value.isEmpty) ? null : value;
    if (_playerBackgroundImage == next) return;
    _playerBackgroundImage = next;
    final preferences = _preferences;
    if (preferences != null) {
      if (next == null) {
        await preferences.remove(_playerBackgroundImageKey);
      } else {
        await preferences.setString(_playerBackgroundImageKey, next);
      }
    }
    notifyListeners();
  }

  /// 只重置应用设置，不清除登录 Cookie 与搜索历史。
  Future<void> resetToDefaults() async {
    _themeMode = defaultThemeMode;
    _themeAccent = defaultThemeAccent;
    _ambientGlowEnabled = true;
    _playbackMode = PlaybackMode.listLoop;
    _audioQuality = AudioQuality.hq;
    _rememberVolume = true;
    _volume = 1;
    _lyricsAutoScrollEnabled = true;
    _androidLyricFontStep = 0;
    _androidLyricTranslationVisible = true;
    _playbackSpeed = 1;
    _desktopLyricsDoubleLine = true;
    _desktopLyricsColor = DesktopLyricsColor.white;
    _desktopLyricsUnplayedColor = defaultDesktopLyricsUnplayedColor;
    _desktopLyricsStroke = DesktopLyricsStroke.none;
    _desktopLyricsFontPt = defaultDesktopLyricsFontPt;
    _desktopLyricsTopmost = true;
    _desktopLyricsLocked = false;
    _desktopLyricsPanelAlpha = defaultDesktopLyricsPanelAlpha;
    _desktopLyricsPosition = null;
    _inAppSpaceShortcutEnabled = true;
    _globalSpaceHotkeyEnabled = false;
    _recordSearchHistoryEnabled = true;
    _playerBackground = PlayerBackground.cover;
    _playerBackgroundBlur = defaultPlayerBackgroundBlur;
    _playerBackgroundImage = null;
    final preferences = _preferences;
    if (preferences != null) {
      await preferences.remove(_themeModeKey);
      await preferences.remove(_themeAccentKey);
      await preferences.remove(_ambientGlowKey);
      await preferences.remove(_playbackModeKey);
      await preferences.remove(_audioQualityKey);
      await preferences.remove(_rememberVolumeKey);
      await preferences.remove(_volumeKey);
      await preferences.remove(_lyricsAutoScrollKey);
      await preferences.remove(_androidLyricFontStepKey);
      await preferences.remove(_androidLyricTranslationKey);
      await preferences.remove(_playbackSpeedKey);
      await preferences.remove(_desktopLyricsDoubleLineKey);
      await preferences.remove(_desktopLyricsColorKey);
      await preferences.remove(_desktopLyricsUnplayedColorKey);
      await preferences.remove(_desktopLyricsStrokeKey);
      await preferences.remove(_desktopLyricsFontPtKey);
      await preferences.remove(_desktopLyricsTopmostKey);
      await preferences.remove(_desktopLyricsLockedKey);
      await preferences.remove(_desktopLyricsPanelAlphaKey);
      await preferences.remove(_desktopLyricsPositionKey);
      await preferences.remove(_inAppSpaceKey);
      await preferences.remove(_spaceHotkeyKey);
      await preferences.remove(_recordSearchHistoryKey);
      await preferences.remove(_playerBackgroundKey);
      await preferences.remove(_playerBackgroundBlurKey);
      await preferences.remove(_playerBackgroundImageKey);
    }
    notifyListeners();
  }

  /// 偏好文件里同一个数值键可能写成 `1` 也可能写成 `1.0`，
  /// getDouble/getInt 会直接抛类型异常导致启动白屏，所以统一按 num 取。
  double _readDouble(String key, double fallback) {
    final value = _preferences?.get(key);
    return value is num ? value.toDouble() : fallback;
  }

  int _readInt(String key, int fallback) {
    final value = _preferences?.get(key);
    return value is num ? value.round() : fallback;
  }

  String? _readOptionalString(String key) {
    final value = _preferences?.getString(key)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  List<int>? _readPosition() {
    final raw = _preferences?.getString(_desktopLyricsPositionKey);
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final x = int.tryParse(parts[0].trim());
    final y = int.tryParse(parts[1].trim());
    if (x == null || y == null || x < 0 || y < 0) return null;
    return [x, y];
  }

  List<String> _readHistory() {
    final raw = _preferences?.getString(_searchHistoryKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      final values = <String>[];
      for (final item in data) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty && !values.contains(value)) values.add(value);
      }
      return values.take(maxSearchHistory).toList();
    } catch (error) {
      debugPrint('读取搜索历史失败：$error');
      return const [];
    }
  }

  Future<void> _persistHistory() async {
    final preferences = _preferences;
    if (preferences == null) return;
    if (_searchHistory.isEmpty) {
      await preferences.remove(_searchHistoryKey);
    } else {
      await preferences.setString(_searchHistoryKey, jsonEncode(_searchHistory));
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
