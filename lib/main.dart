import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/navigation/app_shell_controller.dart';
import 'core/theme/app_colors.dart';
import 'providers/account_provider.dart';
import 'providers/desktop_lyrics_provider.dart';
import 'providers/home_provider.dart';
import 'providers/imported_playlist_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/player_provider.dart';
import 'providers/search_provider.dart';
import 'providers/settings_provider.dart';
import 'services/api/migu_cookie_store.dart';
import 'services/api/migu_music_api.dart';
import 'services/auth/session_keep_alive.dart';
import 'services/auth/session_reject_ledger.dart';
import 'services/auth/web_session_sync.dart';
import 'services/external/external_playlist_service.dart';
import 'services/platform/global_hotkeys.dart';
import 'services/platform/legacy_data_migration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await migrateLegacyWindowsData();
  await MiguCookieStore.instance.init();
  await SessionRejectLedger.instance.init();

  final settings = SettingsProvider();
  await settings.load();

  late final SessionKeepAlive keepAlive;
  // 启动期就可能自动退登（refreshProfile 在播放器创建前发出），
  // 这里保持可空，避免闭包读到尚未赋值的 late final。
  PlayerProvider? player;
  late final AccountProvider account;
  account = AccountProvider(
    onSessionEstablished: () => keepAlive.restart(),
    onSessionLost: () {
      keepAlive.stop();
      // 播放器 profile 独立于登录页，退出时不清掉就会把旧账号的网页会话留在本机。
      unawaited(WebSessionSync.clearPlayerProfile());
    },
    // 咪咕明确回绝本机会话时没有恢复的余地，直接退干净，别把界面卡在“已失效”。
    onAutoSignOut: () async {
      await account.signOut();
      await player?.clearQueue();
    },
  );
  await account.initialize();

  final api = MiguMusicApi(
    onAuthVerified: account.markVerified,
    onAuthRejected: account.markRejected,
    onSessionRevoked: account.markSessionRevoked,
    sessionEpoch: () => account.credentialEpoch,
  );
  account.attachApi(api);

  // 保活只在前台跑：探到失效时账号层先用留存票据试一次续期，续不到才需要手动重登。
  keepAlive = SessionKeepAlive(
    probe: api.checkSessionAlive,
    onAlive: account.markVerified,
    onRevoked: account.markSessionRevoked,
    sessionEpoch: () => account.credentialEpoch,
  )..attach();
  if (account.hasLogin) keepAlive.restart();

  if (account.hasLogin) {
    unawaited(account.refreshProfile());
    unawaited(account.refreshLibrary());
  }
  final importedPlaylists = ImportedPlaylistProvider(ExternalPlaylistService(), api);
  await importedPlaylists.load();

  final createdPlayer = PlayerProvider(api, settings: settings);
  player = createdPlayer;
  await createdPlayer.initialize();

  final hotkeys = GlobalHotkeyService(createdPlayer, settings);
  await hotkeys.initialize();

  await _configureDesktopWindow(settings);

  runApp(
    MultiProvider(
      providers: [
        Provider<MiguMusicApi>.value(value: api),
        ChangeNotifierProvider<PlayerProvider>.value(value: createdPlayer),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AccountProvider>.value(value: account),
        ChangeNotifierProvider<AppShellController>(create: (_) => AppShellController()),
        ChangeNotifierProvider<DesktopLyricsProvider>(
          create: (context) => DesktopLyricsProvider(
            createdPlayer,
            settings,
            context.read<AppShellController>(),
          ),
        ),
        ChangeNotifierProvider<SearchProvider>(
          create: (_) => SearchProvider(api, settings),
        ),
        ChangeNotifierProvider<HomeProvider>(create: (_) => HomeProvider(api)),
        ChangeNotifierProvider<ImportedPlaylistProvider>.value(
          value: importedPlaylists,
        ),
        ChangeNotifierProvider<PlaylistProvider>(create: (_) => PlaylistProvider(api)),
        Provider<GlobalHotkeyService>.value(value: hotkeys),
      ],
      child: const MiguLeleApp(),
    ),
  );
}

Future<void> _configureDesktopWindow(SettingsProvider settings) async {
  if (!Platform.isWindows) return;
  final systemBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  final dark = switch (settings.themeMode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => systemBrightness == Brightness.dark,
  };
  try {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: const Size(1280, 840),
      minimumSize: const Size(920, 640),
      center: true,
      title: AppConstants.appName,
      backgroundColor: dark ? AppColors.darkBackground : AppColors.lightBackground,
      titleBarStyle: TitleBarStyle.hidden,
    );
    unawaited(
      windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      }),
    );
  } catch (error) {
    debugPrint('初始化桌面窗口失败：$error');
  }
}
