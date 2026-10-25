import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/navigation/app_page_route.dart';
import 'package:migu_lele/core/theme/android_system_ui.dart';
import 'package:migu_lele/core/theme/android_tokens.dart';
import 'package:migu_lele/core/theme/app_colors.dart';
import 'package:migu_lele/core/theme/app_theme.dart';
import 'package:migu_lele/models/playback_mode.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/models/theme_accent.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/providers/settings_provider.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/widgets/android/android_ui.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(ThemeAccent.rose),
    home: Scaffold(body: Center(child: child)),
  );
}

const _testSong = Song(
  contentId: 'content-1',
  copyrightId: 'copyright-1',
  name: '测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 120),
  isVipOnly: false,
);

/// 只覆盖迷你播放器需要的读取接口，不触碰音频插件与网络。
class _StubPlayer extends PlayerProvider {
  _StubPlayer() : super(MiguMusicApi());

  bool _playing = false;
  PlaybackMode _mode = PlaybackMode.listLoop;
  double _volume = 0.6;
  double _speed = 1.0;

  @override
  Song? get currentSong => _testSong;

  @override
  bool get hasSong => true;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isLoading => false;

  @override
  PlaybackMode get mode => _mode;

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  Stream<Duration> get positionStream =>
      Stream<Duration>.value(const Duration(seconds: 30));

  @override
  Stream<Duration?> get durationStream =>
      Stream<Duration?>.value(const Duration(seconds: 120));

  @override
  Future<void> togglePlayPause() async {
    _playing = !_playing;
    notifyListeners();
  }

