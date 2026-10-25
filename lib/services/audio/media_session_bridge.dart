import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart';

import '../../models/playback_mode.dart';
import '../../models/song.dart';

/// 系统媒体会话桥接：
/// - Android：媒体通知、锁屏控制与前台服务；
/// - Windows：任务栏/系统媒体浮层（SMTC）。
class MediaSessionBridge {
  final FlutterMediaSession _session = FlutterMediaSession();
  bool _initialized = false;
  bool _activated = false;
  String? _lastCoverUrl;
  String? _lastSongId;
  Duration? _lastDuration;

  bool get isActive => _activated;

  Future<void> initialize({
    required VoidCallback onPlay,
    required VoidCallback onPause,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    required VoidCallback onStop,
    required ValueChanged<Duration> onSeek,
  }) async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isWindows) {
      try {
        await _session.setWindowsAppUserModelId(
          'cn.migulele.miguLele',
          displayName: 'MiguGo',
        );
      } catch (error) {
        debugPrint('初始化 Windows 媒体标识失败：$error');
      }
    }

    _session.setActionHandler(
      onPlay: onPlay,
      onPause: onPause,
      onSkipToNext: onNext,
      onSkipToPrevious: onPrevious,
      onStop: onStop,
      onSeekTo: onSeek,
    );
    // just_audio 已经通过 audio_session 管理音频焦点，禁止插件重复抢占。
    try {
      await _session.setAutoHandleInterruptions(false);
    } catch (_) {
      // 部分平台无此实现，不影响播放。
    }
  }

  Future<void> activate() async {
    if (!_initialized || _activated) return;
    try {
      await _session.activate();
      _activated = true;
      await FlutterMediaSessionPlatform.instance.updateAvailableActions({
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seekTo,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      });
    } catch (error) {
      // 系统媒体会话不可用时，应用内播放仍需正常工作。
      debugPrint('系统媒体会话激活失败：$error');
    }
  }

  Future<void> sync({
    required Song song,
    required bool playing,
    required bool buffering,
    required Duration position,
    required Duration duration,
    required PlaybackMode mode,
    required double speed,
  }) async {
    if (!_activated) return;
    final platform = FlutterMediaSessionPlatform.instance;
    final effectiveDuration = duration > Duration.zero ? duration : song.duration;

    final cover = song.coverUrl;
    if (_lastSongId != song.contentId ||
        _lastCoverUrl != cover ||
        _lastDuration != effectiveDuration) {
      _lastSongId = song.contentId;
      _lastCoverUrl = cover;
      _lastDuration = effectiveDuration;
      try {
        await platform.updateMetadata(
          MediaMetadata(
            title: song.name,
            artist: song.artist,
            album: song.album,
            artworkUri: cover,
            duration: effectiveDuration,
          ),
        );
      } catch (error) {
        debugPrint('更新系统媒体元数据失败：$error');
      }
    }

    try {
      await platform.updatePlaybackState(
        PlaybackState(
          status: buffering
              ? PlaybackStatus.buffering
              : (playing ? PlaybackStatus.playing : PlaybackStatus.paused),
          position: position,
          speed: speed,
          repeatMode: switch (mode) {
            PlaybackMode.listLoop => MediaRepeatMode.all,
            PlaybackMode.singleLoop => MediaRepeatMode.one,
            PlaybackMode.shuffle => MediaRepeatMode.all,
          },
          shuffleModeEnabled: mode == PlaybackMode.shuffle,
        ),
      );
    } catch (error) {
      debugPrint('更新系统播放状态失败：$error');
    }
  }

  Future<void> deactivate() async {
    if (!_activated) return;
    _activated = false;
    try {
      await _session.deactivate();
    } catch (error) {
      debugPrint('关闭系统媒体会话失败：$error');
    }
  }
}
