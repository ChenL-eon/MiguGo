import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:migu_lele/services/auth/session_probe.dart';
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
import 'package:migu_lele/services/platform/global_hotkeys.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

/// 调试版的探测记录是「轮换是否真在续命」唯一的取证出口，入口与导出都要钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AccountProvider> account() async {
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    return AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
      diagnostics: SessionProbeDiagnostics.instance,
    );
  }

  Future<void> pumpSettings(WidgetTester tester) async {
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<AccountProvider>.value(value: await account()),
          ChangeNotifierProvider<DesktopLyricsProvider>.value(value: lyrics),
          ChangeNotifierProvider<AppShellController>.value(value: shell),
          Provider<GlobalHotkeyService>.value(value: hotkeys),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();
  }

  testWidgets('调试版可复制与清空登录探测记录', (tester) async {
    expect(kDebugMode, isTrue);
    final preferences = await SharedPreferences.getInstance();
    final diagnostics = SessionProbeDiagnostics(
      preferences: preferences,
      enabled: true,
    );
    await diagnostics.record(
      SessionProbeRecord(
        at: DateTime(2026, 10, 25, 15),
        trigger: 'keep-alive',
        verdict: SessionProbe.alive,
        officialStatus: 200,
        officialCode: '000000',
        rotationHeader: true,
        rotated: true,
        expiryFromResponse: DateTime(2026, 11, 24, 15),
      ),
    );

    const channel = OptionalMethodChannel(
      'flutter/platform',
      JSONMethodCodec(),
    );
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(call.arguments['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await pumpSettings(tester);

    expect(find.text('登录探测记录（调试）'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '试一次续期'), findsOneWidget);

    // 这个入口不联网也要能落一条记录：测试里的账号没有留存票据，
    // 提示必须实话实说，不能写成「已发起」。
    await tester.tap(find.widgetWithText(OutlinedButton, '试一次续期'));
    await tester.pumpAndSettle();
    expect(
      find.text('本机没有留存票据，这次没试，稍等再点「复制记录」看 renewal 那行。'),
      findsOneWidget,
    );

    // 账户分组下面还有别的卡片，按钮可能被挤到视口外，先滚到眼前再点。
    final copyButton = find.widgetWithText(OutlinedButton, '复制记录');
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(copied.single, contains('keep-alive'));
    expect(copied.single, contains('2026-11-24'));
    expect(copied.single, contains('调试：本机没有可用票据'));
    expect(find.text('登录探测记录已复制，可直接粘贴发送。'), findsOneWidget);

    final clearButton = find.widgetWithText(TextButton, '清空记录');
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('登录探测记录已清空。'), findsOneWidget);
    expect(await SessionProbeDiagnostics.instance.load(), isEmpty);
    expect(preferences.getString(SessionProbeDiagnostics.storageKey), isNull);
  });
}