  @override
  Future<void> setPlaybackMode(PlaybackMode mode) async {
    _mode = mode;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  @override
  Future<void> setSpeed(double value) async {
    _speed = value;
    notifyListeners();
  }

  Duration? _sleepDelay;

  @override
  bool get hasSleepTimer => _sleepDelay != null;

  @override
  Duration? get sleepDuration => _sleepDelay;

  @override
  void setSleepTimer(Duration? delay) {
    _sleepDelay = delay;
    notifyListeners();
  }
}

Widget _wrapPlayer(Widget child, PlayerProvider player, {double? textScale}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlayerProvider>.value(value: player),
      ChangeNotifierProvider<SettingsProvider>.value(value: SettingsProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(ThemeAccent.rose),
      home: Builder(
        builder: (context) => MediaQuery(
          data: textScale == null
              ? MediaQuery.of(context)
              : MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(child: SizedBox(width: 360, child: child)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('Android token 保持统一的间距、圆角与 48dp 触控下限', () {
    expect(AndroidSpacing.xxs, 4);
    expect(AndroidSpacing.xl, 24);
    expect(AndroidSpacing.xxl, 32);
    expect(AndroidRadius.xl, 28);
    expect(AndroidRadius.sheetTop.topLeft.x, 28);
    expect(AndroidRadius.sheetTop.bottomLeft.x, 0);
    expect(AndroidSizes.touch, greaterThanOrEqualTo(48));
    expect(AndroidTypeScale.pageTitle, greaterThan(AndroidTypeScale.section));
    expect(AndroidTypeScale.section, greaterThan(AndroidTypeScale.listTitle));
    expect(AndroidTypeScale.listTitle, greaterThan(AndroidTypeScale.body));
    expect(AndroidTypeScale.body, greaterThan(AndroidTypeScale.caption));
  });

  test('Android 系统栏样式按亮暗背景切换图标明暗', () {
    final onDark = androidSystemUiStyle(statusIconBrightness: Brightness.light);

    expect(onDark.statusBarColor, Colors.transparent);
    expect(onDark.statusBarIconBrightness, Brightness.light);
    expect(onDark.statusBarBrightness, Brightness.dark);
    expect(onDark.systemNavigationBarColor, Colors.transparent);
    expect(onDark.systemNavigationBarIconBrightness, Brightness.light);
    expect(onDark.systemStatusBarContrastEnforced, isFalse);
    expect(onDark.systemNavigationBarContrastEnforced, isFalse);

    const navColor = Color(0xFFF4F7FC);
    final onLight = androidSystemUiStyle(
      statusIconBrightness: Brightness.dark,
      navigationBarColor: navColor,
    );

    expect(onLight.statusBarIconBrightness, Brightness.dark);
    expect(onLight.statusBarBrightness, Brightness.light);
    expect(onLight.systemNavigationBarColor, navColor);
    expect(onLight.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('分组标题支持副标题与动作点击', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        AndroidSectionHeader(
          title: '今日推荐',
          subtitle: '为你挑选的 20 首歌',
          actionLabel: '换一批',
          onAction: () => tapped = true,
        ),
      ),
    );

    expect(find.text('今日推荐'), findsOneWidget);
    expect(find.text('为你挑选的 20 首歌'), findsOneWidget);
    await tester.tap(find.text('换一批'));
    expect(tapped, isTrue);
  });

  testWidgets('彩色图标徽章渲染指定图标', (tester) async {
    await tester.pumpWidget(
      _wrap(const AndroidIconBadge(icon: Icons.settings_rounded, color: Colors.blue)),
    );

    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  testWidgets('玻璃面板显示内容并隔离重绘', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AndroidGlassSurface(
          padding: EdgeInsets.all(AndroidSpacing.md),
          child: Text('磨砂面板'),
        ),
      ),
    );

    expect(find.text('磨砂面板'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('玻璃面板默认投影分两层，最浓处落在面板下沿之外', (tester) async {
    await tester.pumpWidget(
      _wrap(const AndroidGlassSurface(child: SizedBox(width: 220, height: 44))),
    );

    // 外层 DecoratedBox 才是投影，内层那层是面板底色。
    final outer = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(AndroidGlassSurface),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final shadows = (outer.decoration as BoxDecoration).boxShadow!;
    expect(shadows, hasLength(2));
    for (final shadow in shadows) {
      // 偏移撑不到 σ 的话，最浓的一档就压在面板自己下沿上，
      // 看着就是胶囊底下糊了一道灰；单层大投影就是这么来的。
      expect(
        shadow.offset.dy,
        greaterThanOrEqualTo(shadow.blurRadius / 2),
        reason: '${shadow.offset.dy} < σ=${shadow.blurRadius / 2}',
      );
    }
  });

  testWidgets('底部操作表能打开、展示标题并通过关闭按钮退出', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAndroidSheet<void>(
                context: context,
                title: '播放控制',
                builder: (_) => const Text('音量与倍速'),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('播放控制'), findsOneWidget);
    expect(find.text('音量与倍速'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('播放控制'), findsNothing);
  });

  testWidgets('跑马灯在短文本时不启动滚动', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 300, child: AndroidMarqueeText('短歌名'))),
    );

    expect(find.text('短歌名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跑马灯对超长文本保留完整语义并循环滚动', (tester) async {
    const longText = '这是一首名字非常非常长的歌曲用于验证横向滚动不会被截断';
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 120,
          child: AndroidMarqueeText(longText, startDelay: Duration.zero),
        ),
      ),
    );

    expect(find.text(longText), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('骨架屏渲染占位块且不进入语义树', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AndroidSkeleton(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 160, height: 18),
              SizedBox(height: AndroidSpacing.xs),
              SkeletonLine(width: 100),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SkeletonBox), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部胶囊只有首页与我的，中间唱片点击进播放页', (tester) async {
    var selected = 0;
    var opened = 0;
    final player = _StubPlayer();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrapPlayer(
        AndroidBottomNav(
          selectedIndex: 0,
          onSelect: (value) => selected = value,
          onOpenPlayer: () => opened++,
        ),
        player,
      ),
    );
    await tester.pump();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('歌单'), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    await tester.tap(find.text('我的'));
    expect(selected, 1);

    await tester.tap(find.bySemanticsLabel('播放页'));
    await tester.pump();
    expect(opened, 1);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('选中态不垫常驻色块，靠描边到实心的图标形变区分', (tester) async {
    final player = _StubPlayer();
    Widget nav(int index) => _wrapPlayer(
      AndroidBottomNav(selectedIndex: index, onSelect: (_) {}, onOpenPlayer: () {}),
      player,
    );
    // 形变是两套图标交叉淡入淡出，读它们外面那层 Opacity 就知道当前进度。
    double opacityOf(IconData icon) => tester
        .widget<Opacity>(
          find.ancestor(of: find.byIcon(icon), matching: find.byType(Opacity)),
        )
        .opacity;

    await tester.pumpWidget(nav(0));
    await tester.pump();

    expect(opacityOf(Icons.home_rounded), 1);
    expect(opacityOf(Icons.home_outlined), 0);
    expect(opacityOf(Icons.person_rounded), 0);
    expect(opacityOf(Icons.person_outline_rounded), 1);

    await tester.pumpWidget(nav(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(opacityOf(Icons.home_rounded), inInclusiveRange(0.15, 0.85));
    expect(opacityOf(Icons.person_rounded), inInclusiveRange(0.15, 0.85));

    await tester.pump(const Duration(milliseconds: 200));
    expect(opacityOf(Icons.home_rounded), 0);
    expect(opacityOf(Icons.person_rounded), 1);
  });

  testWidgets('选中项文字用主题色，未选中用次级色', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(
      _wrapPlayer(
        AndroidBottomNav(selectedIndex: 0, onSelect: (_) {}, onOpenPlayer: () {}),
        player,
      ),
    );
    await tester.pump();

    final palette = tester.element(find.text('首页')).palette;
    // InkWell 自己也会插一层 AnimatedDefaultTextStyle，取最近的那层才是导航的。
    Color labelColor(String label) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style
        .color!;

    expect(labelColor('首页'), palette.accent);
    expect(labelColor('我的'), palette.textSecondary);
  });

  testWidgets('切到新选中那格闪一块淡色切面，定住后淡回全透明', (tester) async {
    final player = _StubPlayer();
    Widget nav(int index) => _wrapPlayer(
      AndroidBottomNav(selectedIndex: index, onSelect: (_) {}, onOpenPlayer: () {}),
      player,
    );
    // 切面就是那一格自己的背景，取文字最近的那个 DecoratedBox 即是它。
    Finder facet(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first;
    double alpha(String label) =>
        (tester.widget<DecoratedBox>(facet(label)).decoration as BoxDecoration)
            .color!
            .a;

    await tester.pumpWidget(nav(0));
    await tester.pump();
    expect(alpha('首页'), 0);
    expect(alpha('我的'), 0);

    await tester.pumpWidget(nav(1));
    await tester.pump();
    // 参考端没有渐亮过程：第一帧就落在实测峰值浓度（叠在白胶囊上正是那块淡蓝）。
    expect(alpha('我的'), closeTo(0.13, 0.0001));
    // 被离开的那格不跟着闪。
    expect(alpha('首页'), 0);
    final peakSize = tester.getSize(facet('我的'));
    // 圆角跟胶囊同一档：夹到格子高度的一半，两端都是半圆，不会露出直边。
    final facetRadius =
        ((tester.widget<DecoratedBox>(facet('我的')).decoration as BoxDecoration)
                    .borderRadius!
                as BorderRadius)
            .topLeft
            .x;
    expect(facetRadius, greaterThanOrEqualTo(peakSize.height / 2));
    // 水波纹关掉：切面就是这格唯一的按下反馈，圆形波纹会和胶囊形对不上。
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(of: find.text('我的'), matching: find.byType(InkWell)),
          )
          .splashFactory,
      same(NoSplash.splashFactory),
    );

    // 定住的那 100ms 浓度不掉。
    await tester.pump(const Duration(milliseconds: 90));
    expect(alpha('我的'), closeTo(0.13, 0.0001));

    // 剩下 400ms 线性淡出，中途过半。
    await tester.pump(const Duration(milliseconds: 200));
    expect(alpha('我的'), inInclusiveRange(0.05, 0.09));

    // 淡干净了，静止时不垫任何东西；尺寸全程不变，只有透明度在动。
    await tester.pump(const Duration(milliseconds: 220));
    expect(alpha('我的'), 0);
    expect(tester.getSize(facet('我的')), peakSize);
  });

  testWidgets('关掉动效时底部导航不闪切面', (tester) async {
    final player = _StubPlayer();
    Widget nav(int index) => _wrapPlayer(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AndroidBottomNav(
            selectedIndex: index,
            onSelect: (_) {},
            onOpenPlayer: () {},
          ),
        ),
      ),
      player,
    );
    double alpha(String label) =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color!
            .a;

    await tester.pumpWidget(nav(0));
    await tester.pump();
    await tester.pumpWidget(nav(1));
    await tester.pump();
    expect(alpha('我的'), 0);

    await tester.pump(const Duration(milliseconds: 200));
    expect(alpha('我的'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按住导航格时亮起胶囊形按下底色，松手淡回透明', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(
      _wrapPlayer(
        AndroidBottomNav(selectedIndex: 0, onSelect: (_) {}, onOpenPlayer: () {}),
        player,
      ),
    );
    await tester.pump();
    Finder facet(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first;
    BoxDecoration box(String label) =>
        tester.widget<DecoratedBox>(facet(label)).decoration as BoxDecoration;

    expect(box('我的').color!.a, 0);

    final gesture = await tester.startGesture(tester.getCenter(facet('我的')));
    // 过掉 onTapDown 的 30ms 判定，再把底色那 160ms 走完。
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(AndroidMotion.fast);
    expect(box('我的').color!.a, closeTo(0.09, 0.0001));
    // 形状跟切面同一颗胶囊，不是从触点扩出去的圆。
    final pressedSize = tester.getSize(facet('我的'));
    final pressedRadius = ((box('我的').borderRadius! as BorderRadius).topLeft.x);
    expect(pressedRadius, greaterThanOrEqualTo(pressedSize.height / 2));
    // 没按住的那格不跟着亮。
    expect(box('首页').color!.a, 0);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(AndroidMotion.fast);
    expect(box('我的').color!.a, 0);
    expect(tester.getSize(facet('我的')), pressedSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('循环进度环与迷你条共用同一套几何', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: AndroidSizes.navDiscSize,
          height: AndroidSizes.navDiscSize,
          child: AndroidRingProgress(
            value: 0.4,
            color: Colors.red,
            track: Colors.grey,
            child: const Center(child: Text('唱片')),
          ),
        ),
      ),
    );

    expect(find.text('唱片'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组标题支持右侧自定义控件', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AndroidSectionHeader(
          title: '母带音质 · 精选',
          trailing: Icon(Icons.play_arrow_rounded),
        ),
      ),
    );

    expect(find.text('母带音质 · 精选'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('AndroidShellInset 把底栏高度传给页面', (tester) async {
    double inset = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidShellInset(
          bottom: 150,
          child: Builder(
            builder: (context) {
              inset = AndroidShellInset.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(inset, 150);
  });

  testWidgets('Android 迷你播放器展示歌曲并打开播放控制操作表', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(_wrapPlayer(AndroidMiniPlayer(onOpen: () {}), player));
    await tester.pump();

    expect(find.text('测试歌曲'), findsOneWidget);
    expect(find.text('测试歌手'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(player.isPlaying, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('倍速'), findsOneWidget);
    expect(find.text('音质'), findsOneWidget);
    expect(find.text('定时'), findsOneWidget);
    expect(find.text('播放顺序'), findsNothing);
    expect(find.text('音量'), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Android 搜索框支持提交与清空', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    String? submitted;
    var cleared = 0;

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320,
          child: AndroidSearchField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (value) => submitted = value,
            onClear: () {
              controller.clear();
              cleared++;
            },
          ),
        ),
      ),
    );

    expect(find.text('搜索歌曲、歌手或歌单'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '晴天');
    await tester.pump();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    expect(submitted, '晴天');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(cleared, 1);
    expect(controller.text, isEmpty);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('Android 顶栏展示标题副标题并回传动作', (tester) async {
    var backTapped = false;
    var actionTapped = false;

    await tester.pumpWidget(
      _wrap(
        AndroidPageTopBar(
          title: '歌单',
          subtitle: '咪咕公开歌单',
          onBack: () => backTapped = true,
          actions: [
            IconButton(
              onPressed: () => actionTapped = true,
              tooltip: '刷新歌单',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );

    expect(find.text('歌单'), findsOneWidget);
    expect(find.text('咪咕公开歌单'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(backTapped, isTrue);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(actionTapped, isTrue);
  });

  testWidgets('Android 播放控制宫格只摆倍速/音质/定时，并在子面板里改值', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(
      _wrapPlayer(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(showAndroidPlaybackSheet(context)),
            child: const Text('打开播放控制'),
          ),
        ),
        player,
      ),
    );

    await tester.tap(find.text('打开播放控制'));
    await tester.pumpAndSettle();
    expect(find.text('播放控制'), findsOneWidget);
    expect(find.text('调整倍速、音质与睡眠定时'), findsOneWidget);
    // 三格当前值：1× 倍速、高品质音质、未开定时。
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('高品质'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('播放顺序'), findsNothing);
    expect(find.text('音量'), findsNothing);

    await tester.tap(find.text('倍速'));
    await tester.pumpAndSettle();
    expect(find.text('播放倍速'), findsOneWidget);
    await tester.tap(find.text('2×'));
    await tester.pumpAndSettle();
    expect(player.speed, 2.0);
    expect(find.text('播放控制'), findsOneWidget);

    await tester.tap(find.text('音质'));
    await tester.pumpAndSettle();
    expect(find.text('播放音质'), findsOneWidget);
    await tester.tap(find.text('无损音质'));
    await tester.pumpAndSettle();
    expect(find.text('无损'), findsOneWidget);

    await tester.tap(find.text('定时'));
    await tester.pumpAndSettle();
    expect(find.text('睡眠定时'), findsOneWidget);
    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    expect(player.sleepDuration, const Duration(minutes: 30));
    expect(find.text('30 分钟'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('播放控制'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Android 播放页路由保留上滑过渡', () {
    final route = AndroidPlayerRoute<void>(builder: (_) => const SizedBox.shrink());

    expect(route.transitionDuration, const Duration(milliseconds: 340));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 280));
  });

  testWidgets('定高壳层的字号缩放封顶在 chromeMaxTextScale', (tester) async {
    double? scaledAt240Percent;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.4)),
        child: AndroidBoundedChrome(
          child: Builder(
            builder: (context) {
              scaledAt240Percent = MediaQuery.textScalerOf(context).scale(10);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(scaledAt240Percent, 10 * AndroidSizes.chromeMaxTextScale);
  });

  testWidgets('底部导航在两倍字体下不撑破定高壳层', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(
      _wrapPlayer(
        AndroidBottomNav(selectedIndex: 0, onSelect: (_) {}, onOpenPlayer: () {}),
        player,
        textScale: 2.0,
      ),
    );
    await tester.pump();

    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('迷你播放条在两倍字体下不撑破 60dp 定高', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(
      _wrapPlayer(AndroidMiniPlayer(onOpen: () {}), player, textScale: 2.0),
    );
    await tester.pump();

    expect(find.text('测试歌曲'), findsOneWidget);
    expect(tester.getSize(find.byType(AndroidMiniPlayer)).height, isNot(0));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('分组标题在窄宽度里省略号截断而不是溢出', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 150,
          child: AndroidSectionHeader(
            title: '这是一个非常非常长的分组标题用来验证省略号',
            subtitle: '副标题同样只占一行',
            actionLabel: '更多',
            onAction: () {},
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('这是一个非常非常长的分组标题用来验证省略号'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放控制宫格与子面板选项满足 48dp 触控下限', (tester) async {
    final player = _StubPlayer();
    await tester.pumpWidget(_wrapPlayer(AndroidMiniPlayer(onOpen: () {}), player));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.ancestor(of: find.text('倍速'), matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(AndroidSizes.touch),
    );

    await tester.tap(find.text('倍速'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.ancestor(of: find.text('1.5×'), matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(AndroidSizes.touch),
    );

    // 子面板叠在操作表上，两个关闭按钮各收一层。
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
