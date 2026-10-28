import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/widgets/web_player_panel.dart';

/// 政策标题与正文拼成一段，便于按关键词检查披露是否齐全。
String _policyText() => AppConstants.privacyPolicy
    .map((notice) => '${notice.title}${notice.body}')
    .join('\n');

void main() {
  group('必填声明文本保持原样', () {
    test('关于页用途与版权声明', () {
      expect(
        AppConstants.aboutNotice,
        '本应用为第三方咪咕音乐流式播放客户端，仅作个人学习、技术研究使用。'
        '本项目无破解会员、绕过权限等功能，不会保存、下载、传播任何音频文件，不用于商业用途。'
        '所有版权内容归属原平台及著作权方。',
      );
    });

    test('账号权限与播放边界', () {
      expect(
        AppConstants.accountPolicy,
        '账号权限完全跟随咪咕官方：只有登录咪咕账号、且该账号拥有对应曲目权益时，才可能拿到播放地址。'
        '禁止实现歌曲下载、音频文件解密、本地持久保存音频文件，仅在线流式播放。',
      );
    });

    test('WebView 使用范围声明', () {
      expect(
        AppConstants.webViewPolicy,
        '原生登录只调用咪咕通行证与音乐站的会话接口，代码里不含任何账号密钥，也不生成官方风控签名；'
        '只有你主动点「改用咪咕官方页面登录」时才临时打开一个加载通行证页面的登录窗口，'
        '读到凭证后该窗口立即关闭；播放页只为 VIP 曲目内嵌咪咕官方网页播放器；'
        '两处 WebView 都只显示咪咕自己的页面，其余界面全部为原生 Flutter。'
        '不读取内嵌播放器页面里的音频地址；只在这些页面与自己之间同步本机账号的登录会话，'
        '其余 Cookie 一概不取。',
      );
    });

    test('登录弹窗底部只留一句提示，详情走隐私政策', () {
      expect(
        AppConstants.loginPrivacyHint,
        '手机号、验证码与密码只在登录请求中提交给咪咕通行证，本机不保存；'
        '登录换来的会话凭据只写入系统安全存储。',
      );
      // 整段说明已经搬进隐私政策，弹窗里不再重复一篇，只留入口。
      final center = File('lib/widgets/account_center.dart').readAsStringSync();
      expect(center, contains('showPrivacyPolicyDialog'));
      expect(center, contains('隐私政策'));
      expect(AppConstants.privacyPolicyIntro, isNotEmpty);
    });

    test('图形验证码只显示咪咕下发的图片，由本人识别', () {
      // 声明里必须说清「人来输」，并且不再有「本软件没有实现」这种重复表述。
      final text = _policyText();
      expect(text, contains('由你本人照着输入'));
      expect(text, isNot(contains('不代解')));

      final panel = File('lib/widgets/native_login_panel.dart').readAsStringSync();
      expect(panel, contains('图形验证码'));
      expect(panel, contains('由你本人识别'));
      // 答案只可能来自输入框，没有任何程序生成的值。
      expect(panel, contains('_captcha.text'));

      // 没有引入任何识别图片或自动作答验证码的依赖。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final solver in ['ocr', 'tesseract', 'captcha_solver', 'opencv']) {
        expect(pubspec, isNot(contains(solver)));
      }
    });

    test('网络请求边界', () {
      expect(
        AppConstants.networkPolicy,
        '音乐数据来自咪咕网页公开接口；只有你主动导入歌单时，才会读取对应平台公开歌单的曲目名与歌手，'
        '用于匹配咪咕曲库。不登录第三方账号、不下载音频、不批量抓取。',
      );
    });

    test('外部歌单导入边界', () {
      expect(
        AppConstants.externalPlaylistNotice,
        '导入只读取公开歌单的曲目名与歌手，再逐首搜索咪咕曲库；匹配不到的歌曲会被跳过。'
        '不登录网易云、QQ音乐或酷狗账号，也不读取或保存这些平台的 Cookie。',
      );
    });

    test('请求固定携带咪咕来源页', () {
      expect(AppConstants.miguReferer, 'https://music.migu.cn');
    });

    test('VIP 缺凭据的提示指向账号入口，不再提已取消的 Cookie 导入', () {
      final source = File('lib/services/api/migu_music_api.dart').readAsStringSync();
      expect(source, isNot(contains('设置里导入')));
      expect(source, isNot(contains('浏览器 Cookie')));
      expect(source, contains('请点开账号入口'));
    });

    test('播放器提示按平台说明会话去向', () {
      final windows = webPlayerSessionHint('晴天', sessionSyncSupported: true);
      expect(windows, contains('《晴天》'));
      expect(windows, contains('会同步回本机'));

      final android = webPlayerSessionHint('晴天', sessionSyncSupported: false);
      expect(android, isNot(contains('会同步回本机')));
      expect(android, contains('不会写回本机保存的登录凭据'));
    });

    test('内嵌播放器不读写任何 Cookie 或音频地址', () {
      final source = File('lib/widgets/web_player_panel.dart').readAsStringSync();
      expect(source, isNot(contains('CookieManager')));
      expect(source, isNot(contains('getCookies')));
      expect(source, isNot(contains('evaluateJavascript')));
    });

    test('清空网页会话只作用于登录环境，不波及内嵌播放器', () {
      final source = File('lib/services/web/app_webview_environment.dart')
          .readAsStringSync();
      expect(source, contains('webview2_player'));
      final clearCalls = RegExp(
        r'CookieManager\.instance\(\s*webViewEnvironment:\s*(\w+),?\s*\)'
        r'\s*\.deleteAllCookies',
      ).allMatches(source);
      expect(clearCalls, hasLength(1));
      expect(clearCalls.single.group(1), 'login');
    });

    test('登录页每一处退出都无条件清网页会话，不留可复用登录态', () {
      final source =
          File('lib/pages/official_login_page.dart').readAsStringSync();
      // SSO 实验的「保留 Cookie」开关：通行证会话是会话级 Cookie，应用一退就没了，
      // 这条路已被证伪，开关本身也不许再出现。
      expect(source, isNot(contains('keepLoginProfileCookies')));
      expect(
        RegExp(
          r'if\s*\([^)]*\)\s*\{\s*(?:unawaited\()?\s*await\s+'
          r'AppWebViewEnvironment\.clearLoginCookies',
        ).hasMatch(source),
        isFalse,
      );
      expect(
        RegExp(r'AppWebViewEnvironment\.clearLoginCookies\(\)')
            .allMatches(source)
            .length,
        4,
      );
    });

    test('账号弹窗内嵌原生登录面板，网页只出现在官方登录窗口与播放器', () {
      final center = File('lib/widgets/account_center.dart').readAsStringSync();
      expect(center, contains('NativeLoginPanel'));
      expect(center, isNot(contains('flutter_inappwebview')));
      expect(center, isNot(contains('InAppWebView')));

      // 原生登录面板自己完成手机号、验证码与密码的提交，不能夹任何网页。
      final panel = File('lib/widgets/native_login_panel.dart').readAsStringSync();
      expect(panel, isNot(contains('flutter_inappwebview')));
      expect(panel, isNot(contains('InAppWebView')));

      // 系统浏览器登录与手动粘贴 Cookie 已经取消，不许再回到界面里。
      expect(center + panel, isNot(contains('launchUrl')));
      expect(center + panel, isNot(contains('showCookieImportDialog')));

      final webHosts = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') &&
                file.readAsStringSync().contains('InAppWebView('),
          )
          .map((file) => file.path.replaceAll(r'\', '/'))
          .toSet();
      expect(webHosts, {
        'lib/pages/official_login_page.dart',
        'lib/widgets/web_player_panel.dart',
      });
    });
  });

  group('隐私政策与实现逐条对应', () {
    test('条目结构完整，标题不重复也不为空', () {
      // 数量是刻意锁定的：删条目等于删披露，必须连同这条一起改。
      expect(AppConstants.privacyPolicy, hasLength(12));
      final titles = AppConstants.privacyPolicy.map((n) => n.title).toList();
      expect(titles.toSet(), hasLength(titles.length));
      for (final notice in AppConstants.privacyPolicy) {
        expect(notice.title.trim(), isNotEmpty);
        expect(notice.body.trim().length, greaterThan(30));
      }
    });

    test('凭据部分说清加密提交、本机不保存与安全存储落点', () {
      final text = _policyText();
      expect(text, contains('RSA 公钥加密后直接提交给咪咕通行证'));
      expect(text, contains('本机不保存、不写日志'));
      expect(text, contains('不含任何账号密钥'));
      expect(text, contains('原生登录保存取链用的 pacmtoken'));
      expect(text, contains('通行证签发的那张登录票据'));
      expect(text, contains('这条路径没有登录票据'));
      expect(text, contains('Keystore'));
      // Windows 侧是 DPAPI 按当前用户加密的密文，不能写成硬件安全芯片或凭据管理器。
      expect(text, contains('以当前 Windows 账户加密的密文'));
      expect(text, contains('应用数据目录'));
    });

    test('验证码、设备标识与假指纹按真实实现披露', () {
      final text = _policyText();
      expect(text, contains('不识别图片、不自动作答'));
      expect(text, contains('验证码会话只留在内存'));
      expect(text, contains('ANDROID_ID'));
      expect(text, contains('随机 UUID 存在本机'));
      expect(text, contains('只发给咪咕，不发给任何第三方'));
      expect(text, contains('fingerPrint 在每次启动时生成一次'));
      expect(text, isNot(contains('fingerPrint 是每次登录新造的随机值')));
      expect(text, contains('固定填字符串 h5page'));
      expect(text, contains('不读取真实 IMEI 或 IMSI'));
    });

    test('本机其余数据与网络去向连例外一起写明', () {
      final text = _policyText();
      expect(text, contains('最多 10 条'));
      expect(text, contains('没有播放历史，没有收听统计'));
      expect(text, contains('音频 CDN'));
      expect(text, contains('网易云、QQ音乐、酷狗'));
      // 播放器目录里的网页数据不会被清除，这是实现事实，不能含糊承诺。
      expect(text, contains('不会被本应用清除'));
      expect(text, contains('不写日志文件'));
      expect(text, contains('没有统计、广告或崩溃上报组件'));
      // 版本检查是新增的对外请求，政策要同时写出地址和「不带凭据」。
      expect(text, contains('api.github.com'));
      expect(text, contains('请求里不带账号、不带凭据'));
      expect(text, contains('Android 清单只声明网络访问一项'));
      expect(text, contains('%APPDATA%'));
    });

    test('登录窗口读取 document.cookie 的兜底也写进政策', () {
      final text = _policyText();
      expect(text, contains('document.cookie'));
      expect(text, contains('只取名称与值'));
    });

    test('退出登录只说清本机动作，不夸大成服务端登出', () {
      final text = _policyText();
      // 换账号与退出都在个人中心里，政策要点名这两个入口。
      expect(text, contains('退出登录'));
      expect(text, contains('切换账号'));
      // 咪咕没有登出接口，这句是硬事实，不能写成「登出服务端会话」。
      expect(text, contains('咪咕没有登出接口'));
      expect(text, contains('退出只发生在你这台设备上，不会通知服务端'));
      // 退出不碰设置、搜索历史与导入的歌单，范围要划清。
      expect(text, contains('设置、搜索历史与导入的歌单都不受这一步影响'));
      expect(text, isNot(contains('没有退出登录')));
    });

    test('自动退出写清两次回绝才生效，403 与公开接口都不算失效', () {
      final text = _policyText();
      expect(text, contains('自动退出'));
      expect(text, contains('HTTP 401'));
      expect(text, contains('请先登录'));
      // 单次信号只降级：删凭据不可逆，政策不能承诺「一被拒就登出」。
      expect(text, contains('第一次只把状态标成「登录可能已失效」并继续保留凭据'));
      expect(text, contains('隔过 30 分钟后账号接口再次回绝'));
      // 取证记录对外可见，但绝不能带凭据内容。
      expect(text, contains('这条记录不含 Cookie、手机号或任何凭据内容'));
      // 403 很可能只是这首歌没权益，把它当失效会把人无故登出。
      expect(text, contains('HTTP 403'));
      expect(text, contains('不会动你的登录'));
      expect(text, contains('不参与失效判定'));

      final provider = File('lib/providers/account_provider.dart').readAsStringSync();
      expect(provider, contains('unawaited(onAutoSignOut?.call())'));
      // 自动退出挂在 markSessionRevoked 上，markRejected 必须保持只改状态。
      final revoked = provider.substring(
        provider.indexOf('void markSessionRevoked()'),
        provider.indexOf('Future<void> signOut()'),
      );
      expect(revoked, contains('onAutoSignOut'));
      expect(revoked, contains('_ledger.strikes < 2'));
      final rejected = provider.substring(
        provider.indexOf('void markRejected()'),
        provider.indexOf('void markSessionRevoked()'),
      );
      expect(rejected, isNot(contains('onAutoSignOut')));
      expect(rejected, isNot(contains('signOut()')));

      // 判定必须按接口地址收口，否则一条歌词 401 就能登出用户。
      final client = File('lib/services/api/migu_api_client.dart').readAsStringSync();
      expect(client, contains('bool isLoginScopedEndpoint(Uri uri)'));
      expect(client, contains('/user/h5/user-info/'));
      expect(client, contains('/pc/user/home-page/'));
    });

    test('票据一次性写进政策：不再承诺静默续期', () {
      final text = _policyText();
      // 留存票据这件事必须说清它换不来新会话，否则用户会以为掉线能自动恢复。
      expect(text, contains('它换不来第二份会话'));
      expect(text, contains('应用不会拿它做自动续期'));
      expect(text, isNot(contains('先用留存的登录票据静默换一次新会话')));
      expect(text, contains('登录票据与账号快照'));
      // 这个域名现在只做换票与校验，政策不能再把它写成续期通道。
      expect(text, contains('c.musicapp.migu.cn 负责登录换票与登录状态校验'));

      final provider = File('lib/providers/account_provider.dart').readAsStringSync();
      // 换票只剩调试入口一个调用方：失效判定这条线路上不能有它。
      final revoked = provider.substring(
        provider.indexOf('void markSessionRevoked()'),
        provider.indexOf('/// 往调试记录里写一条续期事件'),
      );
      expect(revoked, isNot(contains('_renewSession')));
      expect(provider, contains('_passport.renewSession'));
      expect(provider, isNot(contains('renewalCooldown')));
      expect(provider, contains('applyRenewedCredentials'));
      // 票据必须和 Cookie 一样进安全存储，不能落在普通偏好里。
      final ticketStore = File('lib/services/api/passport_ticket_store.dart')
          .readAsStringSync();
      expect(ticketStore, contains('SecureCookieStorage'));
      expect(ticketStore, isNot(contains('SharedPreferences')));
    });

    test('常量里出现的咪咕域名都要在政策里点名', () {
      final constants = File('lib/core/constants/app_constants.dart')
          .readAsStringSync();
      final hosts = RegExp(r'https://([A-Za-z0-9._-]+)')
          .allMatches(constants)
          .map((match) => match.group(1)!)
          .where((host) => host.endsWith('migu.cn'))
          .toSet();
      expect(hosts, isNotEmpty);
      final text = _policyText();
      for (final host in hosts) {
        expect(text, contains(host), reason: '$host 已用于请求，却未在隐私政策中说明');
      }
    });

    test('不写实现做不到的承诺', () {
      final text = _policyText();
      for (final overclaim in [
        '不保存任何 Cookie',
        '安全芯片',
        '凭据管理器',
        '全部清除',
        '只会连接咪咕',
        '硬件级加密',
        '永久有效',
      ]) {
        expect(text, isNot(contains(overclaim)));
      }
    });

    test('个人中心里的退出确实清凭据、清队列并停保活', () {
      // 政策承诺「退出登录清除本机凭据」，实现必须真的三条都做到。
      final provider = File('lib/providers/account_provider.dart').readAsStringSync();
      expect(provider, contains('Future<void> signOut()'));
      expect(provider, contains('_cookieStore.clearLoginCookies()'));
      expect(provider, contains('_authSessionStore.clear()'));
      expect(provider, contains('onSessionLost?.call()'));

      final center = File('lib/widgets/account_center.dart').readAsStringSync();
      expect(center, contains('signOut()'));
      expect(center, contains('clearQueue()'));
      expect(center, contains('退出登录'));
      expect(center, contains('切换账号'));
    });

    test('常驻托盘把「后台还在发什么」讲清楚，并且只有 Windows 有这个入口', () {
      final text = _policyText();
      expect(text, contains('关闭主窗口后常驻托盘'));
      expect(text, contains('默认关闭'));
      expect(text, contains('每 45–75 分钟'));
      expect(text, contains('不播放音频、不读取你的文件、没有任何统计上报'));
      // 托盘组件进了依赖，第三方组件那条不能还停在「只有播放、界面与网络库」。
      expect(text, contains('窗口与托盘组件'));
      expect(text, isNot(contains('依赖里只有播放、界面与网络库')));

      final settingsPage =
          File('lib/pages/settings_page.dart').readAsStringSync();
      expect(settingsPage, contains('关闭主窗口后常驻托盘'));
      expect(settingsPage, contains('settings.backgroundKeepAliveEnabled'));

      final tray =
          File('lib/services/platform/desktop_tray.dart').readAsStringSync();
      expect(tray, contains('Platform.isWindows'));
      // 安卓没有托盘，后台进程也随时被系统回收，这个能力不许在安卓侧假装存在。
      expect(tray, contains('Android'));
      // 后台只是继续同一件探测，不许顺手拉起网页、新的接口或别的域名。
      expect(tray, isNot(contains('flutter_inappwebview')));
      expect(tray, isNot(contains('InAppWebView')));
      expect(tray, isNot(contains('http')));
      // 政策说「后台期间不播放音频」，收起窗口这一侧就得真的按下暂停。
      expect(tray, contains('onWindowHidden'));

      // 开关要接通保活本身，否则这项设置只是一句空话。
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('keepAlive.allowsBackground = enabled'));
    });

    test('隐私政策只留在登录弹窗，关于页不再重复一份', () {
      final dialog = File('lib/widgets/privacy_policy.dart').readAsStringSync();
      expect(dialog, contains('AppConstants.privacyPolicy'));
      expect(dialog, contains('showPrivacyPolicyDialog'));

      // 用户要求把关于页的隐私政策模块删掉：正文只在登录弹窗里出现一次。
      final about = File('lib/pages/about_page.dart').readAsStringSync();
      expect(about, isNot(contains('PrivacyPolicySections')));
      expect(about, isNot(contains("title: '隐私政策'")));
      expect(about, isNot(contains('privacy_policy.dart')));
      expect(about, isNot(contains('_PrivacyBlock')));
    });
  });
}
