import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/navigation/app_shell_controller.dart';
import 'package:migu_lele/models/player_background.dart';
import 'package:migu_lele/pages/settings_page.dart';
import 'package:migu_lele/providers/desktop_lyrics_provider.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/providers/settings_provider.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/platform/global_hotkeys.dart';
import 'package:migu_lele/services/platform/native_file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

PlayerProvider _player() {
  return PlayerProvider(
    MiguMusicApi(
      client: MiguApiClient(
        cookieStore: MiguCookieStore(secureStorage: FakeSecureCookieStorage()),
      ),
    ),
  );
}

/// 系统文件选择框只能弹一个：选取未返回时再点按钮不该重复拉起。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('migu_lele/file_picker');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('选择背景图未返回时再次点击不会重复拉起文件选择器', (tester) async {
    final directory = Directory.systemTemp.createTempSync('migugo_bg_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/bg.png')
      ..writeAsBytesSync(base64Decode(_onePixelPng));

    final gate = Completer<void>();
    var pickerCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      pickerCalls++;
      await gate.future;
      return image.path;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      if (!gate.isCompleted) gate.complete();
    });

    final settings = SettingsProvider();
    await settings.load();
    await settings.setPlayerBackground(PlayerBackground.custom);
    final player = _player();
    final shell = AppShellController();
    final hotkeys = GlobalHotkeyService(player, settings);
    final lyrics = DesktopLyricsProvider(player, settings, shell);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<DesktopLyricsProvider>.value(value: lyrics),
          ChangeNotifierProvider<AppShellController>.value(value: shell),
          Provider<GlobalHotkeyService>.value(value: hotkeys),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // 设置页先显示分组菜单，播放页背景收在「歌词与播放画面」分组里。
    await tester.tap(find.text('歌词与播放画面'));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(TextButton, '选择图片');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pump();
    expect(pickerCalls, 1);

    await tester.tap(button);
    await tester.pump();
    expect(pickerCalls, 1, reason: '上一次选择还没返回，第二次点击应被挡住');

    gate.complete();
    await tester.pumpAndSettle();

    expect(settings.playerBackgroundImage, image.path);
    expect(find.text('已更新播放页背景。'), findsOneWidget);
  }, skip: !NativeFilePicker.supportsImagePicker);
}
