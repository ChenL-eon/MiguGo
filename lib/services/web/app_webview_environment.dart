import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 应用内 WebView2 环境：按用途隔离用户数据目录，同一用途重复打开时复用。
///
/// flutter_inappwebview 在 Windows 上创建默认环境时可能一直不返回，
/// 官方示例要求显式指定 userDataFolder。登录页进出时会清空自己的 Cookie，
/// 所以不能和内嵌官方播放器共用同一个 profile，否则播放会话会被连带抹掉。
class AppWebViewEnvironment {
  AppWebViewEnvironment._();

  static const String _loginProfile = 'webview2';
  static const String _playerProfile = 'webview2_player';

  /// 环境建立的等待上限。超时的只是本次调用，后台那次创建继续跑。
  static const Duration _createTimeout = Duration(seconds: 45);

  /// 清空 Cookie 的等待上限，避免登录页被同一个插件通道拖住。
  static const Duration _cookieClearTimeout = Duration(seconds: 10);

  static final Map<String, WebViewEnvironment> _environments = {};
  static final Map<String, Future<WebViewEnvironment?>?> _pending = {};

  /// 登录页环境；退出登录页时其中的 Cookie 会被清空。
  static WebViewEnvironment? get login => _environments[_loginProfile];

  static Future<WebViewEnvironment?> ensureLogin() => _ensure(_loginProfile);

  /// 登录会话可能落地的咪咕站点，与登录页的 Cookie 探测地址一致。
  static const List<String> _loginSites = [
    'https://music.migu.cn/v5/',
    'https://music.migu.cn',
    'https://passport.migu.cn',
    'https://www.migu.cn',
    'https://migu.cn',
  ];

  /// 清空登录页自己的 Cookie。Windows 上环境还没建立时没有可清理的东西。
  ///
  /// Windows 的登录页有独立 profile，整份清掉波及不到播放器；Android 只有一个
  /// WebView 用户数据目录，`deleteAllCookies()` 会把咪咕之外的域名一起抹掉，
  /// 所以非 Windows 按咪咕站点逐条删除，越界的域名一概不动。
  ///
  /// Android 上内嵌官方播放器与登录页共用这份存储，清掉 `music.migu.cn` 意味着
  /// 播放器页面要重新登录一次——原先整份清空时更甚，不是这次改出来的行为。
  static Future<void> clearLoginCookies() async {
    try {
      if (Platform.isWindows) {
        if (login == null) return;
        await CookieManager.instance(webViewEnvironment: login)
            .deleteAllCookies()
            .timeout(_cookieClearTimeout);
        return;
      }
      final manager = CookieManager.instance();
      for (final site in _loginSites) {
        final url = WebUri(site);
        for (final cookie in await manager.getCookies(url: url)) {
          await manager.deleteCookie(
            url: url,
            name: cookie.name,
            path: cookie.path ?? '/',
            domain: cookie.domain,
          );
        }
      }
    } catch (_) {
      // 清理失败不阻塞登录流程，页面退出时会再试一次。
    }
  }

  /// 内嵌官方播放器环境；咪咕页面自己写入的登录会话保存在这里，
  /// 打开前后由 WebSessionSync 与原生请求同步，保持同一个登录会话。
  static WebViewEnvironment? get player => _environments[_playerProfile];

  static Future<WebViewEnvironment?> ensurePlayer() => _ensure(_playerProfile);

  /// 确保环境已创建。失败时返回 null，由调用方提示用户。
  static Future<WebViewEnvironment?> _ensure(String profile) {
    if (!Platform.isWindows) return Future<WebViewEnvironment?>.value();
    final created = _environments[profile];
    if (created != null) return Future<WebViewEnvironment?>.value(created);
    final pending = _pending[profile] ??= _create(profile)
        .whenComplete(() => _pending.remove(profile));
    // create() 可能永远不返回，挂死的 future 会把登录页永久卡在「正在准备登录页面」。
    // 超时只让本次调用拿到 null 去提示用户，创建留在后台：真建成了会进 _environments。
    return pending.timeout(_createTimeout, onTimeout: () => null);
  }

  static Future<WebViewEnvironment?> _create(String profile) async {
    try {
      final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      final folder =
          '$base${Platform.pathSeparator}migu_lele'
          '${Platform.pathSeparator}$profile';
      await Directory(folder).create(recursive: true);
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: folder),
      );
      _environments[profile] = environment;
      return environment;
    } catch (_) {
      return null;
    }
  }
}
