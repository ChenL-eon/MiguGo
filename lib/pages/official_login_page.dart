import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_shell_controller.dart';
import '../core/theme/app_colors.dart';
import '../providers/account_provider.dart';
import '../services/api/migu_cookie_store.dart';
import '../services/api/secure_cookie_storage.dart';
import '../services/auth/migu_passport_url.dart';
import '../services/auth/web_login_cookies.dart';
import '../services/web/app_webview_environment.dart';
import '../widgets/ambient_background.dart';
import '../widgets/login_feedback.dart';

const String _webView2Unavailable =
    '无法初始化 Windows WebView2 环境——可能未安装 Microsoft Edge WebView2 Runtime，'
    '或初始化在 45 秒内没有返回。请点击“重新加载”重试；反复如此请彻底退出本应用后重新打开。';

const List<String> _cookieProbeUrls = [
  'https://music.migu.cn/v5/',
  'https://music.migu.cn',
  'https://passport.migu.cn',
  'https://www.migu.cn',
  'https://migu.cn',
];

const Set<String> _blockedSchemes = {
  'weixin',
  'wechat',
  'alipay',
  'alipays',
  'mqq',
  'qq',
  'tel',
  'sms',
  'mailto',
  'intent',
};

/// 登录窗口能停留在哪些地址：咪咕官方域的 https 页面，其余一律拦下。
///
/// 光看 scheme 不够。通行证页面里的运营位、活动页与「其他方式登录」会把地址
/// 带到第三方域名——那份地址拿不走本机凭据，却会在本窗口里渲染一个不是咪咕的
/// 登录界面，用户在这里输入的账号密码就交给了别人。
///
/// 地址为空和 `about:*` 是 WebView 自身的导航占位，不算离开官方页面。
bool isAllowedLoginNavigation(Uri? uri) {
  if (uri == null) return true;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'about') return true;
  if (scheme != 'https') return false;
  return isMiguHost(uri.host);
}

/// 官方账号登录窗口：整个应用里唯一会出现 WebView 的地方。
///
/// 从登录页按需打开，只加载咪咕官方通行证页面；读到音乐域登录凭据后立即
/// 清空网页会话并关闭本页。登录页与其余界面都是原生 Flutter。
class OfficialLoginPage extends StatefulWidget {
  const OfficialLoginPage({super.key});

  @override
  State<OfficialLoginPage> createState() => _OfficialLoginPageState();
}

class _OfficialLoginPageState extends State<OfficialLoginPage> {
  static const Duration _loginTimeout = Duration(minutes: 5);

  /// 登录会话 Cookie 需要生效的站点；接口请求都以该站点的会话鉴权。
  static const String _musicHost = 'music.migu.cn';

  /// 回跳后的本地检查次数，约 16 秒。整页 WebView 不一定能立刻拿到音乐站点的
  /// 全部登录凭据，所以只做短暂等待，用户也可以随时手动读取。
  static const int _autoImportAttempts = 18;

  /// 第几次检查后改为显示“已读到的 Cookie 名称”。
  static const int _announceDetailAttempt = 6;

  /// Cookie 探测覆盖的访问域数量上限。
  static const int _maxVisitedHosts = 12;

  AppShellController? _shellController;
  InAppWebViewController? _webController;
  Timer? _timeoutTimer;
  final Set<String> _visitedHosts = {};

  bool _webViewCreated = false;
  bool _loadingPage = true;
  bool _extracting = false;
  bool _closing = false;
  bool _timedOut = false;
  bool _autoCheckScheduled = false;
  bool _loginGuardEntered = false;
  bool _loginGuardScheduled = false;

