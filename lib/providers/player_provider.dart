import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/utils/lyric_parser.dart';
import '../models/audio_quality.dart';
import '../models/lyric_line.dart';
import '../models/playback_mode.dart';
import '../models/song.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_music_api.dart';
import '../services/audio/media_session_bridge.dart';
import 'settings_provider.dart';

/// 播放状态管理：负责队列、在线流地址、歌词同步与系统媒体会话。
class PlayerProvider extends ChangeNotifier {
  PlayerProvider(this._api, {SettingsProvider? settings})
    // ignore: prefer_initializing_formals
    : _settings = settings;

  final MiguMusicApi _api;
  final SettingsProvider? _settings;
  final AudioPlayer _player = AudioPlayer();
  final MediaSessionBridge _mediaSession = MediaSessionBridge();
  final Random _random = Random();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<Song> _queue = const [];
  int _currentIndex = -1;
  PlaybackMode _mode = PlaybackMode.listLoop;
  List<LyricLine> _lyrics = const [];
  bool _initialized = false;
  bool _isLoading = false;
  bool _isPlaying = false;
  bool _lyricsLoading = false;
  bool _completionHandled = false;
  String? _error;
  MiguApiException? _errorDetail;
  String? _lyricsMessage;
  double _volume = 1.0;
  double _speed = 1.0;
  int _loadToken = 0;

  /// 已经为哪首歌自动重取过播放地址；同一首歌只自愈一次。
  String? _autoRefetchedFor;
  ProcessingState _processingState = ProcessingState.idle;
  Timer? _mediaProgressTimer;
  Timer? _sleepTicker;
  DateTime? _sleepDeadline;
  Duration? _sleepDuration;

  /// 睡眠定时的候选档位；`delay == null` 表示不开启。
  static const List<({String label, Duration? delay})> sleepTimerOptions = [
    (label: '关闭', delay: null),
    (label: '15 分钟', delay: Duration(minutes: 15)),
    (label: '30 分钟', delay: Duration(minutes: 30)),
    (label: '60 分钟', delay: Duration(minutes: 60)),
    (label: '90 分钟', delay: Duration(minutes: 90)),
  ];

  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;
  PlaybackMode get mode => _mode;
  List<LyricLine> get lyrics => _lyrics;
  bool get isLoading => _isLoading;
  bool get isPlaying => _isPlaying;
  bool get lyricsLoading => _lyricsLoading;
  String? get lyricsMessage => _lyricsMessage;
  String? get error => _error;
  bool get errorCanRelogin => _errorDetail?.canRelogin ?? false;
  double get volume => _volume;
  double get speed => _speed;
  bool get hasSong => currentSong != null;
  bool get canSkip => _queue.length > 1;
  bool get isBuffering =>
      _processingState == ProcessingState.loading ||
      _processingState == ProcessingState.buffering;
  bool get hasSleepTimer => _sleepDeadline != null;
  Duration? get sleepDuration => _sleepDuration;
  Duration? get sleepRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// 当前播放进度；桌面歌词浮层按固定节拍读取它来推进高亮。
  Duration get position => _player.position;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _mode = _settings?.playbackMode ?? PlaybackMode.listLoop;
    _speed = _settings?.playbackSpeed ?? 1;
    if (_settings?.rememberVolume == true) {
      _volume = _settings?.volume ?? 1;
      await _player.setVolume(_volume);
    }

