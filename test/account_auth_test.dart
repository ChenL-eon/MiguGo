import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/api/secure_cookie_storage.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthSession 序列化', () {
    test('状态与时间可往返', () {
      final session = AuthSession(
        status: AuthStatus.verified,
        importedAt: DateTime.utc(2026, 10, 20, 8),
        lastCheckedAt: DateTime.utc(2026, 10, 20, 9),
      );
      final restored = AuthSession.fromJson(jsonDecode(jsonEncode(session.toJson())));
      expect(restored, isNotNull);
      expect(restored!.status, AuthStatus.verified);
      expect(restored.importedAt, DateTime.utc(2026, 10, 20, 8));
      expect(restored.lastCheckedAt, DateTime.utc(2026, 10, 20, 9));
    });

    test('未知状态返回 null', () {
      expect(AuthSession.fromJson({'status': 'unknown'}), isNull);
    });
  });

  group('认证状态存储', () {
    test('读写认证状态', () async {
      final storage = FakeSecureCookieStorage();
      final store = AuthSessionStore(storage: storage);
      expect((await store.read()).status, AuthStatus.none);

      final now = DateTime.utc(2026, 10, 20, 10);
      await store.write(AuthSession(status: AuthStatus.unverified, importedAt: now));
      final restored = await store.read();
      expect(restored.status, AuthStatus.unverified);
      expect(restored.importedAt, now);

      await store.write(AuthSession(status: AuthStatus.verified, importedAt: now));
      expect((await store.read()).status, AuthStatus.verified);
    });

    test('损坏的记录按未登录处理', () async {
      final storage = FakeSecureCookieStorage();
      storage.values[AuthSessionStore.defaultKey] = '{bad json';
      final store = AuthSessionStore(storage: storage);
      expect((await store.read()).status, AuthStatus.none);
    });
  });

  group('AccountProvider 状态机', () {
    test('导入后未验证，VIP 请求结果驱动验证与失效状态', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();

      expect(account.status, AuthStatus.none);
      expect(account.hasLogin, isFalse);

      final count = await account.importLoginCookie('uid=u1; mg_auth_sid=s1');
      expect(count, 2);
      expect(account.status, AuthStatus.unverified);
      expect(account.hasWebSessionCookie, isTrue);
      expect(account.statusLabel, '已保存登录凭据');
      expect(account.importedAt, isNotNull);

      account.markVerified();
      expect(account.status, AuthStatus.verified);
      expect(account.lastCheckedAt, isNotNull);

      account.markRejected();
      expect(account.status, AuthStatus.rejected);
      expect(account.statusHint, contains('可能已失效'));
      // 应用不自动清掉本机凭据：失效后仍保留，等用户自己重新登录覆盖。
      expect(account.hasLogin, isTrue);
    });

    test('重新登录重启保活，两次独立回绝才停保活并自动退出', () async {
      final (ledger, clock) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      var started = 0;
      var lost = 0;
      var autoSignOuts = 0;
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
        ledger: ledger,
        onSessionEstablished: () => started++,
        onSessionLost: () => lost++,
        onAutoSignOut: () async => autoSignOuts++,
      );
      await account.initialize();
      expect(started, 0);
      expect(lost, 0);

      await account.importLoginCookie('pacmtoken=p1; uid=u1');
      expect(started, 1);

      // 403 可能只是这首歌没权益，不足以断定登录失效：不停保活，更不能退出。
      account.markRejected();
      expect(lost, 0);
      expect(autoSignOuts, 0);
      expect(account.status, AuthStatus.rejected);

      // 第一次账号接口回绝：只降级，凭据留着，保活照跑。
      noteAccountRejection(ledger);
      account.markSessionRevoked();
      expect(lost, 0);
      expect(autoSignOuts, 0);
      expect(account.hasLogin, isTrue);
      expect(account.status, AuthStatus.rejected);
      // 状态说明要指出到底是哪个接口回的什么，否则用户无从判断。
      expect(account.statusHint, contains('/user/h5/user-info/v1.0'));
      expect(account.statusHint, contains('HTTP 401'));

      // 隔过 confirmGap 之后再次被拒，才认定这份凭据真的作废。
      clock.advance(const Duration(minutes: 31));
      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      account.markSessionRevoked();
      expect(lost, 1);
      expect(autoSignOuts, 1);
      expect(account.autoSignOutNotice, contains('自动退出'));
      expect(account.autoSignOutNotice, contains('请先登录'));
    });

    test('凭据重新被接受后，旧的被拒记录不再算数', () async {
      final (ledger, clock) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      var autoSignOuts = 0;
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
        ledger: ledger,
        onAutoSignOut: () async => autoSignOuts++,
      );
      await account.initialize();
      await account.importLoginCookie('pacmtoken=p1; uid=u1');

      noteAccountRejection(ledger);
      expect(ledger.strikes, 1);
      account.markVerified();
      expect(ledger.strikes, 0);

      // 已经接受过一次，计数从头再来：单次回绝不该把人登出。
      clock.advance(const Duration(minutes: 40));
      noteAccountRejection(ledger);
      account.markSessionRevoked();
      expect(autoSignOuts, 0);
      expect(account.hasLogin, isTrue);
      expect(account.status, AuthStatus.rejected);
    });

    test('缺少官方登录会话时明确说明凭证不完整', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();

      await account.importLoginCookie('passID=p1; task-session-id=t1');

      expect(account.hasLogin, isTrue);
      expect(account.hasWebSessionCookie, isFalse);
      expect(account.hasIncompleteLogin, isTrue);
      expect(account.statusLabel, contains('缺少音乐登录会话'));
      expect(account.statusHint, contains('mg_auth_sid'));
    });

    test('重启后不直接采信上次的已验证状态', () async {
      final storage = FakeSecureCookieStorage();
      final firstStore = MiguCookieStore(secureStorage: storage);
      await firstStore.init();
      final authStore = AuthSessionStore(storage: storage);
      final first = AccountProvider(
        cookieStore: firstStore,
        authSessionStore: authStore,
      );
      await first.initialize();
      await first.importLoginCookie('uid=u1');
      first.markVerified();
      await Future<void>.delayed(Duration.zero);

      final restartedStore = MiguCookieStore(secureStorage: storage);
      await restartedStore.init();
      final restarted = AccountProvider(
        cookieStore: restartedStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await restarted.initialize();

      expect(restarted.status, AuthStatus.unverified);
      expect(restarted.importedAt, isNotNull);
      expect(restarted.lastCheckedAt, isNull);
    });

    test('重新登录重置失效状态', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();
      await account.importLoginCookie('uid=old');
      account.markRejected();

      await account.importLoginCookie('uid=new');

      expect(account.status, AuthStatus.unverified);
      expect(account.lastCheckedAt, isNull);
    });

    test('安全存储写不进去时登录仍可用并给出警告', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();
      storage.failWrites = true;

      await account.importLoginCookie('uid=u1');

      expect(account.hasLogin, isTrue);
      expect(account.status, AuthStatus.unverified);
      expect(account.storageWarning, isNotNull);
    });
  });

  group('退出登录只动本机', () {
    test('清除凭据、账号快照与状态记录，并停掉前台保活', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      var started = 0;
      var lost = 0;
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
        onSessionEstablished: () => started++,
        onSessionLost: () => lost++,
      );
      await account.initialize();

      await account.importLoginCookie('uid=u1; mg_auth_sid=s1');
      expect(storage.values['migu_manual_cookies_v2'], isNotNull);
      expect(storage.values[AuthSessionStore.defaultKey], isNotNull);

      await account.signOut();

      expect(account.hasLogin, isFalse);
      expect(account.cookieCount, 0);
      expect(account.status, AuthStatus.none);
      expect(account.statusLabel, '未登录');
      expect(account.displayName, '未登录');
      // 咪咕没有登出接口：这一步只能停掉保活，绝不会去请求什么登出地址。
      expect(lost, 1);
      expect(started, 1);
      // 落盘的两份东西都要真的消失，不能只改内存。
      expect(storage.values['migu_manual_cookies_v2'], isNull);
      expect(storage.values['migu_cookie_jar_v2'], isNull);
      expect(storage.values[AuthSessionStore.defaultKey], isNull);
    });

    test('两次独立回绝才自动退出，凭据出盘并留下可解释的说明', () async {
      final (ledger, clock) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      late final AccountProvider account;
      Future<void>? autoSignOut;
      account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
        ledger: ledger,
        onAutoSignOut: () async {
          autoSignOut = account.signOut();
          await autoSignOut;
        },
      );
      await account.initialize();
      await account.importLoginCookie('uid=u1; pacmtoken=old');
      expect(account.hasLogin, isTrue);

      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      account.markSessionRevoked();
      expect(account.hasLogin, isTrue);
      expect(autoSignOut, isNull);

      clock.advance(const Duration(minutes: 31));
      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      account.markSessionRevoked();
      // 闭包同步跑到第一个 await，所以这里 future 已经就位。
      await autoSignOut;

      expect(account.hasLogin, isFalse);
      expect(account.cookieCount, 0);
      expect(storage.values['migu_manual_cookies_v2'], isNull);
      expect(storage.values[AuthSessionStore.defaultKey], isNull);
      // 被系统登出必须说清楚是谁干的，不能让人以为是自己误点。
      expect(account.statusLabel, contains('已自动退出'));
      expect(account.statusHint, contains('重新登录'));
      expect(account.autoSignOutNotice, contains('咪咕已拒绝'));
      // 说明里要带上取证那行，用户才知道咪咕到底拒了什么。
      expect(account.autoSignOutNotice, contains('/user/h5/user-info/v1.0'));
      expect(account.autoSignOutNotice, contains('290001'));
      expect(ledger.last, isNull);

      // 重新登录之后，这条失效说明要跟着消失。
      await account.importLoginCookie('uid=u2; pacmtoken=new');
      expect(account.autoSignOutNotice, isNull);
      expect(account.statusLabel, isNot(contains('已自动退出')));
    });

    test('退出后重启仍是未登录，不会把旧凭据读回来', () async {
      final storage = FakeSecureCookieStorage();
      final firstCookieStore = MiguCookieStore(secureStorage: storage);
      await firstCookieStore.init();
      final first = AccountProvider(
        cookieStore: firstCookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await first.initialize();
      await first.importLoginCookie('uid=u1; pacmtoken=p1');
      await first.signOut();

      final reopenedCookieStore = MiguCookieStore(secureStorage: storage);
      await reopenedCookieStore.init();
      final reopened = AccountProvider(
        cookieStore: reopenedCookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await reopened.initialize();

      expect(reopened.hasLogin, isFalse);
      expect(reopened.status, AuthStatus.none);
      // 重启后连请求头都不该再带上任何一份旧凭据。
      expect(
        reopenedCookieStore.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        isNull,
      );
    });

    test('安全存储删不掉时本次运行仍然退出，并明确提示', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();
      await account.importLoginCookie('uid=u1');

      storage.failDeletes = true;
      await account.signOut();

      expect(account.hasLogin, isFalse);
      expect(account.cookieCount, 0);
      expect(account.storageWarning, isNotNull);
    });

    test('退出后再登录一次就能换新账号', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await account.initialize();

      await account.importLoginCookie('uid=u1; pacmtoken=old');
      await account.signOut();
      await account.importLoginCookie('uid=u2; pacmtoken=new');

      expect(account.hasLogin, isTrue);
      expect(account.cookieCount, 2);
      expect(cookieStore.credentials.pacmtoken, 'new');
      expect(
        cookieStore.cookieHeaderFor(Uri.parse('https://music.migu.cn/')),
        isNot(contains('old')),
      );
    });
  });

  group('原生登录', () {
    Future<(MiguCookieStore, AccountProvider)> provider(
      FakeSecureCookieStorage storage, {
      PassportStubAdapter? stub,
      void Function()? onEstablished,
    }) async {
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final adapter = stub ?? PassportStubAdapter();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: storage),
        passportApi: MiguPassportApi(dio: dioWith(adapter)),
        onSessionEstablished: onEstablished,
      );
      await account.initialize();
      return (cookieStore, account);
    }

    test('短信登录成功后只保存 pacmtoken，状态直接算已验证', () async {
      final storage = FakeSecureCookieStorage();
      var started = 0;
      final (cookieStore, account) = await provider(
        storage,
        onEstablished: () => started++,
      );

      // 先有一份旧账号的凭据，登录成功必须整体覆盖。
      await account.importLoginCookie('uid=old-account; mg_auth_sid=old-session');
      expect(started, 1);

      final phone = await account.signInWithSmsCode(
        phone: '13800000000',
        code: '248157',
      );

      expect(phone, '138****0000');
      expect(account.status, AuthStatus.verified);
      expect(account.lastCheckedAt, isNotNull);
      expect(account.hasLogin, isTrue);
      expect(account.hasWebSessionCookie, isTrue);
      expect(account.hasIncompleteLogin, isFalse);
      expect(cookieStore.importedCookieCount, 1);
      // 原生登录同样要重启前台保活。
      expect(started, 2);

      final saved =
          jsonDecode(storage.values['migu_manual_cookies_v2']!) as Map<String, dynamic>;
      expect(saved, {'pacmtoken': 'pacm-stub-value'});
      expect(
        cookieStore.cookieHeaderFor(Uri.parse('https://app.c.nf.migu.cn/x')),
        'pacmtoken=pacm-stub-value',
      );
    });

    test('密码登录走通同样的链路并持久化到安全存储', () async {
      final storage = FakeSecureCookieStorage();
      final adapter = PassportStubAdapter();
      final (_, account) = await provider(storage, stub: adapter);

      await account.signInWithPassword(username: '13800000000', password: 'pw-secret');

      expect(account.status, AuthStatus.verified);
      expect(adapter.paths.map((url) => Uri.parse(url).path), [
        '/password/publickey',
        '/authn',
        '/user/h5/token-validate/v3.0',
      ]);
      final json =
          jsonDecode(storage.values['migu_manual_cookies_v2']!) as Map<String, dynamic>;
      expect(json.keys, ['pacmtoken']);
      expect(storage.values.containsKey(AuthSessionStore.defaultKey), isTrue);
    });

    test('重启后仍保有登录会话', () async {
      final storage = FakeSecureCookieStorage();
      final (_, account) = await provider(storage);
      await account.signInWithSmsCode(phone: '13800000000', code: '248157');

      final restartedStore = MiguCookieStore(secureStorage: storage);
      await restartedStore.init();
      final restarted = AccountProvider(
        cookieStore: restartedStore,
        authSessionStore: AuthSessionStore(storage: storage),
      );
      await restarted.initialize();

      expect(restarted.hasLogin, isTrue);
      expect(restarted.hasWebSessionCookie, isTrue);
      // 跨重启不直接采信上次的“已验证”。
      expect(restarted.status, AuthStatus.unverified);
    });

    test('登录失败不改动已有凭据与状态', () async {
      final storage = FakeSecureCookieStorage();
      final (cookieStore, account) = await provider(
        storage,
        stub: PassportStubAdapter(networkFail: true),
      );
      await account.importLoginCookie('pacmtoken=keep-me; uid=u1');

      await expectLater(
        account.signInWithPassword(username: '13800000000', password: 'pw'),
        throwsA(isA<MiguLoginException>()),
      );

      expect(account.cookieCount, 2);
      expect(account.status, AuthStatus.unverified);
      expect(
        cookieStore.cookieHeaderFor(Uri.parse('https://app.c.nf.migu.cn/x')),
        contains('pacmtoken=keep-me'),
      );
    });

    test('验证码请求由手机号格式把关，非法输入不联网', () async {
      final storage = FakeSecureCookieStorage();
      final adapter = PassportStubAdapter();
      final (_, account) = await provider(storage, stub: adapter);

      await expectLater(
        account.requestLoginCode('1380000'),
        throwsA(isA<MiguLoginException>()),
      );
      expect(adapter.requests, isEmpty);

      await account.requestLoginCode('13800000000');
      expect(adapter.paths.map((url) => Uri.parse(url).path), [
        '/password/publickey',
        '/login/dynamicpassword',
      ]);
    });
  });

  group('通行证票据与失效判定', () {
    /// 换票与退出都是后台动作，调用方不等它们；这里把事件队列跑空。
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    AccountProvider build(
      FakeSecureCookieStorage storage,
      MiguCookieStore cookieStore,
      PassportStubAdapter adapter, {
      SessionRejectLedger? ledger,
      Future<void> Function()? onAutoSignOut,
    }) => AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: MiguPassportApi(dio: dioWith(adapter)),
      ledger: ledger,
      onAutoSignOut: onAutoSignOut,
    );

    test('原生登录把票据写进安全存储，退出与官方页面登录都会删掉', () async {
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final account = build(storage, cookieStore, PassportStubAdapter());
      await account.initialize();

      await account.signInWithSmsCode(phone: '13800000000', code: '248157');
      expect(storage.values[PassportTicketStore.defaultKey], 'STnidStubToken');

      // 换成官方页面登录：没有票据可用，旧的必须一起丢掉。
      await account.importLoginCookie('uid=u2; pacmtoken=p2');
      expect(storage.values[PassportTicketStore.defaultKey], isNull);

      await account.signInWithSmsCode(phone: '13800000000', code: '248157');
      await account.signOut();
      expect(storage.values[PassportTicketStore.defaultKey], isNull);
    });

    test('失效判定不再白发续期，两次独立回绝一定自动退出', () async {
      final (ledger, clock) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final adapter = PassportStubAdapter(
        renewCookie: 'pacmtoken=pacm-renewed; Domain=migu.cn; Path=/',
      );
      var autoSignOuts = 0;
      late final AccountProvider account;
      account = build(
        storage,
        cookieStore,
        adapter,
        ledger: ledger,
        onAutoSignOut: () async {
          autoSignOuts++;
          await account.signOut();
        },
      );
      await account.initialize();
      await account.signInWithSmsCode(phone: '13800000000', code: '248157');

      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      account.markSessionRevoked();
      await settle();

      // 只有登录那一次换票：判定失效不再顺手发一个注定失败的续期请求。
      expect(
        adapter.requests.where((r) => r.uri.path.contains('token-validate')),
        hasLength(1),
      );
      expect(account.status, AuthStatus.rejected);
      expect(account.hasLogin, isTrue);
      expect(autoSignOuts, 0);

      // 隔过取证间隔再被拒一次，两步判定必须走完：以前这一步被续期吞掉了，
      // 界面因此长期挂着死凭据，功能坏着却不退出，只能用户手动重登。
      clock.advance(const Duration(minutes: 31));
      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      account.markSessionRevoked();
      await settle();

      expect(ledger.strikes, 0);
      expect(autoSignOuts, 1);
      expect(account.hasLogin, isFalse);
      expect(cookieStore.credentials.pacmtoken, isNull);
      expect(
        adapter.requests.where((r) => r.uri.path.contains('token-validate')),
        hasLength(1),
      );
    });

    test('调试入口手动换票成功时写回新凭据、计数清零', () async {
      final (ledger, _) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final adapter = PassportStubAdapter(
        renewCookie: 'pacmtoken=pacm-renewed; Domain=migu.cn; Path=/',
      );
      final account = build(storage, cookieStore, adapter, ledger: ledger);
      await account.initialize();
      await account.signInWithSmsCode(phone: '13800000000', code: '248157');

      noteAccountRejection(ledger);
      expect(account.debugRenewNow(), '已发起一次换票');
      await settle();

      final validations = adapter.requests
          .where((request) => request.uri.path.contains('token-validate'))
          .toList();
      expect(validations, hasLength(2));
      expect(validations.last.queryParameters['token'], 'STnidStubToken');
      expect(cookieStore.credentials.pacmtoken, 'pacm-renewed');
      expect(account.status, AuthStatus.verified);
      expect(ledger.strikes, 0);
      expect(account.hasLogin, isTrue);
    });

    test('调试入口换不到凭据时只降级，凭据与票据都不动', () async {
      final (ledger, _) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      // 咪咕不认这张票据（真机就是这一档：200 + 199999，不下发新会话）。
      final adapter = PassportStubAdapter(renewCookie: '');
      final account = build(storage, cookieStore, adapter, ledger: ledger);
      await account.initialize();
      await account.signInWithSmsCode(phone: '13800000000', code: '248157');

      noteAccountRejection(ledger, code: '290001', info: '请先登录');
      expect(account.debugRenewNow(), '已发起一次换票');
      await settle();

      // 换票失败只要不是 401，就不能替服务端判死：只降级，不退登。
      expect(account.status, AuthStatus.rejected);
      expect(account.hasLogin, isTrue);
      expect(cookieStore.credentials.pacmtoken, 'pacm-stub-value');
      expect(storage.values[PassportTicketStore.defaultKey], 'STnidStubToken');
    });

    test('官方页面登录没有票据，失效只走两步判定', () async {
      final (ledger, _) = testLedger();
      final storage = FakeSecureCookieStorage();
      final cookieStore = MiguCookieStore(secureStorage: storage);
      await cookieStore.init();
      final adapter = PassportStubAdapter();
      final account = build(storage, cookieStore, adapter, ledger: ledger);
      await account.initialize();
      await account.importLoginCookie('uid=u1; mg_auth_sid=s1');

      noteAccountRejection(ledger);
      account.markSessionRevoked();
      await settle();

      expect(adapter.requests, isEmpty);
      expect(account.status, AuthStatus.rejected);
      expect(account.hasLogin, isTrue);

      // 同一份缺票据的会话，调试入口也不该碰网络。
      expect(adapter.requests, isEmpty);
      expect(account.debugRenewNow(), '本机没有留存票据，这次没试');
      await settle();
      expect(adapter.requests, isEmpty);
    });

    test('票据读写去掉空白，空值按删除处理', () async {
      final storage = FakeSecureCookieStorage();
      final store = PassportTicketStore(storage: storage);
      expect(await store.read(), isNull);

      await store.write('  ST-ticket  ');
      expect(storage.values[PassportTicketStore.defaultKey], 'ST-ticket');
      expect(await store.read(), 'ST-ticket');

      await store.write('   ');
      expect(storage.values[PassportTicketStore.defaultKey], isNull);
    });

    test('票据写入失败不会卡死队列，后续删除与写入仍会执行', () async {
      final storage = FakeSecureCookieStorage();
      final store = PassportTicketStore(storage: storage);
      await store.write('ST-old');

      storage.failWrites = true;
      await expectLater(
        store.write('ST-failed'),
        throwsA(isA<SecureCookieStorageException>()),
      );
      storage.failWrites = false;

      await store.clear();
      expect(storage.values[PassportTicketStore.defaultKey], isNull);

      await store.write('ST-new');
      expect(storage.values[PassportTicketStore.defaultKey], 'ST-new');
      expect(await store.read(), 'ST-new');
    });
  });
}