  String? _error;
  String? _notice;
  String? _currentHost;
  int _progress = 0;
  int _webViewGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareWebView());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = context.read<AppShellController>();
    _shellController = shell;
    if (_loginGuardScheduled) return;
    _loginGuardScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loginGuardEntered = true;
      shell.enterWebLogin();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    unawaited(AppWebViewEnvironment.clearLoginCookies());
    final shell = _shellController;
    if (_loginGuardEntered) {
      _loginGuardEntered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        shell?.leaveWebLogin();
      });
    }
    super.dispose();
  }

  Future<void> _prepareWebView() async {
    if (Platform.isWindows && await AppWebViewEnvironment.ensureLogin() == null) {
      if (!mounted) return;
      setState(() {
        _loadingPage = false;
        _error = _webView2Unavailable;
      });
      return;
    }
    await AppWebViewEnvironment.clearLoginCookies();
    if (!mounted) return;
    setState(() => _webViewCreated = true);
    _armTimeout();
  }

  Future<WebLoginCookieSet> _collectCookies() async {
    final generation = _webViewGeneration;
    final manager = CookieManager.instance(
      webViewEnvironment: AppWebViewEnvironment.login,
    );
    final collected = <WebLoginCookie>[];
    for (final url in await _cookieProbeTargets(generation)) {
      final cookies = await manager.getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        final domain = cookie.domain;
        if (domain == null || domain.isEmpty) continue;
        collected.add(
          WebLoginCookie(
            name: cookie.name,
            value: cookie.value,
            domain: domain,
            path: cookie.path ?? '/',
          ),
        );
      }
    }
    collected.addAll(await _readDocumentCookies(generation));
    return WebLoginCookieSet.fromCookies(collected);
  }

  /// 除固定探测地址外，还要探测 WebView 真正访问过的咪咕域名：
  /// 页面脚本写入的会话 Cookie 可能是 host-only 的，只按写入它的那个域名返回。
  Future<List<String>> _cookieProbeTargets(int generation) async {
    final targets = <String>{};
    if (generation == _webViewGeneration) {
      final current = await _webController?.getUrl();
      final raw = current?.toString();
      if (raw != null && (raw.startsWith('http://') || raw.startsWith('https://'))) {
        targets.add(raw.split('#').first);
      }
    }
    for (final host in _visitedHosts) {
      targets.add('https://$host/');
    }
    targets.addAll(_cookieProbeUrls);
    return targets.toList(growable: false);
  }

  /// 记录本次登录过程中经过的咪咕域名，只用于确定 Cookie 探测范围。
  void _noteVisitedUrl(WebUri? url) {
    final host = url?.host.toLowerCase();
    if (host == null || host.isEmpty) return;
    if (host != 'migu.cn' && !host.endsWith('.migu.cn')) return;
    if (_visitedHosts.length >= _maxVisitedHosts && !_visitedHosts.contains(host)) {
      return;
    }
    _visitedHosts.add(host);
  }

  /// 补充来源：直接读页面自己的 `document.cookie`。
  ///
  /// WebView2 的 CookieManager 在部分时机不会返回当前页刚写入的 Cookie，
  /// 而官方网页的登录会话正是由页面脚本写入的，因此这里做本地兜底。
  /// 只读取名称与值，不发起任何额外网络请求。
  Future<List<WebLoginCookie>> _readDocumentCookies(int generation) async {
    final controller = generation == _webViewGeneration ? _webController : null;
    if (controller == null) return const [];
    try {
      final raw = await controller.evaluateJavascript(source: 'document.cookie');
      if (raw is! String || raw.trim().isEmpty) return const [];
      final host = (await controller.getUrl())?.host.toLowerCase() ?? _musicHost;
      final cookies = <WebLoginCookie>[];
      for (final part in raw.split(';')) {
        final pair = part.trim();
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        cookies.add(
          WebLoginCookie(
            name: pair.substring(0, separator).trim(),
            value: pair.substring(separator + 1).trim(),
            domain: host,
            path: '/',
          ),
        );
      }
      return cookies;
    } catch (_) {
      // 读取失败时仍可使用 CookieManager 的结果。
      return const [];
    }
  }

  void _armTimeout() {
    _timeoutTimer ??= Timer(_loginTimeout, () {
      if (!mounted || _closing) return;
      setState(() {
        _timedOut = true;
        _notice = null;
        _error = '登录等待超时（5 分钟）。请点击“重新加载”后重试。';
      });
    });
  }

  void _handleLoadStart(WebUri? url) {
    if (!mounted) return;
    _armTimeout();
    _noteVisitedUrl(url);
    setState(() {
      _loadingPage = true;
      _progress = 0;
      if (url?.host != null) _currentHost = url!.host;
      if (_error != null && !_timedOut) _error = null;
    });
  }

  Future<void> _handleLoadStop(WebUri? url) async {
    if (!mounted) return;
    _noteVisitedUrl(url);
    setState(() {
      _loadingPage = false;
      _progress = 100;
      if (url?.host != null) _currentHost = url!.host;
    });
    if (_isMusicUrl(url)) _scheduleAutoImport();
  }

  void _handleVisitedHistory(WebUri? url) {
    if (!mounted) return;
    _noteVisitedUrl(url);
    final host = url?.host;
    if (host != null && host != _currentHost) {
      setState(() => _currentHost = host);
    }
    if (_isMusicUrl(url)) _scheduleAutoImport();
  }

  void _scheduleAutoImport() {
    if (_closing || _extracting || _timedOut || _autoCheckScheduled) return;
    _autoCheckScheduled = true;
    unawaited(_autoImportWithRetry());
  }

  /// 回跳后网页还要用地址里的 token 换取会话 Cookie，因此多次做本地检查。
  /// 这里只读取 WebView 的 Cookie，不请求任何额外的登录接口。
  Future<void> _autoImportWithRetry() async {
    final generation = _webViewGeneration;
    WebLoginCookieSet? last;
    var announcedWaiting = false;
    var announcedDetail = false;
    try {
      for (var attempt = 0; attempt < _autoImportAttempts; attempt++) {
        await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 700 : 900));
        if (!mounted ||
            _closing ||
            _extracting ||
            _timedOut ||
            generation != _webViewGeneration) {
          return;
        }
        final cookies = await _collectCookies();
        last = cookies;
        if (!mounted || _closing || _extracting || generation != _webViewGeneration) {
          return;
        }
        if (cookies.hasWebSessionFor(_musicHost)) {
          await _finishLogin(cookies);
          return;
        }
        if (!announcedWaiting && attempt >= 2 && _notice == null) {
          announcedWaiting = true;
          setState(() {
            _notice = '已返回咪咕音乐，正在等待网页写入登录会话…';
          });
        }
        // 短暂等待后先把已读到的 Cookie 显示出来，后台仍继续检测。
        if (!announcedDetail && attempt >= _announceDetailAttempt - 1) {
          announcedDetail = true;
          final detail = _waitingSessionText(cookies);
          setState(() => _notice = detail);
        }
      }
      if (!mounted || _closing || _extracting || _timedOut) return;
      setState(() {
        _notice = _missingSessionText(last ?? WebLoginCookieSet.fromCookies(const []));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cookie 提取失败，请点击“我已登录，读取凭证”重试。';
      });
    } finally {
      _autoCheckScheduled = false;
    }
  }

  /// 等待中的说明：显示已经读到的官方 Cookie，后台仍继续检测。
  String _waitingSessionText(WebLoginCookieSet cookies) {
    final official = cookies.officialCookieNames;
    if (official.isEmpty) {
      return '已读取 ${cookies.length} 项 Cookie，其中没有官方登录 Cookie（mg_auth_*）。'
          '请确认页面已显示自己的账号信息，后台仍在继续检测；'
          '也可以直接点“我已登录，读取凭证”。';
    }
    return '已读到官方登录 Cookie：${official.join('、')}，'
        '正在等待咪咕音乐写入登录凭据（pacmtoken / mg_auth_sid）…';
  }

  /// 没识别到官方登录会话时的说明；只列名称，不显示任何 Cookie 值。
  String _missingSessionText(WebLoginCookieSet cookies) {
    if (cookies.isEmpty) {
      return '没有读取到任何 migu.cn 的 Cookie。'
          '请等待页面完全加载后点“我已登录，读取凭证”重试。';
    }
    final names = cookies.cookieNames.take(18).join('、');
    final suffix = cookies.cookieNames.length > 18 ? '…' : '';
    return '已读取 ${cookies.length} 项 Cookie：$names$suffix。'
        '其中还没有 pacmtoken / mg_auth_sid 这类登录凭据，'
        '可能是登录尚未完成，或咪咕这次没有写入音乐站点凭据。'
        '这里不会导入这些非凭据 Cookie；'
        '可以在登录完成后点“我已登录，读取凭证”再试一次。';
  }

  Future<void> _readCredentialsManually() async {
    if (_extracting || _closing) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    setState(() {
      _extracting = true;
      _timedOut = false;
      _error = null;
      _notice = null;
    });

    try {
      final cookies = await _collectCookies();
      if (!mounted) return;
      if (cookies.isEmpty) {
        setState(() {
          _extracting = false;
          _error =
              'Cookie 提取失败：未读取到任何 migu.cn 的 Cookie。'
              '请确认已在该页面完成登录。';
        });
        return;
      }
      final hasWebSession = cookies.hasWebSessionFor(_musicHost);
      if (!hasWebSession && !cookies.hasOfficialCookieFor(_musicHost)) {
        // 只拿到通行证或统计类 Cookie 时不导入，也不清空 WebView 会话，
        // 否则会把网页稍后才写入的登录会话一起丢掉。
        setState(() {
          _extracting = false;
          _error = _missingSessionText(cookies);
        });
        return;
      }
      await _finishLogin(cookies, keepWebViewSession: !hasWebSession);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = 'Cookie 提取失败，请重试。';
      });
    }
  }

  /// [keepWebViewSession] 为 true 时保留 WebView 会话：此时导入的只是
  /// 名称像登录凭证的 Cookie，用户等页面加载完还能再读一次官方会话。
  Future<void> _finishLogin(
    WebLoginCookieSet cookies, {
    bool keepWebViewSession = false,
  }) async {
    if (_closing) return;
    final header = cookies.header;
    if (header == null) {
      setState(() {
        _extracting = false;
        _error = 'Cookie 提取失败：没有可导入的 Cookie。';
      });
      return;
    }

    setState(() {
      _extracting = true;
      _error = null;
      _notice = null;
    });

    final account = context.read<AccountProvider>();
    final hasAuthHint = cookies.hasAuthHint;
    int count;
    try {
      count = await account.importLoginCookie(header);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = 'Cookie 提取失败：${error.message}';
      });
      return;
    } on SecureCookieStorageException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = 'Cookie 提取失败，请重新登录。';
      });
      return;
    }

    if (!mounted) return;
    if (keepWebViewSession) {
      setState(() {
        _extracting = false;
        _error = null;
        _notice =
            '已导入当前可见的 $count 项官方 Cookie，但还没读到登录凭据'
            '（pacmtoken / mg_auth_sid）。可以等页面加载完再读一次。';
      });
      return;
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await AppWebViewEnvironment.clearLoginCookies();
    if (!mounted) return;

    setState(() {
      _extracting = false;
      _closing = true;
      _webViewCreated = false;
      _notice = '已读取并保存 $count 项登录 Cookie，正在返回首页…';
    });

    final warning = account.storageWarning;
    if (warning != null) {
      await showLoginStorageWarning(context, warning);
      if (!mounted) return;
    }

    showLoginSnack(
      context,
      hasAuthHint
          ? '登录成功：已保存 $count 项 Cookie，正在返回首页。'
          : '已保存 $count 项 Cookie，但未识别到明确的登录标识；'
                '若仍提示登录，请重新登录。',
    );

    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    context.read<AppShellController>().select(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _restartWebLogin() async {
    if (_extracting) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    setState(() {
      _webViewGeneration++;
      _webController = null;
      _visitedHosts.clear();
      _autoCheckScheduled = false;
      _error = null;
      _notice = null;
      _currentHost = null;
      _timedOut = false;
      _loadingPage = true;
      _progress = 0;
      _extracting = false;
      _closing = false;
      _webViewCreated = false;
    });
    if (Platform.isWindows && await AppWebViewEnvironment.ensureLogin() == null) {
      if (!mounted) return;
      setState(() {
        _loadingPage = false;
        _error = _webView2Unavailable;
      });
      return;
    }
    await AppWebViewEnvironment.clearLoginCookies();
    if (!mounted) return;
    setState(() => _webViewCreated = true);
    _armTimeout();
  }

  Future<NavigationActionPolicy?> _handleNavigation(NavigationAction action) async {
    final uri = action.request.url;
    if (isAllowedLoginNavigation(uri)) return NavigationActionPolicy.ALLOW;
    if (mounted) {
      setState(() {
        _notice = _blockedSchemes.contains(uri?.scheme.toLowerCase() ?? '')
            ? '该登录方式需要跳转到其他应用，本窗口不支持；'
                  '请使用页面内的短信、密码或本机号码登录。'
            : '这个地址不是咪咕官方页面，已阻止跳转；'
                  '请使用页面内的短信、密码或本机号码登录。';
      });
    }
    return NavigationActionPolicy.CANCEL;
  }

  bool _isMusicUrl(WebUri? url) => url != null && _isMusicHost(url.host);

  bool _isMusicHost(String host) {
    final lower = host.toLowerCase();
    return lower == _musicHost || lower.endsWith('.$_musicHost');
  }

  /// 状态栏显示 WebView 当前真实域名，便于区分“停在通行证页”和“已回音乐页”。
  String get _webViewStatusText {
    final host = _currentHost;
    if (host == null || host.isEmpty) return '正在打开咪咕通行证登录页…';
    if (_autoCheckScheduled) return '$host · 正在检测登录会话';
    return '$host · ${_isMusicHost(host) ? '咪咕音乐页面' : '咪咕官方页面'}';
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = size.width >= 720 ? 30.0 : 14.0;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  14,
                  horizontalPadding,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _closing
                          ? _buildSuccessPanel(context)
                          : _buildWebPanel(context, account),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '咪咕官方登录',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 3),
              Text(
                '只在完成登录这一步打开官方页面，读到凭证后本页自动关闭。',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebPanel(BuildContext context, AccountProvider account) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showHints = constraints.maxHeight >= 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHints) ...[
              LoginInfoBanner(
                icon: Icons.verified_user_outlined,
                tone: context.palette.mint,
                title: '咪咕官方登录页',
                message:
                    '页面由咪咕官方提供，登录方式以官方页面为准。'
                    '登录完成后页面会写入 pacmtoken 等凭据，这里会自动读取并保存到本机安全存储，'
                    '票据由咪咕官方页面自己签发，本程序不自行请求，也不接触账号密码。',
              ),
              const SizedBox(height: 10),
            ],
            if (_error != null) ...[
              LoginStatusBanner(message: _error!, isError: true),
              const SizedBox(height: 10),
            ],
            if (_notice != null) ...[
              LoginStatusBanner(message: _notice!),
              const SizedBox(height: 10),
            ],
            if (account.hasLogin) ...[
              LoginStatusBanner(
                message: account.hasIncompleteLogin
                    ? '本机已有 ${account.cookieCount} 项 Cookie，'
                          '但其中没有咪咕音乐的登录凭据（pacmtoken / mg_auth_sid），'
                          'VIP 曲目暂时无法取链。'
                          '完成新的登录后会覆盖旧的本地凭证。'
                    : '本机已有 ${account.cookieCount} 项登录 Cookie。'
                          '完成新的登录后会覆盖旧的本地凭证。',
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.palette.line),
                ),
                child: Column(
                  children: [
                    _buildWebBar(context),
                    if (_loadingPage)
                      LinearProgressIndicator(
                        value: _progress > 0 && _progress < 100
                            ? _progress / 100
                            : null,
                        minHeight: 2,
                        backgroundColor: context.palette.fillStrong,
                        color: context.palette.accent,
                      ),
                    Expanded(
                      child: _webViewCreated
                          ? _buildWebView()
                          : _buildPreparing(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildWebActions(context),
          ],
        );
      },
    );
  }

  Widget _buildWebBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: context.palette.surfaceSoft,
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: context.palette.mint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _webViewStatusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.palette.textSecondary),
            ),
          ),
          if (_loadingPage)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.palette.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreparing(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            '正在准备登录页面…',
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      key: ValueKey(_webViewGeneration),
      webViewEnvironment: AppWebViewEnvironment.login,
      initialUrlRequest: URLRequest(url: WebUri(buildMiguPassportLoginUrl())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        useShouldOverrideUrlLoading: true,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) => _webController = controller,
      onLoadStart: (controller, url) => _handleLoadStart(url),
      onLoadStop: (controller, url) => unawaited(_handleLoadStop(url)),
      onUpdateVisitedHistory: (controller, url, isReload) => _handleVisitedHistory(url),
      onProgressChanged: (controller, progress) {
        if (!mounted || progress == _progress) return;
        setState(() => _progress = progress);
      },
      shouldOverrideUrlLoading: (controller, action) => _handleNavigation(action),
    );
  }

  Widget _buildWebActions(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final readButton = FilledButton.icon(
          onPressed: _extracting || _closing || !_webViewCreated
              ? null
              : () => unawaited(_readCredentialsManually()),
          icon: _extracting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.task_alt_rounded, size: 17),
          label: Text(_extracting ? '正在读取凭证…' : '我已登录，读取凭证'),
        );
        final reloadButton = OutlinedButton.icon(
          onPressed: _extracting || _closing
              ? null
              : () => unawaited(_restartWebLogin()),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('重新加载'),
        );

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [readButton, const SizedBox(height: 8), reloadButton],
          );
        }
        return Row(
          children: [
            Expanded(child: readButton),
            const SizedBox(width: 10),
            reloadButton,
          ],
        );
      },
    );
  }

  Widget _buildSuccessPanel(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
        decoration: BoxDecoration(
          color: context.palette.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.palette.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 46, color: context.palette.mint),
            const SizedBox(height: 14),
            Text(
              '登录成功',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '凭证已保存，正在返回首页…',
              style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
