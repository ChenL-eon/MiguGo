import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/android_system_ui.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/lyric_parser.dart';
import '../core/utils/platform_kind.dart';
import '../models/lyric_line.dart';
import '../models/playback_mode.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/web/migu_web_player_url.dart';
import '../widgets/account_center.dart';
import '../widgets/ambient_background.dart';
import '../widgets/android/android_marquee_text.dart';
import '../widgets/android/android_mini_player.dart' show showAndroidPlaybackSheet;
import '../widgets/cover_art.dart';
import '../widgets/player_background.dart';
import '../widgets/player_queue_dialog.dart';
import '../widgets/state_views.dart';
import '../widgets/tag_pill.dart';
import '../widgets/web_player_panel.dart';
import '../widgets/app_window_caption.dart';
import '../widgets/window_chrome.dart';

/// 打开播放页：Android 使用底部上滑转场，其他平台保持原页面路由。
Future<void> openPlayerPage(BuildContext context) {
  final route = isAndroidPlatform
      ? AndroidPlayerRoute<void>(builder: (_) => const PlayerPage())
      : AppPageRoute<void>(builder: (_) => const PlayerPage());
  return Navigator.of(context).push<void>(route);
}

/// 播放页右侧面板当前显示的内容。
enum _PanelView { lyrics, web }

