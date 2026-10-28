import 'dart:io';

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
import 'package:migu_lele/services/auth/session_probe_diagnostics.dart';
import 'package:migu_lele/services/platform/global_hotkeys.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

/// 「关闭主窗口后常驻托盘」这一项：只在 Windows 出现，点开要真的落到偏好里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAccountSettings(
    WidgetTester tester,
    SettingsProvider settings,
  ) async {
    final storage = FakeSecureCookieStorage();
    final player = PlayerProvider(
      MiguMusicApi(
        client: MiguApiClient(
          cookieStore: MiguCookieStore(secureStorage: storage),
        ),
      ),
    );
    final shell = AppShellController();
    final (ledger, _) = testLedger();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<AccountProvider>.value(
            value: AccountProvider(
              cookieStore: MiguCookieStore(secureStorage: storage),
              authSessionStore: AuthSessionStore(storage: storage),
              passportTicketStore: PassportTicketStore(storage: storage),
              ledger: ledger,
              diagnostics: SessionProbeDiagnostics.instance,
            ),
          ),
          ChangeNotifierProvider<DesktopLyricsProvider>.value(
            value: DesktopLyricsProvider(player, settings, shell),
          ),
          ChangeNotifierProvider<AppShellController>.value(value: shell),
          Provider<GlobalHotkeyService>.value(
            value: GlobalHotkeyService(player, settings),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();
  }

  testWidgets('开关只在 Windows 出现，点开即写进偏好并在重启后保留', (tester) async {
    final settings = SettingsProvider();
    await settings.load();
    await pumpAccountSettings(tester, settings);

    final row = find.text('关闭主窗口后常驻托盘');
    if (!Platform.isWindows) {
      // 安卓没有托盘，后台进程也随时被系统回收，界面不能给出做不到的承诺。
      expect(row, findsNothing);
      return;
    }

    expect(row, findsOneWidget);
    // 账户分组一次只渲染这一组，页面里唯一的一枚开关就是这一项。
    final toggle = find.byType(Switch);
    expect(toggle, findsOneWidget);
    expect(
      tester.widget<Switch>(toggle).value,
      isFalse,
      reason: '隐私政策承诺这一项默认关闭',
    );

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(settings.backgroundKeepAliveEnabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('background_keep_alive_v1'), isTrue);

    final restored = SettingsProvider();
    await restored.load();
    expect(restored.backgroundKeepAliveEnabled, isTrue);
  });
}
