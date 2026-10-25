import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../api/migu_cookie_store.dart';
import '../web/app_webview_environment.dart';
import 'web_login_cookies.dart';

/// 播放器 profile 里的一枚 Cookie。
@immutable
class PlayerCookie {
  const PlayerCookie({required this.name, required this.value, this.domain});

  final String name;
  final String value;
  final String? domain;
}

/// 播放器 profile 的 Cookie 访问入口；测试可注入内存实现。
///
/// Windows 端的 `CookieManager` 没有实现 `getAllCookies`，只能按 URL 查询，
/// 所以这里刻意只暴露按地址读取，不假设能枚举整个 profile。
abstract interface class PlayerProfileCookies {
  Future<List<PlayerCookie>> read(Uri url);

  Future<bool> write(
    Uri url, {
    required String name,
    required String value,
    required String path,
  });

  Future<bool> deleteAll();
}

/// 内嵌官方播放器与原生请求之间的登录会话同步。
///
/// 官方网页每次打开都会续签 `mg_auth_sid`、`pacmtoken` 这类会话 Cookie，
/// 但续签结果只留在 WebView2 自己的 profile 里，原生请求拿不到，本机快照
/// 于是只能等服务端把它判死。页面开始加载时把凭据写进 profile、加载完再
/// 读回来，两边共用同一个会话，快照也跟着网页一起续期。
///
/// 播放器 profile 和登录页 profile 是两份独立的用户数据目录，退出登录
/// 清空登录页不会连带清空它。这里用登录会话的代际标记判断 profile 属于
/// 哪一次登录：代际不符就先整份清掉，回收结果也必须由 Cookie 仓库复核
/// 代际后才允许写回，避免旧账号在退出或换号后复活。
///
/// 只处理用户自己账号在本机 profile 中的会话，不访问任何额外接口。
class WebSessionSync {
  WebSessionSync._();

  static const String _cookieDomain = '.migu.cn';
  static const String _syncCookieName = 'migugo_web_sync';
  static const String _syncCookiePath = '/__migugo_web_sync';
  static final Uri _syncUri = Uri.parse('https://music.migu.cn$_syncCookiePath');
  static final List<Uri> _probeUris = [
    Uri.parse('https://music.migu.cn/v5/'),
    Uri.parse('https://music.migu.cn'),
    Uri.parse('https://passport.migu.cn'),
  ];

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// WebView2 的 Cookie 调用在环境刚创建时可能迟迟不返回，会话同步只是加分项，
  /// 不能让官方页面等它，所以两边都设一个短超时。
  static const Duration _timeout = Duration(seconds: 6);

  /// 让官方页面沿用本机已导入的登录会话，避免同一账号开出两份互相顶替的会话。
  ///
  /// 只写官方登录会话那几个名称：手动快照里还有统计和设备 Cookie，把它们统一
  /// 改挂到 `.migu.cn` 会和页面自己种的同名条目撞车，实测会让官方页面白屏。
  ///
  /// 已退出时清空整个播放器 profile：旧账号的网页会话不能继续留在本机，
  /// 否则重新打开播放器仍会带着它访问咪咕页面。
  static Future<void> seedPlayer(
    MiguCookieStore store, {
    PlayerProfileCookies? profile,
  }) async {
    final cookies = _profile(profile);
    if (cookies == null) return;

    final token = store.webSyncToken;
    if (token == null || !store.hasImportedLogin) {
      await _clearProfile(cookies);
      return;
    }

    final snapshot = Map<String, String>.fromEntries(
      store.loginSnapshot.entries.where((entry) => isSessionCookieName(entry.key)),
    );
    if (snapshot.isEmpty) return;

    try {
      final sentinel = await _readSentinel(cookies);
      if (sentinel != token) {
        // 旧账号或旧版本留下的 profile：先整份清掉再写入，不能把两个账号的
        // Cookie 混在同一次页面加载里。删除失败时宁可不播种（fail closed），
        // 否则页面可能带着上一份会话继续使用。
        final hasSessionCookies = (await _collectSessionCookies(cookies)).isNotEmpty;
        if (sentinel != null || hasSessionCookies) {
          if (!await cookies.deleteAll()) {
            debugPrint('清理官方播放器旧登录会话失败，本次不写入新的登录会话。');
            return;
          }
        }
        if (!await cookies.write(
          _syncUri,
          name: _syncCookieName,
          value: token,
          path: _syncCookiePath,
        )) {
          // 标记写不进去只影响回收，不应连带让页面的登录会话播种失败。
          debugPrint('写入官方播放器会话代际标记失败，本次回收结果将被忽略。');
        }
      }
      await Future.wait(
        snapshot.entries.map(
          (entry) => cookies.write(
            _probeUris.first,
            name: entry.key,
            value: entry.value,
            path: '/',
          ),
        ),
      );
    } catch (error) {
      debugPrint('写入官方播放器登录会话失败，页面仍可自行完成登录：$error');
    }
  }