/// 播放页：封面、歌曲信息、逐行歌词与全部播放控制。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerProvider _player;
  final ItemScrollController _lyricScrollController = ItemScrollController();
  final ItemPositionsListener _lyricPositionsListener = ItemPositionsListener.create();
  final PageController _androidPageController = PageController();

  StreamSubscription<Duration>? _positionSubscription;
  Timer? _followResumeTimer;
  Duration _position = Duration.zero;
  int _activeLyricIndex = -1;
  int _lyricLineCount = 0;
  int _androidPageIndex = 0;
  bool _browsingLyrics = false;
  String? _songContentId;
  bool _webPlayerOpen = false;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerProvider>();
    _songContentId = _player.currentSong?.contentId;
    _lyricLineCount = _player.lyrics.length;
    _activeLyricIndex = LyricParser.activeIndex(_player.lyrics, _position);
    _player.addListener(_handlePlayerChanged);
    _positionSubscription = _player.positionStream.listen(_handlePosition);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _player.removeListener(_handlePlayerChanged);
    _followResumeTimer?.cancel();
    _androidPageController.dispose();
    super.dispose();
  }

  void _handlePosition(Duration position) {
    if (!mounted) return;
    _position = position;
    final index = LyricParser.activeIndex(_player.lyrics, position);
    if (index == _activeLyricIndex) return;
    setState(() => _activeLyricIndex = index);
    if (!_browsingLyrics && _autoScrollEnabled) _scrollToActiveLine();
  }

  bool get _autoScrollEnabled =>
      context.read<SettingsProvider>().lyricsAutoScrollEnabled;

  void _handlePlayerChanged() {
    if (!mounted) return;
    var changed = false;

    final contentId = _player.currentSong?.contentId;
    if (contentId != _songContentId) {
      _songContentId = contentId;
      _position = Duration.zero;
      _activeLyricIndex = -1;
      _browsingLyrics = false;
      _followResumeTimer?.cancel();
      changed = true;
    }

    if (_player.lyrics.length != _lyricLineCount) {
      _lyricLineCount = _player.lyrics.length;
      final index = LyricParser.activeIndex(_player.lyrics, _position);
      if (index != _activeLyricIndex) {
        _activeLyricIndex = index;
        changed = true;
      }
      if (_lyricLineCount > 0 && !_browsingLyrics && _autoScrollEnabled) {
        _scrollToActiveLine();
      }
    }

    if (changed) setState(() {});
  }

  void _openWebPlayer() {
    setState(() => _webPlayerOpen = true);
    if (isAndroidPlatform) _selectAndroidPage(1);
  }

  void _handleAndroidPageChanged(int index) {
    if (index == _androidPageIndex) return;
    setState(() => _androidPageIndex = index);
    if (index == 1) _scrollToActiveLine();
  }

  void _selectAndroidPage(int index) {
    if (_androidPageIndex == index) return;
    if (!_androidPageController.hasClients) {
      setState(() => _androidPageIndex = index);
      if (index == 1) _scrollToActiveLine();
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      _androidPageController.animateToPage(
        index,
        duration: AndroidMotion.base,
        curve: AndroidMotion.standard,
      ),
    );
  }

  /// 安卓返回键先收层级：歌词页与网页播放器都挂在第二页，
  /// 回到封面页之后才真正退出播放页。
  bool _collapseAndroidLayer() {
    if (_androidPageIndex == 0) return false;
    _selectAndroidPage(0);
    return true;
  }

  void _handleAndroidBack(BuildContext context) {
    if (_collapseAndroidLayer()) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _reloginAndRetry() async {
    final signedIn = await showAccountCenterDialog(context);
    if (!mounted || !signedIn || _player.currentSong == null) return;
    await _player.retryCurrent();
  }

  void _scrollToActiveLine() {
    final index = _activeLyricIndex;
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_lyricScrollController.isAttached ||
          index >= _player.lyrics.length) {
        return;
      }
      _lyricScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
      );
    });
  }

  void _markBrowsingLyrics() {
    _followResumeTimer?.cancel();
    if (_browsingLyrics || !mounted) return;
    setState(() => _browsingLyrics = true);
  }

  void _scheduleFollowResume() {
    if (!_browsingLyrics) return;
    _followResumeTimer?.cancel();
    _followResumeTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _browsingLyrics = false);
      _scrollToActiveLine();
    });
  }

  void _resumeLyricFollow() {
    _followResumeTimer?.cancel();
    if (_browsingLyrics) setState(() => _browsingLyrics = false);
    _scrollToActiveLine();
  }

  bool _handleLyricScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _markBrowsingLyrics();
    } else if (notification is ScrollEndNotification) {
      _scheduleFollowResume();
    }
    return false;
  }

  void _seekToLine(int index) {
    final lines = _player.lyrics;
    if (index < 0 || index >= lines.length) return;
    _followResumeTimer?.cancel();
    setState(() {
      _browsingLyrics = false;
      _activeLyricIndex = index;
    });
    unawaited(_player.seek(lines[index].start));
    _scrollToActiveLine();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final settings = context.watch<SettingsProvider>();
    final song = player.currentSong;

    if (song == null) {
      if (isAndroidPlatform) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: androidSystemUiStyle(
            statusIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: context.palette.background,
            body: AmbientBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    _buildAndroidHeader(context, player),
                    Expanded(child: _buildNoSong(context)),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: context.palette.background,
        body: AmbientBackground(
          child: Column(
            children: [
              const AppWindowCaption(),
              Expanded(
                child: SafeArea(
                  top: !AppWindowCaption.managed,
                  child: Column(
                    children: [
                      _buildHeader(context, player),
                      Expanded(child: _buildNoSong(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 整屏模糊封面做背景时应用主题不再适用，改用固定的白阶沉浸配色。
    return WindowCaptionOverride(
      brightness: Brightness.dark,
      caption: PlayerBackgroundLayer.captionColor,
      child: Theme(
        data: AppTheme.immersive,
        child: Builder(
          builder: (context) {
            if (isAndroidPlatform) {
              return _buildAndroidPlayer(context, player, settings, song);
            }
            return Scaffold(
              backgroundColor: PlayerBackgroundLayer.baseColor,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  PlayerBackgroundLayer(settings: settings, song: song),
                  // 背景铺到窗口顶边，只把窗口按钮浮在右上角；放在内容之下，
                  // 这样返回键等仍可点，空白处才用来拖动窗口。
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AppWindowCaption(),
                  ),
                  SafeArea(
                    top: !AppWindowCaption.managed,
                    child: Column(
                      children: [
                        _buildHeader(context, player),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 920;
                              if (wide) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(36, 8, 36, 26),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: 400,
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.only(
                                            right: 10,
                                            bottom: 12,
                                          ),
                                          child: _buildDeck(
                                            context,
                                            player,
                                            song,
                                            centered: false,
                                            coverSize: 318,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 34),
                                      Expanded(
                                        child: _buildLyricsPanel(
                                          context,
                                          player,
                                          compact: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final coverSize = math
                                  .min(
                                    math.max(constraints.maxWidth - 96, 180.0),
                                    268.0,
                                  )
                                  .toDouble();
                              return SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 560),
                                    child: Column(
                                      children: [
                                        _buildDeck(
                                          context,
                                          player,
                                          song,
                                          centered: true,
                                          coverSize: coverSize,
                                        ),
                                        const SizedBox(height: 22),
                                        SizedBox(
                                          height: 380,
                                          child: _buildLyricsPanel(
                                            context,
                                            player,
                                            compact: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAndroidPlayer(
    BuildContext context,
    PlayerProvider player,
    SettingsProvider settings,
    Song song,
  ) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: androidSystemUiStyle(
        statusIconBrightness: Brightness.light,
        navigationIconBrightness: Brightness.light,
        navigationBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: _androidPageIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _collapseAndroidLayer();
        },
        child: Scaffold(
          backgroundColor: PlayerBackgroundLayer.baseColor,
          body: Stack(
            fit: StackFit.expand,
            children: [
              PlayerBackgroundLayer(settings: settings, song: song),
              SafeArea(
                child: Column(
                  children: [
                    _buildAndroidHeader(context, player),
                    Expanded(
                      child: PageView(
                        controller: _androidPageController,
                        onPageChanged: _handleAndroidPageChanged,
                        children: [
                          _buildAndroidCoverPage(context, player, song),
                          _buildAndroidLyricsPage(context, player),
                        ],
                      ),
                    ),
                    _buildAndroidPageSwitch(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidHeader(BuildContext context, PlayerProvider player) {
    final palette = context.palette;
    final song = player.currentSong;
    final album = song == null || song.album == '未知专辑' ? '' : song.album;
    final subtitle = song == null
        ? '还没有正在播放的歌曲'
        : album.isEmpty
        ? song.artist
        : '${song.artist} · $album';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AndroidSpacing.sm,
        AndroidSpacing.xxs,
        AndroidSpacing.sm,
        AndroidSpacing.xxs,
      ),
      child: Row(
        children: [
          _AndroidHeaderButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: '收起播放页',
            filled: true,
            onPressed: () => _handleAndroidBack(context),
          ),
          const SizedBox(width: AndroidSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: AndroidMarqueeText(
                        song?.name ?? '正在播放',
                        velocity: 28,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (song != null && song.isVipOnly) ...[
                      const SizedBox(width: AndroidSpacing.xs),
                      TagPill(label: 'VIP', color: palette.gold, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          if (player.hasSong) ...[
            _AndroidHeaderButton(
              icon: Icons.more_horiz_rounded,
              tooltip: '更多播放控制',
              onPressed: () => unawaited(showAndroidPlaybackSheet(context)),
            ),
          ],
        ],
      ),
    );
  }

  /// 参考图的封面页：接近满宽的封面 + 两行歌词预览 + 进度 + 五个控制键。
  /// 歌名与歌手已经上移到顶栏，这里不再重复一遍。
  ///
  /// 封面用 Expanded + 1:1 比例吃剩余高度，但边长封顶在 [AndroidSizes.playerCoverMaxSide]，
  /// 横屏、小屏或大字体时会自动缩小，不再依赖写死的预留高度；
  /// 可用高度不足 420dp（横屏）时预览行让位给控制区。
  Widget _buildAndroidCoverPage(
    BuildContext context,
    PlayerProvider player,
    Song song,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AndroidSpacing.lg,
            compact ? AndroidSpacing.xxs : AndroidSpacing.xs,
            AndroidSpacing.lg,
            compact ? AndroidSpacing.xxs : AndroidSpacing.sm,
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AndroidSizes.playerCoverMaxSide,
                      maxHeight: AndroidSizes.playerCoverMaxSide,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _AndroidCoverStage(song: song),
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: AndroidSpacing.md),
                _AndroidLyricPreview(
                  lyrics: player.lyrics,
                  activeIndex: _activeLyricIndex,
                  loading: player.lyricsLoading,
                  message: player.lyricsMessage,
                  onTap: () => _selectAndroidPage(1),
                ),
              ],
              if (player.error != null) ...[
                const SizedBox(height: AndroidSpacing.sm),
                _ErrorBanner(
                  android: true,
                  message: player.error!,
                  onRetry: () => unawaited(player.retryCurrent()),
                  onRelogin: player.errorCanRelogin
                      ? () => unawaited(_reloginAndRetry())
                      : null,
                  onOpenWebPlayer: song.isVipOnly ? _openWebPlayer : null,
                ),
              ],
              const SizedBox(height: AndroidSpacing.sm),
              PlayerProgressBar(player: player, song: song, android: true),
              const SizedBox(height: AndroidSpacing.xs),
              _AndroidPlaybackControls(player: player),
            ],
          ),
        );
      },
    );
  }

  /// 歌词是否真的带第二语言：解析器把同一时间戳的多行合并成 '\n'，
  /// 没有译文时不给「文A」按钮，避免摆一个按了没反应的开关。
  bool _hasTranslation(PlayerProvider player) =>
      player.lyrics.any((line) => line.text.contains('\n'));

  /// 参考图的歌词页：满版左对齐，底部是字号与译文开关，不再套玻璃卡。
  Widget _buildAndroidLyricsPage(BuildContext context, PlayerProvider player) {
    final song = player.currentSong;
    final settings = context.watch<SettingsProvider>();
    final showWebPlayer = song != null && song.isVipOnly && _webPlayerOpen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AndroidSpacing.md,
        0,
        AndroidSpacing.md,
        AndroidSpacing.xs,
      ),
      child: Column(
        children: [
          if (song != null && song.isVipOnly) ...[
            Align(
              alignment: Alignment.centerRight,
              child: _ViewToggle(
                android: true,
                selected: showWebPlayer ? _PanelView.web : _PanelView.lyrics,
                onChanged: (value) =>
                    setState(() => _webPlayerOpen = value == _PanelView.web),
              ),
            ),
            const SizedBox(height: AndroidSpacing.xs),
          ],
          Expanded(
            child: showWebPlayer
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AndroidRadius.sm),
                    child: MiguWebPlayerPanel(
                      url: MiguWebPlayerUrl.forSong(song),
                      songName: song.name,
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: _buildAndroidLyricsContent(context, player),
                      ),
                      if (_browsingLyrics && _activeLyricIndex >= 0)
                        Positioned(
                          right: AndroidSpacing.xxs,
                          bottom: AndroidSpacing.xs,
                          child: _AndroidBackToCurrent(onTap: _resumeLyricFollow),
                        ),
                    ],
                  ),
          ),
          if (!showWebPlayer && player.lyrics.isNotEmpty) ...[
            const SizedBox(height: AndroidSpacing.sm),
            _AndroidLyricToolbar(
              settings: settings,
              hasTranslation: _hasTranslation(player),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAndroidLyricsContent(BuildContext context, PlayerProvider player) {
    final palette = context.palette;
    if (player.lyrics.isEmpty) {
      if (player.lyricsLoading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AndroidSpacing.sm),
              Text('正在获取歌词…', style: AndroidTextStyles.caption(palette.textMuted)),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AndroidSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off_rounded,
                size: 30,
                color: palette.textMuted.withValues(alpha: 0.7),
              ),
              const SizedBox(height: AndroidSpacing.sm),
              Text(
                player.lyricsMessage ?? '暂无同步歌词',
                textAlign: TextAlign.center,
                style: AndroidTextStyles.body(palette.textMuted),
              ),
              const SizedBox(height: AndroidSpacing.xxs),
              Text(
                '可以继续欣赏音乐',
                style: TextStyle(
                  fontSize: AndroidTypeScale.micro,
                  color: palette.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lyricsSettings = context.watch<SettingsProvider>();
    final step = lyricsSettings.androidLyricFontStep;
    final showTranslation = lyricsSettings.androidLyricTranslationVisible;

    return ShaderMask(
      // 上下边缘渐隐，滚动时歌词不会硬切在页面边界上。
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.07, 0.93, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _markBrowsingLyrics();
            _scheduleFollowResume();
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleLyricScroll,
          child: ScrollablePositionedList.builder(
            itemCount: player.lyrics.length,
            itemScrollController: _lyricScrollController,
            itemPositionsListener: _lyricPositionsListener,
            initialScrollIndex:
                _activeLyricIndex < 0 || _activeLyricIndex >= player.lyrics.length
                ? 0
                : _activeLyricIndex,
            initialAlignment: 0.42,
            padding: const EdgeInsets.symmetric(
              vertical: AndroidSpacing.xl,
              horizontal: AndroidSpacing.xs,
            ),
            itemBuilder: (context, index) {
              final line = player.lyrics[index];
              final active = index == _activeLyricIndex;
              final near = (_activeLyricIndex - index).abs() <= 1;
              // 同一时间戳的第二行按译文处理，字号比主行小一档。
              final parts = line.text.split('\n');
              final translation = showTranslation && parts.length > 1
                  ? parts.skip(1).join(' ')
                  : null;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _seekToLine(index),
                  borderRadius: BorderRadius.circular(AndroidRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AndroidSpacing.sm,
                      vertical: AndroidSpacing.xs + 1,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: AndroidMotion.base,
                          curve: AndroidMotion.standard,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: (active ? 18.0 : 15.0) + step * 1.5,
                            height: 1.42,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active
                                ? palette.textPrimary
                                : near
                                ? palette.textSecondary
                                : palette.textMuted.withValues(alpha: 0.72),
                          ),
                          child: Text(parts.first, textAlign: TextAlign.start),
                        ),
                        if (translation != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            translation,
                            style: TextStyle(
                              fontSize: (active ? 14.0 : 12.5) + step,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: active
                                  ? palette.textSecondary
                                  : palette.textMuted.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 参考图底部的两个圆点：当前页是拉长的胶囊，点一下直接翻到那页。
  Widget _buildAndroidPageSwitch(BuildContext context) {
    return _AndroidPageDots(
      index: _androidPageIndex,
      labels: const ['封面页', '歌词页'],
      onTap: _selectAndroidPage,
    );
  }

  Widget _buildHeader(BuildContext context, PlayerProvider player) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    // 右上角的窗口按钮浮在背景上，头部内容要让开这块区域。
    final rightInset =
        (wide ? 28.0 : 14.0) +
        (AppWindowCaption.managed ? AppWindowCaption.buttonsWidth : 0.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 14, wide ? 16 : 6, rightInset, 6),
      child: Row(
        children: [
          _RoundAction(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正在播放',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                'NOW PLAYING',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 8.5,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (player.hasSong) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: context.palette.fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.palette.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 14,
                    color: context.palette.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${player.currentIndex + 1} / ${player.queue.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 8),
              TagPill(
                label: player.mode.label,
                color: context.palette.mint,
                dense: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNoSong(BuildContext context) {
    return Center(
      child: AppEmptyView(
        title: '还没有正在播放的歌曲',
        message: '回到首页或搜索页，选择一首歌开始在线播放。',
        icon: Icons.music_note_rounded,
        action: OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('返回'),
        ),
      ),
    );
  }

  Widget _buildDeck(
    BuildContext context,
    PlayerProvider player,
    Song song, {
    required bool centered,
    required double coverSize,
  }) {
    return Column(
      children: [
        _CoverStage(song: song, size: coverSize),
        SizedBox(height: centered ? 22 : 26),
        _SongMeta(song: song, centered: centered),
        if (player.error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(
            message: player.error!,
            onRetry: () => unawaited(player.retryCurrent()),
            onRelogin: player.errorCanRelogin
                ? () => unawaited(_reloginAndRetry())
                : null,
            onOpenWebPlayer: song.isVipOnly ? _openWebPlayer : null,
          ),
        ],
        SizedBox(height: centered ? 18 : 24),
        _PlaybackControls(player: player),
        const SizedBox(height: 4),
        PlayerProgressBar(player: player, song: song),
        if (!centered) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                '在线流式播放 · 不保存音频文件',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLyricsPanel(
    BuildContext context,
    PlayerProvider player, {
    required bool compact,
  }) {
    final hasLyrics = player.lyrics.isNotEmpty;
    final song = player.currentSong;
    final showWebPlayer = song != null && song.isVipOnly && _webPlayerOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 6 : 10, 6, compact ? 4 : 8, 12),
          child: Row(
            children: [
              Icon(
                showWebPlayer ? Icons.public_rounded : Icons.lyrics_outlined,
                size: 17,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                showWebPlayer ? '官方网页播放器' : '歌词',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
              if (song != null && song.isVipOnly) ...[
                const SizedBox(width: 10),
                _ViewToggle(
                  selected: showWebPlayer ? _PanelView.web : _PanelView.lyrics,
                  onChanged: (value) =>
                      setState(() => _webPlayerOpen = value == _PanelView.web),
                ),
              ],
              const Spacer(),
              if (!showWebPlayer && player.lyricsLoading)
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else if (!showWebPlayer && hasLyrics)
                Text(
                  _autoScrollEnabled ? '点按歌词跳转' : '点按歌词跳转 · 自动滚动已关',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.palette.textMuted, fontSize: 10),
                ),
            ],
          ),
        ),
        Expanded(
          child: showWebPlayer
              ? MiguWebPlayerPanel(
                  url: MiguWebPlayerUrl.forSong(song),
                  songName: song.name,
                )
              : Stack(
                  children: [
                    Positioned.fill(child: _buildLyricsContent(context, player)),
                    if (_browsingLyrics && _activeLyricIndex >= 0)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: context.palette.surfaceHigh,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            onTap: _resumeLyricFollow,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: context.palette.lineStrong),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    size: 14,
                                    color: context.palette.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '回到当前',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.palette.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildLyricsContent(BuildContext context, PlayerProvider player) {
    if (player.lyrics.isEmpty) {
      if (player.lyricsLoading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 14),
              Text(
                '正在获取歌词…',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off_rounded,
                size: 28,
                color: context.palette.textMuted.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                player.lyricsMessage ?? '暂无同步歌词',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Text(
                '可以继续欣赏音乐',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.textMuted.withValues(alpha: 0.7),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _markBrowsingLyrics();
          _scheduleFollowResume();
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleLyricScroll,
        child: ScrollablePositionedList.builder(
          itemCount: player.lyrics.length,
          itemScrollController: _lyricScrollController,
          itemPositionsListener: _lyricPositionsListener,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
          itemBuilder: (context, index) {
            final line = player.lyrics[index];
            final active = index == _activeLyricIndex;
            final near = (_activeLyricIndex - index).abs() <= 1;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _seekToLine(index),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: active ? 26 : 20,
                      height: 1.6,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      shadows: active
                          ? [Shadow(color: context.palette.shadow, blurRadius: 16)]
                          : const [],
                      color: active
                          ? context.palette.textPrimary
                          : near
                          ? context.palette.textSecondary
                          : context.palette.textMuted,
                    ),
                    child: Text(line.text, textAlign: TextAlign.center),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 桌面端播放页封面：这里边长到 318dp，必须用 [Song.coverUrlLarge] 的
/// 800px 档，列表用的 200px 档放大后会糊。
class _CoverStage extends StatelessWidget {
  const _CoverStage({required this.song, required this.size});

  final Song song;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cover = song.coverUrlLarge ?? song.coverUrl;
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 1.12,
            height: size * 1.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  context.palette.accent.withValues(alpha: 0.16),
                  context.palette.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey('${song.contentId}|$cover'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: context.palette.lineStrong),
                boxShadow: [
                  BoxShadow(
                    color: context.palette.accent.withValues(alpha: 0.09),
                    blurRadius: 60,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: CoverArt(
                imageUrl: cover,
                seed: song.name,
                size: size,
                borderRadius: BorderRadius.circular(28),
                iconSize: size * 0.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongMeta extends StatelessWidget {
  const _SongMeta({required this.song, required this.centered});

  final Song song;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Row(
          mainAxisAlignment: centered
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                song.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: centered ? 24 : 28,
                  height: 1.32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (song.isVipOnly) ...[
              const SizedBox(width: 9),
              TagPill(label: 'VIP', color: context.palette.gold, dense: true),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontSize: 14, color: context.palette.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          song.album == '未知专辑' ? '专辑信息暂缺' : '专辑 · ${song.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 11, color: context.palette.textMuted),
        ),
      ],
    );
  }
}

/// 播放进度条：拖动期间只显示手指位置，松手后才真正 seek。
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.player,
    required this.song,
    this.android = false,
  });

  final PlayerProvider player;
  final Song song;
  final bool android;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  double? _dragFraction;

  /// 拖动开始时的曲目；松手时若已切歌，这次比例就不能再用。
  String? _dragSongId;

  @override
  void didUpdateWidget(covariant PlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.contentId != widget.song.contentId) {
      _dragFraction = null;
      _dragSongId = null;
    }
  }

  String _clock(Duration value) {
    final seconds = value.inSeconds < 0 ? 0 : value.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? widget.song.duration;
        final durationMs = duration.inMilliseconds;
        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          initialData: Duration.zero,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final rawFraction = durationMs > 0
                ? (position.inMilliseconds / durationMs).clamp(0.0, 1.0)
                : 0.0;
            final fraction = (_dragFraction ?? rawFraction).toDouble();
            final shownPosition = _dragFraction == null
                ? position
                : Duration(milliseconds: (durationMs * fraction).round());

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: widget.android ? 4 : 3,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: widget.android ? 7 : 6,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: widget.android ? 16 : 13,
                    ),
                  ),
                  child: Slider(
                    value: fraction,
                    onChangeStart: durationMs > 0
                        ? (value) => setState(() {
                            _dragFraction = value;
                            _dragSongId = widget.song.contentId;
                          })
                        : null,
                    onChanged: durationMs > 0
                        ? (value) => setState(() => _dragFraction = value)
                        : null,
                    onChangeEnd: durationMs > 0
                        ? (value) {
                            // 松手时的 value 仍属拖动开始的那首歌；已经切歌时
                            // 用新歌时长换算会跳到完全无关的位置，宁可放弃这次 seek。
                            final dragSongId = _dragSongId;
                            setState(() {
                              _dragFraction = null;
                              _dragSongId = null;
                            });
                            if (dragSongId != widget.song.contentId) return;
                            unawaited(
                              widget.player.seek(
                                Duration(milliseconds: (durationMs * value).round()),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.android ? 4 : 12),
                  child: Row(
                    children: [
                      Text(
                        _clock(shownPosition),
                        style: TextStyle(
                          fontSize: widget.android ? 11 : 10.5,
                          color: context.palette.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        durationMs > 0 ? _clock(duration) : '--:--',
                        style: TextStyle(
                          fontSize: widget.android ? 11 : 10.5,
                          color: context.palette.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.player});

  final PlayerProvider player;

  IconData get _modeIcon => switch (player.mode) {
    PlaybackMode.listLoop => Icons.repeat_rounded,
    PlaybackMode.singleLoop => Icons.repeat_one_rounded,
    PlaybackMode.shuffle => Icons.shuffle_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        return Row(
          children: [
            Tooltip(
              message: '${player.mode.label}，点击切换播放模式',
              child: Material(
                color: context.palette.fill,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => unawaited(player.cyclePlaybackMode()),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.palette.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_modeIcon, size: 18, color: context.palette.accent),
                        if (!compact) ...[
                          const SizedBox(width: 7),
                          Text(
                            player.mode.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.palette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            _SkipButton(
              icon: Icons.skip_previous_rounded,
              tooltip: '上一首',
              onPressed: () => unawaited(player.previous()),
            ),
            const SizedBox(width: 12),
            _PlayButton(player: player),
            const SizedBox(width: 12),
            _SkipButton(
              icon: Icons.skip_next_rounded,
              tooltip: '下一首',
              onPressed: () => unawaited(player.next()),
            ),
            const Spacer(),
            Tooltip(
              message: '播放列表',
              child: Material(
                color: context.palette.fillSubtle,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => unawaited(showPlayQueueDialog(context)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.palette.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 15,
                          color: context.palette.textMuted,
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${player.currentIndex + 1}/${player.queue.length}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: context.palette.textMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.android = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final action = android
        ? () {
            unawaited(HapticFeedback.selectionClick());
            onPressed();
          }
        : onPressed;
    return IconButton(
      onPressed: action,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: context.palette.textSecondary,
        fixedSize: Size.square(android ? 52 : 44),
        hoverColor: context.palette.hover,
      ),
      icon: Icon(icon, size: android ? 36 : 32),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player, this.android = false});

  final PlayerProvider player;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final icon = player.error != null
        ? Icons.refresh_rounded
        : player.isPlaying
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final tooltip = player.error != null
        ? '重新加载'
        : player.isPlaying
        ? '暂停'
        : '播放';
    final size = android ? 68.0 : 66.0;

    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.palette.accent.withValues(alpha: 0.3),
              blurRadius: android ? 28 : 26,
              offset: Offset(0, android ? 10 : 9),
            ),
          ],
        ),
        child: Material(
          color: context.palette.accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: player.isLoading
                ? null
                : () {
                    if (android) {
                      unawaited(HapticFeedback.selectionClick());
                    }
                    unawaited(player.togglePlayPause());
                  },
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: player.isLoading
                    ? SizedBox(
                        width: 23,
                        height: 23,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: context.palette.onAccent,
                        ),
                      )
                    : Icon(
                        icon,
                        size: android ? 36 : 34,
                        color: context.palette.onAccent,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    this.onRelogin,
    this.onOpenWebPlayer,
    this.android = false,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onRelogin;
  final VoidCallback? onOpenWebPlayer;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onOpenWebPlayer != null)
        TextButton(onPressed: onOpenWebPlayer, child: const Text('官方页面播放')),
      if (onRelogin != null)
        TextButton(onPressed: onRelogin, child: const Text('重新登录')),
      TextButton(onPressed: onRetry, child: const Text('重试')),
    ];

    if (android) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AndroidSpacing.sm,
          AndroidSpacing.xs,
          AndroidSpacing.xs,
          AndroidSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: context.palette.danger.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AndroidRadius.sm),
          border: Border.all(color: context.palette.danger.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: context.palette.danger,
                  ),
                ),
                const SizedBox(width: AndroidSpacing.xs),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: AndroidTypeScale.caption,
                      height: 1.55,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AndroidSpacing.xxs,
              children: actions,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: context.palette.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: context.palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: 11.5,
                height: 1.55,
              ),
            ),
          ),
          if (onOpenWebPlayer != null)
            TextButton(onPressed: onOpenWebPlayer, child: const Text('官方页面播放')),
          if (onRelogin != null)
            TextButton(onPressed: onRelogin, child: const Text('重新登录')),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: context.palette.fill,
        foregroundColor: context.palette.textSecondary,
        fixedSize: const Size(40, 40),
        side: BorderSide(color: context.palette.line),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// 歌词 / 官方网页播放器切换按钮；只在 VIP 曲目上出现。
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.selected,
    required this.onChanged,
    this.android = false,
  });

  final _PanelView selected;
  final ValueChanged<_PanelView> onChanged;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(android ? AndroidRadius.pill : 9);
    return Container(
      padding: EdgeInsets.all(android ? 3 : 2),
      decoration: BoxDecoration(
        color: context.palette.fill,
        borderRadius: radius,
        border: Border.all(color: context.palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(context, _PanelView.lyrics, '歌词'),
          _buildOption(context, _PanelView.web, android ? '网页' : '官方播放器'),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, _PanelView value, String label) {
    final active = value == selected;
    final radius = BorderRadius.circular(android ? AndroidRadius.pill : 7);
    return Material(
      color: active ? context.palette.accentSoft : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: radius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: android ? 10 : 9,
            vertical: android ? 6 : 4,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: android ? 11 : 10.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? context.palette.accent : context.palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Android 播放页顶部的圆形操作按钮。
class _AndroidHeaderButton extends StatelessWidget {
  const _AndroidHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: filled ? context.palette.fill : Colors.transparent,
        foregroundColor: context.palette.textSecondary,
        fixedSize: const Size(46, 46),
        side: filled ? BorderSide(color: context.palette.line) : null,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 24),
    );
  }
}

/// Android 封面页的封面：固定圆角与柔和投影，边长取可用宽高里更小的那个。
///
/// 这里是整屏尺寸，用 [Song.coverUrlLarge] 取 800px 档，列表档的 200px 放大后会糊。
class _AndroidCoverStage extends StatelessWidget {
  const _AndroidCoverStage({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = song.coverUrlLarge ?? song.coverUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight).toDouble();
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Container(
                key: ValueKey('${song.contentId}|$cover'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AndroidRadius.lg),
                  border: Border.all(color: palette.lineStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.06),
                      blurRadius: 48,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CoverArt(
                  imageUrl: cover,
                  seed: song.name,
                  size: size,
                  borderRadius: BorderRadius.circular(AndroidRadius.lg),
                  iconSize: size * 0.2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 封面页下方的两行歌词预览：当前行加粗，下一行灰，点进去就是歌词页。
class _AndroidLyricPreview extends StatelessWidget {
  const _AndroidLyricPreview({
    required this.lyrics,
    required this.activeIndex,
    required this.loading,
    required this.message,
    required this.onTap,
  });

  final List<LyricLine> lyrics;
  final int activeIndex;
  final bool loading;
  final String? message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (lyrics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AndroidSpacing.xxs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            loading ? '正在获取歌词…' : (message ?? '暂无同步歌词'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.45, color: palette.textMuted),
          ),
        ),
      );
    }

    // 起播前 activeIndex 还是 -1，此时把第一行当作当前行预览。
    final current = activeIndex < 0 ? 0 : activeIndex;
    final next = current + 1 < lyrics.length ? current + 1 : null;
    return Semantics(
      button: true,
      label: '查看歌词',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AndroidRadius.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AndroidSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _main(lyrics[current]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: 16.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        next == null ? '' : _main(lyrics[next]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // 参考图预览行右侧的小气泡：整块可点，图标只是「点这里看歌词」的提示。
                const SizedBox(width: AndroidSpacing.xs),
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 15,
                  color: palette.textMuted.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 预览只取主行，译文留给歌词页整版展示。
  static String _main(LyricLine line) => line.text.split('\n').first;
}

/// 歌词页底部的字号与译文开关，对应参考图的 A− / A+ / 文A。
class _AndroidLyricToolbar extends StatelessWidget {
  const _AndroidLyricToolbar({required this.settings, required this.hasTranslation});

  final SettingsProvider settings;
  final bool hasTranslation;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        _AndroidRoundButton(
          tooltip: '减小歌词字号',
          onPressed: settings.androidLyricCanShrinkFont
              ? () => unawaited(
                  settings.setAndroidLyricFontStep(settings.androidLyricFontStep - 1),
                )
              : null,
          child: Text(
            'A−',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: AndroidSpacing.xs),
        _AndroidRoundButton(
          tooltip: '增大歌词字号',
          onPressed: settings.androidLyricCanGrowFont
              ? () => unawaited(
                  settings.setAndroidLyricFontStep(settings.androidLyricFontStep + 1),
                )
              : null,
          child: Text(
            'A+',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
        const Spacer(),
        if (hasTranslation)
          _AndroidRoundButton(
            tooltip: settings.androidLyricTranslationVisible ? '隐藏译文' : '显示译文',
            selected: settings.androidLyricTranslationVisible,
            onPressed: () => unawaited(
              settings.setAndroidLyricTranslationVisible(
                !settings.androidLyricTranslationVisible,
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '文',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: 'A',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 歌词页底部的圆形小按钮，禁用态保留占位避免布局跳动。
class _AndroidRoundButton extends StatelessWidget {
  const _AndroidRoundButton({
    required this.tooltip,
    required this.child,
    this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: selected ? palette.accentSoft : palette.fill,
          shape: const CircleBorder(side: BorderSide(color: Colors.white24, width: 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 44, height: 44, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// Android 封面页的控制排：播放顺序、上一首、播放暂停、下一首、播放列表。
///
/// 五段等宽布局保证 360dp 窄屏下也能横向铺开，且每颗都不小于 44dp。
class _AndroidPlaybackControls extends StatelessWidget {
  const _AndroidPlaybackControls({required this.player});

  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    void tap(VoidCallback action) {
      unawaited(HapticFeedback.selectionClick());
      action();
    }

    return Row(
      children: [
        Expanded(
          child: Center(
            child: _AndroidHeaderButton(
              icon: _androidModeIcon(player.mode),
              tooltip: '${player.mode.label}，点击切换播放顺序',
              onPressed: () => tap(() => unawaited(player.cyclePlaybackMode())),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _SkipButton(
              icon: Icons.skip_previous_rounded,
              tooltip: '上一首',
              onPressed: () => unawaited(player.previous()),
              android: true,
            ),
          ),
        ),
        Expanded(
          child: Center(child: _PlayButton(player: player, android: true)),
        ),
        Expanded(
          child: Center(
            child: _SkipButton(
              icon: Icons.skip_next_rounded,
              tooltip: '下一首',
              onPressed: () => unawaited(player.next()),
              android: true,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _AndroidHeaderButton(
              icon: Icons.playlist_play_rounded,
              tooltip: '播放列表',
              onPressed: () => tap(() => unawaited(showPlayQueueDialog(context))),
            ),
          ),
        ),
      ],
    );
  }
}

IconData _androidModeIcon(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.listLoop => Icons.repeat_rounded,
    PlaybackMode.singleLoop => Icons.repeat_one_rounded,
    PlaybackMode.shuffle => Icons.shuffle_rounded,
  };
}

/// 参考图底部的页面指示点：当前页拉成短胶囊，点任意一颗直接翻到那一页。
class _AndroidPageDots extends StatelessWidget {
  const _AndroidPageDots({
    required this.index,
    required this.labels,
    required this.onTap,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            key: ValueKey('android-page-dot-$i'),
            button: true,
            selected: i == index,
            label: labels[i],
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(AndroidRadius.pill),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedContainer(
                    duration: AndroidMotion.base,
                    curve: AndroidMotion.standard,
                    width: i == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == index
                          ? palette.textPrimary
                          : palette.textMuted.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AndroidRadius.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 用户手动翻歌词后，右下角的「回到当前」按钮。
class _AndroidBackToCurrent extends StatelessWidget {
  const _AndroidBackToCurrent({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceHigh,
      borderRadius: BorderRadius.circular(AndroidRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AndroidRadius.pill),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AndroidSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AndroidRadius.pill),
            border: Border.all(color: palette.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location_rounded, size: 15, color: palette.accent),
              const SizedBox(width: 6),
              Text(
                '回到当前',
                style: TextStyle(
                  fontSize: AndroidTypeScale.caption,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
