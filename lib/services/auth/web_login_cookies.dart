import 'dart:math' as math;

/// 从 WebView 读取到的单条 Cookie。
class WebLoginCookie {
  const WebLoginCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
  });

  final String name;
  final String value;
  final String domain;
  final String path;

  String get storageKey => '${domain.toLowerCase()}|$path|$name';
}

/// 网页登录 Cookie 的清洗与导出。
///
/// WebView 会返回多个域下的 Cookie，而且同名 Cookie 可能出现在不同路径。
/// 这里按域和路径的具体程度去重，再交给现有 Cookie 仓库统一保存。
class WebLoginCookieSet {
  WebLoginCookieSet._(this.cookies, this.scopedCookies);

  factory WebLoginCookieSet.fromCookies(Iterable<WebLoginCookie> cookies) {
    final valid = <WebLoginCookie>[];
    for (final cookie in cookies) {
      if (!_cookieName.hasMatch(cookie.name)) continue;
      if (!_isMiguDomain(cookie.domain)) continue;
      if (cookie.value.contains(';') ||
          cookie.value.contains('\n') ||
          cookie.value.contains('\r')) {
        continue;
      }
      valid.add(cookie);
    }

    valid.sort((a, b) {
      final domainCompare = b.domain.length.compareTo(a.domain.length);
      if (domainCompare != 0) return domainCompare;
      final pathCompare = b.path.length.compareTo(a.path.length);
      if (pathCompare != 0) return pathCompare;
      return a.name.compareTo(b.name);
    });

    final unique = <String, WebLoginCookie>{};
    for (final cookie in valid) {
      unique.putIfAbsent(cookie.name, () => cookie);
    }

    final normalized = unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return WebLoginCookieSet._(normalized, List.unmodifiable(valid));
  }

  static final RegExp _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  static const List<String> authNameHints = [
    'token',
    'auth',
    'session',
    'login',
    'passid',
    'ticket',
    'sso',
    'msisdn',
    'userid',
    'member',
    'nickname',
    'avatar',
  ];