  /// 把页面续签后的登录 Cookie 读回本机快照，返回实际更新的条数。
  ///
  /// 只认官方登录流程写入的名称：匿名访问不会种下 `mg_auth_*`，所以一旦这一轮
  /// 什么也没读到就直接跳过，避免把统计 Cookie 或页面自己的匿名会话当成凭据覆盖
  /// 掉本机可用的登录态。
  ///
  /// profile 里的代际标记必须和当前登录一致；即使读取期间刚好退出或换号，
  /// Cookie 仓库还会在写入前复核一次代际，旧会话无法穿过这两道检查。
  static Future<int> harvestPlayer(
    MiguCookieStore store, {
    PlayerProfileCookies? profile,
  }) async {
    final cookies = _profile(profile);
    if (cookies == null) return 0;

    final token = store.webSyncToken;
    if (token == null || !store.hasImportedLogin) return 0;

    try {
      final sentinel = await _readSentinel(cookies);
      if (sentinel != token) return 0;
      final collected = await _collectSessionCookies(cookies);
      if (collected.isEmpty) return 0;
      return await store.refreshLoginCookies(collected, webSyncToken: token);
    } catch (error) {
      debugPrint('读取官方播放器登录会话失败，本次跳过同步：$error');
      return 0;
    }
  }

  /// 退出登录或会话被回绝时清空播放器 profile。
  ///
  /// 与登录页 profile 无关；调用方不应假设清空登录页会连带清掉这里。
  static Future<void> clearPlayerProfile({PlayerProfileCookies? profile}) async {
    final cookies = _profile(profile);
    if (cookies == null) return;
    await _clearProfile(cookies);
  }

  /// 是否为官方登录流程写入的会话名称；统计与设备 Cookie 不算。
  static bool isSessionCookieName(String name) {
    final lower = name.trim().toLowerCase();
    return WebLoginCookieSet.isWebSessionCookieName(lower) ||
        lower.startsWith(WebLoginCookieSet.officialCookieNamePrefix);
  }

  static PlayerProfileCookies? _profile(PlayerProfileCookies? injected) {
    if (injected != null) return injected;
    if (!supported) return null;
    // 播放器 profile 只在真正打开官方页面时才创建，这里不额外拉起环境。
    final environment = AppWebViewEnvironment.player;
    if (environment == null) return null;
    return _WebViewPlayerProfile(
      CookieManager.instance(webViewEnvironment: environment),
    );
  }

  static Future<void> _clearProfile(PlayerProfileCookies cookies) async {
    try {
      if (!await cookies.deleteAll()) {
        debugPrint('清理官方播放器旧登录会话失败，旧账号的网页会话可能仍留在本机。');
      }
    } catch (error) {
      debugPrint('清理官方播放器旧登录会话失败：$error');
    }
  }

  static Future<String?> _readSentinel(PlayerProfileCookies cookies) async {
    final found = await cookies.read(_syncUri);
    for (final cookie in found) {
      if (cookie.name == _syncCookieName) return cookie.value;
    }
    return null;
  }

  static Future<Map<String, String>> _collectSessionCookies(
    PlayerProfileCookies cookies,
  ) async {
    final collected = <String, String>{};
    for (final url in _probeUris) {
      final found = await cookies.read(url);
      for (final cookie in found) {
        final name = cookie.name;
        final value = cookie.value;
        final domain = cookie.domain;
        if (!isSessionCookieName(name)) continue;
        if (value.isEmpty) continue;
        // 域名必须真是咪咕的：`evil-migu.cn` 这种相邻后缀不能回收进本机凭据。
        if (domain == null || !isMiguHost(domain)) continue;
        collected.putIfAbsent(name, () => value);
      }
    }
    return collected;
  }
}

class _WebViewPlayerProfile implements PlayerProfileCookies {
  _WebViewPlayerProfile(this._manager);

  final CookieManager _manager;

  @override
  Future<List<PlayerCookie>> read(Uri url) async {
    final cookies = await _manager
        .getCookies(url: WebUri(url.toString()))
        .timeout(WebSessionSync._timeout);
    return [
      for (final cookie in cookies)
        PlayerCookie(
          name: cookie.name,
          value: cookie.value ?? '',
          domain: cookie.domain,
        ),
    ];
  }

  @override
  Future<bool> write(
    Uri url, {
    required String name,
    required String value,
    required String path,
  }) {
    return _manager
        .setCookie(
          url: WebUri(url.toString()),
          name: name,
          value: value,
          domain: WebSessionSync._cookieDomain,
          path: path,
          isSecure: true,
        )
        .timeout(WebSessionSync._timeout);
  }

  @override
  Future<bool> deleteAll() {
    return _manager.deleteAllCookies().timeout(WebSessionSync._timeout);
  }
}
