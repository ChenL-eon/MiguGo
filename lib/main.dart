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
import 'providers/update_provider.dart';
import 'services/api/migu_cookie_store.dart';
import 'services/api/migu_music_api.dart';
import 'services/app_update_service.dart';
import 'services/auth/session_keep_alive.dart';
import 'services/auth/session_probe.dart';
import 'services/auth/session_probe_diagnostics.dart';
import 'services/auth/session_reject_ledger.dart';
import 'services/auth/web_session_sync.dart';
import 'services/external/external_playlist_service.dart';
import 'services/platform/desktop_tray.dart';
import 'services/platform/global_hotkeys.dart';
import 'services/platform/legacy_data_migration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await migrateLegacyWindowsData();
  await MiguCookieStore.instance.init();
  await SessionRejectLedger.instance.init();

  final settings = SettingsProvider();
  await settings.load();

  final updates = UpdateProvider(AppUpdateService());
  await updates.load();

  late final SessionKeepAlive keepAlive;
  // 启动期就可能自动退登（refreshProfile 在播放器创建前发出），
  // 这里保持可空，避免闭包读到尚未赋值的 late final。
  PlayerProvider? player;
  late final AccountProvider account;
  account = AccountProvider(
    diagnostics: SessionProbeDiagnostics.instance,
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
    diagnostics: SessionProbeDiagnostics.instance,
    onAuthVerified: account.markVerified,
    onAuthRejected: account.markRejected,
    onSessionRevoked: account.markSessionRevoked,
    sessionEpoch: () => account.credentialEpoch,
  );
  account.attachApi(api);

  // 保活默认只在前台跑：探到失效就交给账号层做两步判定，判死就要用户手动重登。
  // 下面挂了常驻托盘时允许后台继续，其余不变。
  keepAlive = SessionKeepAlive(
    probe: () => api.checkSessionAlive(trigger: 'keep-alive'),
    onAlive: account.markVerified,
    onRevoked: account.markSessionRevoked,
    sessionEpoch: () => account.credentialEpoch,
  )..attach();
  if (account.hasLogin) {
    keepAlive.restart();
    // 先让官方校验接口过一遍：成功就顺带轮换 pacmtoken 并清零旧证据，
    // 失败再照常拉资料，由拦截器按真正的拒绝取证。
    unawaited(_warmUpSession(account, api));
  }
  final importedPlaylists = ImportedPlaylistProvider(
    ExternalPlaylistService(),
    api,
  );
  await importedPlaylists.load();

  final createdPlayer = PlayerProvider(api, settings: settings);
  player = createdPlayer;
  await createdPlayer.initialize();

  final hotkeys = GlobalHotkeyService(createdPlayer, settings);
  await hotkeys.initialize();

  await _configureDesktopWindow(settings);

  // 咪咕给每个 pacmtoken 只有签发后两小时命，应用一退就没人再去问服务端。
  // 开了常驻托盘就把关闭变成隐藏，让同一件保活探测在窗口看不见的时候继续做。
  final tray = DesktopTrayService(
    onKeepAliveInBackground: (enabled) => keepAlive.allowsBackground = enabled,
    onWindowHidden: () => unawaited(createdPlayer.pause()),
  );
  await tray.setEnabled(settings.backgroundKeepAliveEnabled);
  settings.addListener(
    () => unawaited(tray.setEnabled(settings.backgroundKeepAliveEnabled)),
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<MiguMusicApi>.value(value: api),
        ChangeNotifierProvider<PlayerProvider>.value(value: createdPlayer),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<UpdateProvider>.value(value: updates),
        ChangeNotifierProvider<AccountProvider>.value(value: account),
        ChangeNotifierProvider<AppShellController>(
          create: (_) => AppShellController(),
        ),
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
        ChangeNotifierProvider<PlaylistProvider>(
          create: (_) => PlaylistProvider(api),
        ),
        Provider<GlobalHotkeyService>.value(value: hotkeys),
      ],
      child: const MiguLeleApp(),
    ),
  );

  // 启动检查不挡首帧；关了开关或刚查过，服务里会自己跳过。
  unawaited(updates.checkOnStartup());
}

Future<void> _warmUpSession(AccountProvider account, MiguMusicApi api) async {
  final epoch = account.credentialEpoch;
  var probe = SessionProbe.unknown;
  try {
    probe = await api
        .checkSessionAlive(trigger: 'startup')
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => SessionProbe.unknown,
        );
  } catch (_) {
    probe = SessionProbe.unknown;
  }
  if (!account.hasLogin || account.credentialEpoch != epoch) return;
  if (probe == SessionProbe.revoked) {
    // 校验接口只拿 pacmtoken 说话，它说失效就不必等下一次保活（45–75 分钟）：
    // 直接交给账号层做两步判定。资料与歌单由这条路径自己刷，
    // 这里再并发拉一次只会用旧凭据盖掉判定结果。
    account.markSessionRevoked();
    return;
  }
  if (probe == SessionProbe.alive) account.markVerified();
  // 校验失败也照常拉资料：真正的拒绝由拦截器取证，网络失败不会记成证据。
  unawaited(account.refreshProfile());
  unawaited(account.refreshLibrary());
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
      backgroundColor: dark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
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
