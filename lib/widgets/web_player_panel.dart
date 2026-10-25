import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/theme/app_colors.dart';
import '../services/api/migu_cookie_store.dart';
import '../services/auth/web_session_sync.dart';
import '../services/web/app_webview_environment.dart';

const String _webViewUnavailable =
    '无法初始化 Windows WebView2 环境。请确认已安装 Microsoft Edge WebView2 Runtime，'
    '然后点右上角的重新载入按钮重试。';

/// 面板底部的会话说明：只有 Windows 会把网页续签结果读回本机快照，
/// Android 使用系统 WebView 的 Cookie 库，不能承诺“同步回本机”。
String webPlayerSessionHint(String songName, {required bool sessionSyncSupported}) {
  final sync = sessionSyncSupported
      ? '这个页面续签出的登录会话会同步回本机，供原生播放继续使用。'
      : '这个页面续签出的登录会话只留在应用内的网页视图里，不会写回本机保存的登录凭据。';
  return '在这段列表里找到《$songName》并点它的播放按钮；'
      '如果提示未登录，请点页面右上角“登录”，用咪咕自己的弹窗完成登录。'
      '$sync';
}

/// 播放页内嵌的咪咕官方网页播放器。
///
/// 这个面板只做一件事：在独立的用户数据目录里加载咪咕自己的页面。
/// 登录、鉴权、取链和解密都由该页面在咪咕服务端完成；面板不解析页面内容，
/// 也不把音频地址交回应用。
///
/// 唯一的例外是登录会话：页面开始加载时把本机已导入的用户 Cookie 写进该
/// profile，页面加载完再把官方续签后的会话读回本机快照，让内嵌播放和原生
/// 请求共用同一个登录会话。见 [WebSessionSync]。
class MiguWebPlayerPanel extends StatefulWidget {
  const MiguWebPlayerPanel({super.key, required this.url, required this.songName});

  final String url;
  final String songName;

  @override
  State<MiguWebPlayerPanel> createState() => _MiguWebPlayerPanelState();
}

class _MiguWebPlayerPanelState extends State<MiguWebPlayerPanel> {
  bool _ready = false;
  bool _loading = true;
  int _generation = 0;
  String? _error;
  String? _blockedUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant MiguWebPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    // 换了歌曲就整页重建，避免残留上一首的搜索结果。
    setState(() {
      _generation++;
      _loading = true;
      _error = null;
      _blockedUrl = null;
    });
  }

  Future<void> _prepare() async {
    if (Platform.isWindows && await AppWebViewEnvironment.ensurePlayer() == null) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = _webViewUnavailable;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  void _reload() {
    setState(() {
      _generation++;
      _loading = true;
      _error = null;
      _blockedUrl = null;
    });
  }

  void _showBlocked(String url) {
    if (!mounted) return;
    setState(() => _blockedUrl = url);
  }

  /// 页面只允许停留在咪咕官方域名里。
  bool _isMiguUrl(WebUri? uri) {
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'migu.cn' || host.endsWith('.migu.cn');
  }

  Future<NavigationActionPolicy?> _handleNavigation(NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null || _isMiguUrl(uri)) return NavigationActionPolicy.ALLOW;
    _showBlocked('${uri.host}${uri.path}');
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        if (_blockedUrl != null) _buildNotice(context, _blockedUrl!),
        const Divider(height: 1),
        Expanded(child: _buildStage(context)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    if (Platform.isAndroid) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
        child: Row(
          children: [
            Icon(Icons.public_rounded, size: 15, color: context.palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '咪咕官方网页播放器',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            IconButton(
              onPressed: _ready && _error == null ? _reload : null,
              tooltip: '重新载入',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.public_rounded, size: 15, color: context.palette.accent),
          const SizedBox(width: 8),
          Text(
            '咪咕官方网页播放器',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13),
          ),
          const SizedBox(width: 8),
          if (_loading)
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          else
            Text(
              '登录与播放权限由咪咕页面自己判断',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.textMuted, fontSize: 10),
            ),
          const Spacer(),
          IconButton(
            onPressed: _ready && _error == null ? _reload : null,
            tooltip: '重新载入',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(BuildContext context, String target) {
    return Container(
      width: double.infinity,
      color: context.palette.fillSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Text(
        '已阻止跳转到非咪咕域名：$target',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.palette.textMuted, fontSize: 10.5),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.gpp_bad_outlined,
              size: 26,
              color: context.palette.danger.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
                fontSize: 11.5,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(_prepare()),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            key: ValueKey('$_generation|${widget.url}'),
            webViewEnvironment: AppWebViewEnvironment.player,
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              sharedCookiesEnabled: true,
              useShouldOverrideUrlLoading: true,
              supportZoom: Platform.isAndroid,
              useWideViewPort: Platform.isAndroid,
              loadWithOverviewMode: Platform.isAndroid,
              disableLongPressContextMenuOnLinks: true,
            ),
            onLoadStart: (controller, url) {
              unawaited(WebSessionSync.seedPlayer(MiguCookieStore.instance));
            },
            onProgressChanged: (controller, progress) {
              if (!mounted || progress < 100) return;
              setState(() => _loading = false);
            },
            onLoadStop: (controller, url) {
              unawaited(WebSessionSync.harvestPlayer(MiguCookieStore.instance));
              if (!mounted) return;
              setState(() {
                _loading = false;
                _blockedUrl = null;
              });
            },
            shouldOverrideUrlLoading: (controller, action) => _handleNavigation(action),
          ),
        ),
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: context.palette.surface.withValues(alpha: 0.86),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '正在打开咪咕官方页面…',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.palette.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildHint(context)),
      ],
    );
  }

  Widget _buildHint(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: context.palette.surface.withValues(alpha: 0.82),
        child: Text(
          webPlayerSessionHint(
            widget.songName,
            sessionSyncSupported: WebSessionSync.supported,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.palette.textMuted, fontSize: 10, height: 1.5),
        ),
      ),
    );
  }
}
