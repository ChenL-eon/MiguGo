import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/providers/player_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:migu_lele/widgets/account_center.dart';
import 'package:migu_lele/widgets/native_login_panel.dart';
import 'package:migu_lele/widgets/privacy_policy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

/// 账号弹窗里的原生登录面板：只验证按钮可用态与入口文案，不发任何网络请求。
Future<void> _pumpLogin(WidgetTester tester, {MiguPassportApi? passport}) async {
  final storage = FakeSecureCookieStorage();
  final cookieStore = MiguCookieStore(secureStorage: storage);
  await cookieStore.init();
  final account = AccountProvider(
    cookieStore: cookieStore,
    authSessionStore: AuthSessionStore(storage: storage),
    passportTicketStore: PassportTicketStore(storage: storage),
    passportApi: passport,
  );
  await account.initialize();

  await tester.pumpWidget(
    ChangeNotifierProvider<AccountProvider>.value(
      value: account,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: const NativeLoginPanel(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 只记录调用次数的播放器替身。
///
/// 真播放器的 `stop()` 走平台通道，回包在 widget 测试的假异步时钟里不保证送达，
/// 等它会让用例偶发卡死；这里只验证弹窗确实去清了队列。
class _TrackingPlayer extends PlayerProvider {
  _TrackingPlayer(super.api);

  int clearCalls = 0;

  @override
  Future<void> clearQueue() async {
    clearCalls++;
  }
}

/// 打开真正的账号弹窗（左下角卡片走的那个），用于检查弹窗内的入口。
///
/// 退出登录要顺带停播放、清队列，所以这里连播放器一起挂上。
Future<_AccountDialog> _pumpAccountDialog(
  WidgetTester tester, {
  bool signedIn = false,
}) async {
  final storage = FakeSecureCookieStorage();
  final cookieStore = MiguCookieStore(secureStorage: storage);
  await cookieStore.init();
  final player = signedIn
      ? _TrackingPlayer(MiguMusicApi(client: MiguApiClient(cookieStore: cookieStore)))
      : null;
  final (ledger, clock) = testLedger();
  late final AccountProvider account;
  account = AccountProvider(
    cookieStore: cookieStore,
    authSessionStore: AuthSessionStore(storage: storage),
    passportTicketStore: PassportTicketStore(storage: storage),
    ledger: ledger,
    // 与 main.dart 一致：账号接口两次回绝才自动退一遍，顺带清队列。
    onAutoSignOut: () async {
      await account.signOut();
      await player!.clearQueue();
    },
  );
  await account.initialize();
  if (signedIn) {
    await account.importLoginCookie('uid=u1; pacmtoken=stub');
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: account),
        if (player != null) ChangeNotifierProvider<PlayerProvider>.value(value: player),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(showAccountCenterDialog(context)),
              child: const Text('open-account'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open-account'));
  await tester.pumpAndSettle();
  return (
    account: account,
    player: player,
    storage: storage,
    ledger: ledger,
    clock: clock,
  );
}

typedef _AccountDialog = ({
  AccountProvider account,
  _TrackingPlayer? player,
  FakeSecureCookieStorage storage,
  SessionRejectLedger ledger,
  StepClock clock,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 不给 SharedPreferences 注册 mock 通道，Cookie 仓库的读取永远不会返回，
    // widget 测试会一直卡在假异步时钟里。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('验证码页签：填齐手机号与验证码才允许提交', (tester) async {
    await _pumpLogin(tester);

    final send = find.widgetWithText(TextButton, '发送验证码');
    final submit = find.widgetWithText(OutlinedButton, '登录');
    final phone = find.byType(TextField).first;
    final code = find.byType(TextField).last;

    await tester.enterText(phone, '1380000000');
    await tester.pump();
    expect(tester.widget<TextButton>(send).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);

    await tester.enterText(phone, '13800000000');
    await tester.pump();
    expect(tester.widget<TextButton>(send).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);

    await tester.enterText(code, '248157');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNotNull);

    await tester.enterText(code, '');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
  });

  testWidgets('账号密码页签：按账号与密码判定可用性', (tester) async {
    await _pumpLogin(tester);

    await tester.tap(find.text('账号密码'));
    await tester.pump();

    final submit = find.widgetWithText(OutlinedButton, '登录');
    final account = find.byType(TextField).first;
    final password = find.byType(TextField).last;

    expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);

    await tester.enterText(account, '13800000000');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);

    await tester.enterText(password, 'pw');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNotNull);
  });

  testWidgets('账号弹窗直接内嵌原生登录，没有浏览器与 Cookie 入口', (tester) async {
    await _pumpAccountDialog(tester);

    expect(find.byType(NativeLoginPanel), findsOneWidget);
    expect(find.text('登录咪咕账号'), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    for (final label in ['在系统浏览器登录', '导入登录 Cookie', '清除登录信息']) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('登录弹窗里点「隐私政策」就地展开全文，关掉回到登录页', (tester) async {
    await _pumpAccountDialog(tester);

    expect(find.textContaining(AppConstants.loginPrivacyHint), findsOneWidget);
    final entry = find.widgetWithText(TextButton, '隐私政策');
    expect(entry, findsOneWidget);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicySections), findsOneWidget);
    expect(find.textContaining(AppConstants.privacyPolicyIntro), findsOneWidget);
    for (final notice in AppConstants.privacyPolicy) {
      expect(
        find.text(notice.title),
        findsOneWidget,
        reason: '政策少了这一条：${notice.title}',
      );
    }

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicySections), findsNothing);
    expect(find.byType(NativeLoginPanel), findsOneWidget);
  });

  testWidgets('已登录时同一个弹窗变成个人中心，不再显示登录表单', (tester) async {
    final dialog = await _pumpAccountDialog(tester, signedIn: true);

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.byType(NativeLoginPanel), findsNothing);
    expect(find.text('咪咕音乐账号'), findsOneWidget);
    expect(find.textContaining('只存在系统安全存储里'), findsOneWidget);
    expect(find.text('播放权益'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '切换账号'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    // 简约版不承诺任何会员判定，只说权益由咪咕决定。
    expect(
      find.textContaining('由咪咕按账号权益判定'),
      findsWidgets,
      reason: dialog.account.isVip ? '未登录资料时按非会员文案' : '没有权益判定说明',
    );
  });

  testWidgets('退出登录先确认，点取消什么都不清', (tester) async {
    final dialog = await _pumpAccountDialog(tester, signedIn: true);

    final signOut = find.widgetWithText(OutlinedButton, '退出登录');
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(find.text('确认退出'), findsOneWidget);
    expect(find.textContaining('正在播放的曲目会停止并清空播放列表'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(dialog.account.hasLogin, isTrue);
    expect(find.text('个人中心'), findsOneWidget);
  });

  testWidgets('确认退出后凭据出盘、播放复位，弹窗退回未登录', (tester) async {
    final dialog = await _pumpAccountDialog(tester, signedIn: true);

    final signOut = find.widgetWithText(OutlinedButton, '退出登录');
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '确认退出'));
    await tester.pumpAndSettle();

    expect(dialog.account.hasLogin, isFalse);
    expect(dialog.account.cookieCount, 0);
    expect(dialog.storage.values['migu_manual_cookies_v2'], isNull);
    // 正在放的东西不能留在旧账号手里：队列要被真的清掉一次。
    expect(dialog.player!.clearCalls, 1);
    // 退出走的是「关掉弹窗」，回到左下角卡片那一屏。
    expect(find.text('open-account'), findsOneWidget);
    expect(find.textContaining('已退出登录'), findsOneWidget);
    // 提示条自己会消失，留到计时结束，免得测试里挂着一个未完成 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('切换账号清掉旧凭据后留在弹窗里，登录表单就地出现', (tester) async {
    final dialog = await _pumpAccountDialog(tester, signedIn: true);

    final switchAccount = find.widgetWithText(OutlinedButton, '切换账号');
    await tester.ensureVisible(switchAccount);
    await tester.tap(switchAccount);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '确认退出'));
    await tester.pumpAndSettle();

    expect(dialog.account.hasLogin, isFalse);
    expect(dialog.storage.values['migu_manual_cookies_v2'], isNull);
    // 换账号同样要把旧账号正在放的那一首停掉。
    expect(dialog.player!.clearCalls, 1);
    // 弹窗没关，标题与内容都退回登录态，可以直接登新账号。
    expect(find.text('登录咪咕账号'), findsOneWidget);
    expect(find.byType(NativeLoginPanel), findsOneWidget);
  });

  testWidgets('账号接口两次回绝才会话自动退出，弹窗退回登录表单并说明原因', (tester) async {
    final dialog = await _pumpAccountDialog(tester, signedIn: true);
    expect(find.text('个人中心'), findsOneWidget);

    // 第一次回绝只降级：人还留在个人中心，凭据一项没动。
    noteAccountRejection(dialog.ledger, code: '290001', info: '请先登录');
    dialog.account.markSessionRevoked();
    await tester.pump();
    expect(find.text('个人中心'), findsOneWidget);
    expect(dialog.account.hasLogin, isTrue);
    expect(dialog.player!.clearCalls, 0);
    expect(find.textContaining('最近一次拒绝'), findsOneWidget);

    // 隔过 30 分钟再次被拒才确认这份凭据真的作废。
    dialog.clock.advance(const Duration(minutes: 31));
    noteAccountRejection(dialog.ledger, code: '290001', info: '请先登录');
    dialog.account.markSessionRevoked();
    await tester.pumpAndSettle();

    // 不再把界面卡在「登录可能已失效」：凭据出盘、队列清空、就地回到登录表单。
    expect(find.text('个人中心'), findsNothing);
    expect(find.byType(NativeLoginPanel), findsOneWidget);
    expect(dialog.account.hasLogin, isFalse);
    expect(dialog.storage.values['migu_manual_cookies_v2'], isNull);
    expect(dialog.player!.clearCalls, 1);
    expect(find.text('登录已失效，已自动退出'), findsOneWidget);
    expect(find.textContaining('咪咕已拒绝本机保存的登录凭据'), findsOneWidget);
  });

  testWidgets('自动退出后左下角卡片直接说明原因，不再写通用引导文案', (tester) async {
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, clock) = testLedger();
    late final AccountProvider account;
    account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      ledger: ledger,
      // 与 main.dart 一致：两次回绝确认失效就自己退一遍，卡片才有「已自动退出」可显示。
      onAutoSignOut: () => account.signOut(),
    );
    await account.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: account,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 260, child: AccountSummaryCard())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('点击登录，使用自己的账号权益'), findsOneWidget);

    await account.importLoginCookie('pacmtoken=p1; uid=u1');
    noteAccountRejection(ledger);
    account.markSessionRevoked();
    await tester.pump();
    // 只被拒过一次，卡片还在讲当前登录态，不该装作已经退出。
    expect(find.text('登录可能已失效'), findsOneWidget);

    clock.advance(const Duration(minutes: 31));
    noteAccountRejection(ledger);
    account.markSessionRevoked();
    await tester.pumpAndSettle();

    expect(find.text('登录已失效，已自动退出'), findsOneWidget);
    expect(find.text('点击登录，使用自己的账号权益'), findsNothing);
  });

  testWidgets('被风控要求时展开图形验证码行，点图片换一张', (tester) async {
    final stub = PassportStubAdapter(authnStatus: '0071', authnMessage: '请输入图片验证码');
    await _pumpLogin(tester, passport: MiguPassportApi(dio: dioWith(stub)));

    expect(find.text('图形验证码'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '13800000000');
    await tester.enterText(find.byType(TextField).last, '248157');
    await tester.pump();

    final submit = find.widgetWithText(OutlinedButton, '登录');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('图形验证码'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('由你本人识别'), findsOneWidget);
    expect(
      stub.requests.map((request) => request.uri.path),
      containsAllInOrder(['/authn/dynamicpassword', '/captcha/graph/risk']),
      reason: '登录被风控挡下后立刻去咪咕取那张图片',
    );
    expect(
      tester.widget<OutlinedButton>(submit).onPressed,
      isNull,
      reason: '还没照图输入字符，不放行',
    );

    await tester.enterText(find.byType(TextField).last, '7k2m');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(submit).onPressed, isNotNull);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(
      stub.requests
          .lastWhere((request) => request.uri.path == '/captcha/graph/risk')
          .queryParameters['showType'],
      '1',
      reason: '点图片就是官方的「换一张」',
    );
  });

  testWidgets('填好图形验证码后先让咪咕认一次，再重新提交登录', (tester) async {
    final stub = PassportStubAdapter(authnStatus: '0071', authnMessage: '请输入图片验证码');
    await _pumpLogin(tester, passport: MiguPassportApi(dio: dioWith(stub)));

    await tester.enterText(find.byType(TextField).first, '13800000000');
    await tester.enterText(find.byType(TextField).last, '248157');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '登录'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '7k2m');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '登录'));
    await tester.pumpAndSettle();

    expect(
      stub.requests.map((request) => request.uri.path),
      containsAllInOrder([
        '/authn/dynamicpassword',
        '/captcha/graph/risk',
        '/captcha/graph/check',
        '/authn/dynamicpassword',
      ]),
    );
    final check = stub.requests.firstWhere(
      (request) => request.uri.path == '/captcha/graph/check',
    );
    expect(check.queryParameters['captcha'], '7k2m');
    final replayed = stub.requests.lastWhere(
      (request) => request.uri.path == '/authn/dynamicpassword',
    );
    expect(
      replayed.headers['Cookie'],
      contains('mgnd_session_id=stub-session'),
      reason: '验证码答案记在那份通行证会话上',
    );
    expect(stub.authnForms.last['captcha'], '7k2m', reason: '认过一次的图形验证码随登录一起提交');
  });

  testWidgets('咪咕给的图片无法显示时，只留一句官方页面提示', (tester) async {
    final stub = PassportStubAdapter(
      authnStatus: '0071',
      authnMessage: '请输入图片验证码',
      riskCaptchaUrl: '',
    );
    await _pumpLogin(tester, passport: MiguPassportApi(dio: dioWith(stub)));

    await tester.enterText(find.byType(TextField).first, '13800000000');
    await tester.enterText(find.byType(TextField).last, '248157');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('需要官方页面协助'), findsOneWidget);
    expect(find.text('图形验证码'), findsNothing);
    expect(find.textContaining('改用官方页面'), findsOneWidget);
    // 同一件事不再重复两遍。
    expect(find.textContaining('不代解'), findsNothing);
  });
}
