import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/navigation/app_shell_controller.dart';
import 'package:migu_lele/pages/settings_page.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/providers/desktop_lyrics_provider.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/providers/settings_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/platform/global_hotkeys.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

/// 桌面端宽栏是设置的唯一导航，分组清单与选中底色的画法都在这里钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpWideSettings(WidgetTester tester) async {
    // 880 以上才走「左栏 + 右栏」的宽版，窄版是逐级下钻、不留选中底色。
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settings = SettingsProvider();
    await settings.load();
    final player = PlayerProvider(
      MiguMusicApi(
        client: MiguApiClient(
          cookieStore: MiguCookieStore(
            secureStorage: FakeSecureCookieStorage(),
          ),
        ),
      ),
    );
    final shell = AppShellController();
    final lyrics = DesktopLyricsProvider(player, settings, shell);
    final hotkeys = GlobalHotkeyService(player, settings);
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<AccountProvider>.value(
            value: AccountProvider(
              cookieStore: cookieStore,
              authSessionStore: AuthSessionStore(storage: storage),
              passportTicketStore: PassportTicketStore(storage: storage),
              ledger: ledger,
            ),
          ),
          ChangeNotifierProvider<DesktopLyricsProvider>.value(value: lyrics),
          ChangeNotifierProvider<AppShellController>.value(value: shell),
          Provider<GlobalHotkeyService>.value(value: hotkeys),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('桌面端左栏不重复「关于」，其余分组照常列出', (tester) async {
    await pumpWideSettings(tester);

    // 桌面端左栏另有专门的关于页，设置里再列一份是重复入口；
    // 手机端没有那个入口，靠 isAndroidPlatform 保留，不受这条约束。
    expect(find.text('关于'), findsNothing);
    for (final label in [
      '外观',
      '播放与音效',
      '歌词与播放画面',
      '快捷键',
      '通用',
      '账户',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少分组 $label');
    }
  });

  testWidgets('切换分组时选中底色只有一枚，且不做位移动画', (tester) async {
    await pumpWideSettings(tester);

    final selection = find.byKey(const ValueKey('settings-nav-selection'));
    expect(selection, findsOneWidget);

    await tester.tap(find.text('通用').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // 切换途中也只有一枚：滑块在列表上跑一趟的话，跑过的每一行都像多出一块。
    expect(selection, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(AnimatedPositioned),
      ),
      findsNothing,
    );

    await tester.pumpAndSettle();
    expect(selection, findsOneWidget);
  });

  testWidgets('导航项不铺水波纹，选中行也不再叠悬停亮底', (tester) async {
    await pumpWideSettings(tester);

    // 涟漪绽在选中底色上就是第二块亮底，淡出那半秒看着像拖影；
    // 悬停亮底叠在已有底色的选中行上，同样是两块。
    final ink = find.ancestor(
      of: find.text('外观').first,
      matching: find.byType(InkWell),
    );
    expect(ink, findsOneWidget);
    final tile = tester.widget<InkWell>(ink);
    expect(tile.splashFactory, same(NoSplash.splashFactory));
    expect(tile.highlightColor, Colors.transparent);
    expect(tile.hoverColor, Colors.transparent);
  });
}