  static bool looksLikeAuthCookieName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower == 'uid' || lower == 'user' || lower == 'phone') return true;
    return authNameHints.any(lower.contains);
  }

  final List<WebLoginCookie> cookies;

  /// 清洗后、按名称去重前的完整列表，用于按域判断 Cookie 的作用范围。
  final List<WebLoginCookie> scopedCookies;

  bool get isEmpty => cookies.isEmpty;

  int get length => cookies.length;

  bool get hasAuthHint => cookies.any(
    (cookie) =>
        !_isAnonymousCookieName(cookie.name) && looksLikeAuthCookieName(cookie.name),
  );

  /// 生成可交给 MiguCookieStore 的请求头；没有登录凭据时返回 null。
  ///
  /// 界面上的「已读到 N 项 Cookie」统计的是清洗后的全量，落盘的只允许凭据：
  /// 网页在同域下写的设备号、埋点会话与统计 Cookie 一概不带出 WebView，
  /// 与「其余 Cookie 一概不取」的声明保持一致。
  String? get header {
    final credentials = cookies
        .where((cookie) => isLoginCredentialCookieName(cookie.name))
        .toList(growable: false);
    if (credentials.isEmpty) return null;
    return credentials.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  /// 咪咕音乐网页登录成功后才会出现的登录凭据名称。
  ///
  /// 官方网页在回跳后用地址里的 token 换取会话，再把这些名称写到
  /// `migu.cn` 域下；匿名访问与统计脚本不会写入它们。
  /// `pacmtoken` 就是原生播放器取 VIP 播放地址所用的凭据。
  static const List<String> webSessionCookieNames = [
    'mg_auth_sid',
    'migu-utoken-sessionid',
    'pacmtoken',
    'mg_auth_pacmtoken',
  ];

  /// 官方登录流程写入的 Cookie 名称前缀。
  ///
  /// 换取会话时 `mg_auth_pid`、`mg_auth_uid` 等名称可能先到、会话名后到，
  /// 因此只用它判断“登录已开始”，不作为导入并清空会话的依据。
  static const String officialCookieNamePrefix = 'mg_auth_';

  /// 匿名访问咪咕网页时也会写入的统计与设备 Cookie，不能当作登录凭证。
  static const List<String> anonymousCookieNames = [
    'cookieid',
    'migu-device-uuid',
    'task-session-id',
  ];

  static const String _anonymousUserCookiePrefix = 'mg_uem_user_id_';

  /// 名称是否为官方网页登录会话 Cookie；Cookie 仓库也用它判断本地凭证完整性。
  static bool isWebSessionCookieName(String name) =>
      webSessionCookieNames.contains(name.trim().toLowerCase());

  /// 名称是否属于要落盘并发送的登录凭据。
  ///
  /// 判据只有三类：官方网页会话名、官方登录流程写的 `mg_auth_*`，以及
  /// 播放接口按同名请求头读取的 `uid`/`msisdn`。`sso_token`、`passID`
  /// 这类「名字像凭证」的统计 Cookie 不在其中——它们既不能用来取链，
  /// 落盘只会无谓扩大本机保存的会话面。
  static bool isLoginCredentialCookieName(String name) {
    final lower = name.trim().toLowerCase();
    return isWebSessionCookieName(lower) ||
        lower.startsWith(officialCookieNamePrefix) ||
        lower == 'uid' ||
        lower == 'msisdn';
  }

  static bool _isOfficialCookieName(String name) {
    final lower = name.trim().toLowerCase();
    return isWebSessionCookieName(lower) || lower.startsWith(officialCookieNamePrefix);
  }

  static bool _isAnonymousCookieName(String name) {
    final lower = name.trim().toLowerCase();
    return anonymousCookieNames.contains(lower) ||
        lower.startsWith(_anonymousUserCookiePrefix);
  }

  /// 判断是否存在对 [host] 生效的咪咕音乐登录会话 Cookie。
  ///
  /// 只看去重后的集合会漏判：同名 Cookie 可能同时存在于通行证域和
  /// `migu.cn`，因此这里遍历清洗后、去重前的完整列表。
  bool hasWebSessionFor(String host) => _hasCookieFor(host, isWebSessionCookieName);

  /// 判断是否存在官方登录流程写入、且对 [host] 生效的 Cookie。
  ///
  /// 手动读取时的兜底判据：只认可登录凭据名称或 `mg_auth_*`，
  /// 统计与设备 Cookie 不算。
  bool hasOfficialCookieFor(String host) => _hasCookieFor(host, _isOfficialCookieName);

  bool _hasCookieFor(String host, bool Function(String name) matches) {
    final target = host.trim().toLowerCase();
    if (target.isEmpty) return false;
    for (final cookie in scopedCookies) {
      if (cookie.value.isEmpty) continue;
      if (_isAnonymousCookieName(cookie.name)) continue;
      if (!matches(cookie.name)) continue;
      if (_appliesToHost(cookie.domain, target)) return true;
    }
    return false;
  }

  /// 仅用于界面诊断的 Cookie 名称；只含名称，不含任何 Cookie 值。
  List<String> get cookieNames =>
      cookies.map((cookie) => cookie.name).toList(growable: false);

  /// 已看到的官方登录 Cookie 名称，用于说明网页正在写入哪一步。
  List<String> get officialCookieNames =>
      cookieNames.where((name) => _isOfficialCookieName(name)).toList(growable: false);

  static bool _appliesToHost(String cookieDomain, String host) {
    final domain = cookieDomain.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (domain.isEmpty) return false;
    return host == domain || host.endsWith('.$domain');
  }

  static bool _isMiguDomain(String domain) {
    final normalized = domain.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    return normalized == 'migu.cn' || normalized.endsWith('.migu.cn');
  }

  /// 仅用于日志或界面展示的数量描述，不暴露具体值。
  String get summary => '${math.min(cookies.length, 999)} 项';
}