    if (Platform.isAndroid) {
      try {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration.music());
      } catch (error) {
        debugPrint('配置 Android 音频会话失败：$error');
      }
    }

    await _mediaSession.initialize(
      onPlay: () => unawaited(resume()),
      onPause: () => unawaited(pause()),
      onNext: () => unawaited(next()),
      onPrevious: () => unawaited(previous()),
      onStop: () => unawaited(stop()),
      onSeek: (position) => unawaited(seek(position)),
    );

    _subscriptions.add(_player.playerStateStream.listen(_handlePlayerState));
    _subscriptions.add(
      _player.errorStream.listen((error) {
        unawaited(handlePlaybackFailure(error));
      }),
    );
  }

  /// 播放一个队列，从指定歌曲开始。
  Future<void> playQueue(List<Song> songs, int startIndex) async {
    if (songs.isEmpty) return;
    final index = startIndex.clamp(0, songs.length - 1).toInt();
    final isSameSong =
        currentSong?.contentId == songs[index].contentId && _error == null;

    _queue = List<Song>.unmodifiable(songs);
    _currentIndex = index;
    if (isSameSong) {
      _completionHandled = false;
      await seek(Duration.zero);
      if (!_player.playing) {
        _requestPlay();
      }
      notifyListeners();
      return;
    }
    await _loadCurrent();
  }

  Future<void> _loadCurrent({bool autoplay = true}) async {
    final song = currentSong;
    if (song == null) return;

    final token = ++_loadToken;
    _isLoading = true;
    _error = null;
    _errorDetail = null;
    _completionHandled = false;
    _lyrics = const [];
    _lyricsMessage = null;
    _lyricsLoading = true;
    notifyListeners();
    unawaited(_loadLyrics(song, token));

    try {
      await _player.stop();
      final url = await _api.resolvePlaybackUrl(
        song,
        quality: _settings?.audioQuality ?? AudioQuality.hq,
      );
      if (token != _loadToken) return;

      await _player.setUrl(url);
      if (token != _loadToken) return;

      await _player.setLoopMode(
        _mode == PlaybackMode.singleLoop ? LoopMode.one : LoopMode.off,
      );
      await _player.setShuffleModeEnabled(_mode == PlaybackMode.shuffle);
      await _player.setVolume(_volume);
      await _player.setSpeed(_speed);

      await _mediaSession.activate();
      if (token != _loadToken) return;

      _isLoading = false;
      notifyListeners();
      _syncMediaState();
      if (autoplay) _requestPlay();
    } catch (error) {
      if (token != _loadToken) return;
      _isLoading = false;
      if (error is MiguApiException) {
        _error = error.message;
        _errorDetail = error;
      } else {
        _error = '歌曲加载失败，播放链接可能已失效，请重试。';
        _errorDetail = null;
      }
      notifyListeners();
      _syncMediaState();
    }
  }

  Future<void> _loadLyrics(Song song, int token) async {
    try {
      final raw = await _api.fetchLyrics(song);
      if (token != _loadToken) return;
      final lines = raw == null ? <LyricLine>[] : LyricParser.parse(raw);
      _lyrics = lines;
      _lyricsLoading = false;
      _lyricsMessage = lines.isEmpty ? '暂无同步歌词' : null;
      notifyListeners();
    } catch (_) {
      if (token != _loadToken) return;
      _lyricsLoading = false;
      _lyricsMessage = '歌词加载失败';
      notifyListeners();
    }
  }

  Future<void> retryCurrent() async {
    if (currentSong == null || _isLoading) return;
    await _loadCurrent();
  }

  void _requestPlay() {
    final token = _loadToken;
    _completionHandled = false;
    _player.play().catchError((Object error) {
      if (token == _loadToken) {
        unawaited(handlePlaybackFailure(error));
      }
    });
  }

  Future<void> togglePlayPause() async {
    if (currentSong == null) return;
    if (_error != null) {
      await retryCurrent();
      return;
    }
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> resume() async {
    if (currentSong == null) return;
    if (_error != null) {
      await retryCurrent();
      return;
    }
    if (_processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    _requestPlay();
  }

  Future<void> pause() async {
    if (currentSong == null) return;
    await _player.pause();
    _syncMediaState();
  }

  Future<void> stop() async {
    if (currentSong == null) return;
    await _player.pause();
    await _player.seek(Duration.zero);
    _syncMediaState();
  }

  /// 清空队列并停止播放：退出登录时用，免得旧账号已发出的地址继续放。
  Future<void> clearQueue() async {
    _loadToken++;
    setSleepTimer(null);
    _mediaProgressTimer?.cancel();
    _mediaProgressTimer = null;
    await _player.stop();
    _queue = const [];
    _currentIndex = -1;
    _lyrics = const [];
    _lyricsLoading = false;
    _lyricsMessage = null;
    _error = null;
    _errorDetail = null;
    _isLoading = false;
    _isPlaying = false;
    _completionHandled = false;
    _autoRefetchedFor = null;
    _processingState = ProcessingState.idle;
    notifyListeners();
    await _mediaSession.deactivate();
  }

  Future<void> next({bool automatic = false}) async {
    if (_queue.isEmpty) return;
    final length = _queue.length;
    if (length == 1) {
      await playQueue(_queue, 0);
      return;
    }

    int target;
    if (_mode == PlaybackMode.shuffle) {
      target = _random.nextInt(length);
      if (target == _currentIndex) {
        target = (target + 1) % length;
      }
    } else {
      target = (_currentIndex + 1) % length;
    }
    _currentIndex = target;
    await _loadCurrent();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final length = _queue.length;
    if (length == 1) {
      await playQueue(_queue, 0);
      return;
    }
    _currentIndex = (_currentIndex - 1 + length) % length;
    await _loadCurrent();
  }

  Future<void> seek(Duration position) async {
    final duration = _player.duration;
    var target = position;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _player.seek(target);
    _completionHandled = false;
    _syncMediaState();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
    notifyListeners();
    final settings = _settings;
    if (settings != null) {
      unawaited(settings.saveVolume(_volume));
    }
  }

  Future<void> setSpeed(double value) async {
    final normalized = value.clamp(0.5, 2.0).toDouble();
    if ((_speed - normalized).abs() < 0.001) return;
    _speed = normalized;
    await _player.setSpeed(_speed);
    notifyListeners();
    final settings = _settings;
    if (settings != null) {
      unawaited(settings.setPlaybackSpeed(_speed));
    }
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _player.setLoopMode(
      _mode == PlaybackMode.singleLoop ? LoopMode.one : LoopMode.off,
    );
    await _player.setShuffleModeEnabled(_mode == PlaybackMode.shuffle);
    final settings = _settings;
    if (settings != null) {
      unawaited(settings.setPlaybackMode(mode));
    }
    _syncMediaState();
    notifyListeners();
  }

  Future<void> cyclePlaybackMode() async {
    await setPlaybackMode(_mode.next);
  }

  /// 设置睡眠定时；传入 null 表示取消。
  void setSleepTimer(Duration? delay) {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (delay == null || delay <= Duration.zero) {
      _sleepDeadline = null;
      _sleepDuration = null;
      notifyListeners();
      return;
    }
    _sleepDeadline = DateTime.now().add(delay);
    _sleepDuration = delay;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _sleepDeadline?.difference(DateTime.now());
      if (remaining == null || remaining <= Duration.zero) {
        _sleepTicker?.cancel();
        _sleepTicker = null;
        _sleepDeadline = null;
        _sleepDuration = null;
        notifyListeners();
        unawaited(pause());
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _handlePlayerState(PlayerState state) {
    final previousProcessing = _processingState;
    _processingState = state.processingState;
    _isPlaying = state.playing;

    // 真的出声了，说明这一轮的地址是好的：把自愈额度还给这首歌，
    // 之后再次过期还能再补一次，而不是整首歌只有一次机会。
    if (state.playing) _autoRefetchedFor = null;

    if (state.processingState != ProcessingState.completed) {
      _completionHandled = false;
    } else if (previousProcessing != ProcessingState.completed &&
        !_completionHandled &&
        _mode != PlaybackMode.singleLoop) {
      _completionHandled = true;
      unawaited(next(automatic: true));
    }

    _updateMediaProgressTimer();
    notifyListeners();
    _syncMediaState();
  }

  /// 播放失败的自愈入口：地址多半已经过期，替用户重新取一次链。
  ///
  /// README 承诺「链接过期后重新请求」。自动续播时没人会去点重试按钮，
  /// 所以这一步必须自己做；但每首歌只自愈一次——连续失败到上限就停下并把
  /// 错误交给界面，不能变成无限重试打咪咕接口的循环。
  Future<void> handlePlaybackFailure(Object error) async {
    _isLoading = false;
    _error = '音频加载失败，链接可能已过期，请重试。';
    _errorDetail = null;
    debugPrint('音频播放失败：$error');
    notifyListeners();
    _syncMediaState();

    final song = currentSong;
    if (song == null || _autoRefetchedFor == song.contentId) return;
    _autoRefetchedFor = song.contentId;
    await _loadCurrent();
  }

  void _updateMediaProgressTimer() {
    if (_isPlaying && currentSong != null) {
      _mediaProgressTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _syncMediaState(),
      );
    } else {
      _mediaProgressTimer?.cancel();
      _mediaProgressTimer = null;
    }
  }

  void _syncMediaState() {
    final song = currentSong;
    if (song == null) return;
    unawaited(
      _mediaSession.sync(
        song: song,
        playing: _isPlaying,
        buffering: _isLoading || isBuffering,
        position: _player.position,
        duration: _player.duration ?? song.duration,
        mode: _mode,
        speed: _speed,
      ),
    );
  }

  @override
  void dispose() {
    _loadToken++;
    _mediaProgressTimer?.cancel();
    _sleepTicker?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(_mediaSession.deactivate());
    unawaited(_player.dispose());
    super.dispose();
  }
}
