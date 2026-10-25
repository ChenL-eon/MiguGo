import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/navigation/app_shell_controller.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/platform/desktop_lyrics_overlay.dart';
import '../services/platform/desktop_lyrics_snapshot.dart';

/// 桌面歌词：把播放状态推给原生置顶浮层，并把浮层控制条的点击转达回播放器。
///
/// 浮层是独立的 Win32 分层窗口，主窗口保持原样，不再被收缩成歌词条。
class DesktopLyricsProvider extends ChangeNotifier {
  DesktopLyricsProvider(
    this._player,
    this._settings,
    this._shell, {
    DesktopLyricsOverlay? overlay,
  }) : _overlay = overlay ?? DesktopLyricsOverlay() {
    _player.addListener(_push);
    _settings.addListener(_push);
    _overlay.listen(_handleControl);
  }

  static const Duration _refreshInterval = Duration(milliseconds: 160);
  static const int _fontStepPt = 2;

  final PlayerProvider _player;
  final SettingsProvider _settings;
  final AppShellController _shell;
  final DesktopLyricsOverlay _overlay;

  bool _enabled = false;
  bool _busy = false;
  String? _error;
  String _signature = '';
  Timer? _ticker;

  bool get enabled => _enabled;

  bool get busy => _busy;

  String? get error => _error;

  bool get supported => _overlay.supported;

  Future<void> toggle() async {
    if (_enabled) {
      await disable();
    } else {
      await enable();
    }
  }

  Future<void> enable() async {
    if (_enabled || _busy || !supported) return;
    _busy = true;
    _error = null;
    notifyListeners();
    final snapshot = _build();
    _signature = snapshot.signature;
    final shown = await _overlay.show(snapshot.toMap());
    _busy = false;
    if (!shown) {
      _error = '无法创建桌面歌词窗口，请确认应用为 Windows 桌面版后重试。';
      notifyListeners();
      return;
    }
    _enabled = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(_refreshInterval, (_) => _push());
    notifyListeners();
  }

  Future<void> disable() async {
    if (!_enabled || _busy) return;
    _busy = true;
    _ticker?.cancel();
    _ticker = null;
    await _overlay.hide();
    _enabled = false;
    _signature = '';
    _busy = false;
    notifyListeners();
  }

  void _handleControl(String event, Map<Object?, Object?> arguments) {
    switch (event) {
      case 'togglePin':
        unawaited(_settings.setDesktopLyricsTopmost(!_settings.desktopLyricsTopmost));
      case 'fontMinus':
        unawaited(
          _settings.setDesktopLyricsFontPt(_settings.desktopLyricsFontPt - _fontStepPt),
        );
      case 'fontPlus':
        unawaited(
          _settings.setDesktopLyricsFontPt(_settings.desktopLyricsFontPt + _fontStepPt),
        );
      case 'toggleLock':
        unawaited(_settings.setDesktopLyricsLocked(!_settings.desktopLyricsLocked));
      case 'previous':
        unawaited(_player.previous());
      case 'playPause':
        unawaited(_player.togglePlayPause());
      case 'next':
        unawaited(_player.next());
      case 'close':
        unawaited(disable());
      case 'openSettings':
        _shell.focusDesktopLyricsSettings();
      case 'moved':
        final x = arguments['x'];
        final y = arguments['y'];
        if (x is int && y is int) {
          unawaited(_settings.setDesktopLyricsPosition([x, y]));
        }
    }
  }

  void _push() {
    if (!_enabled || _busy) return;
    final snapshot = _build();
    if (snapshot.signature == _signature) return;
    _signature = snapshot.signature;
    unawaited(_overlay.update(snapshot.toMap()));
  }

  DesktopLyricsSnapshot _build() {
    return buildDesktopLyricsSnapshot(
      lines: _player.lyrics,
      position: _player.position,
      status: _statusText(),
      fontPt: _settings.desktopLyricsFontPt,
      colorArgb: _settings.desktopLyricsColor.color.toARGB32(),
      unplayedArgb: _settings.desktopLyricsUnplayedColor.color.toARGB32(),
      strokeArgb: _settings.desktopLyricsStroke.color?.toARGB32() ?? 0,
      panelAlpha: _settings.desktopLyricsPanelAlpha,
      doubleLine: _settings.desktopLyricsDoubleLine,
      topmost: _settings.desktopLyricsTopmost,
      locked: _settings.desktopLyricsLocked,
      playing: _player.isPlaying,
      windowPosition: _settings.desktopLyricsPosition,
    );
  }

  String _statusText() {
    final song = _player.currentSong;
    if (song == null) return 'MiguGo 桌面歌词';
    if (_player.lyricsLoading) return '歌词加载中…';
    final message = _player.lyricsMessage;
    if (message != null && message.isNotEmpty) return message;
    return song.name;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player.removeListener(_push);
    _settings.removeListener(_push);
    _overlay.stopListening();
    super.dispose();
  }
}
