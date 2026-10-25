import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/account_library.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/models/migu_user_profile.dart';
import 'package:migu_lele/models/playlist.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

/// 在指定的安全存储写入上挂起，用来把「落盘之后」的异步窗口撑开。
class _GatedSecureStorage extends FakeSecureCookieStorage {
  Completer<void>? writeGate;
  String? writeGateMarker;

  @override
  Future<void> write(String key, String value) async {
    final gate = writeGate;
    if (gate != null && writeGateMarker != null && value.contains(writeGateMarker!)) {
      writeGate = null;
      await gate.future;
    }
    await super.write(key, value);
  }
}

/// 资料与歌单请求由测试手动放行，登录仍走写死的通行证桩。
class _GatedMusicApi extends MiguMusicApi {
  _GatedMusicApi() : super();

  final List<Completer<MiguUserProfile>> profileRequests = [];
  final List<Completer<AccountLibrary>> libraryRequests = [];

  @override
  Future<MiguUserProfile> fetchUserProfile() {
    final request = Completer<MiguUserProfile>();
    profileRequests.add(request);
    return request.future;
  }

  @override
  Future<AccountLibrary> fetchAccountLibrary() {
    final request = Completer<AccountLibrary>();
    libraryRequests.add(request);
    return request.future;
  }
}

class _Counters {
  int established = 0;
  int lost = 0;
}

class _Harness {
  _Harness._(this.storage, this.cookieStore, this.account, this.api, this.counters);

  final _GatedSecureStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;
  final _GatedMusicApi api;
  final _Counters counters;

  static Future<_Harness> create() async {
    final storage = _GatedSecureStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    final counters = _Counters();
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: MiguPassportApi(dio: dioWith(PassportStubAdapter())),
      ledger: ledger,
      onSessionEstablished: () => counters.established++,
      onSessionLost: () => counters.lost++,
    );
    await account.initialize();
    await account.signInWithSmsCode(phone: '13800000000', code: '248157');
    return _Harness._(storage, cookieStore, account, _GatedMusicApi(), counters);
  }
}

MiguUserProfile _profile(String nickname) =>
    MiguUserProfile(nickname: nickname, userId: 'u-$nickname');

AccountLibrary _library(String id) => AccountLibrary(
  favoritePlaylist: PlaylistSummary(id: id, name: '歌单 $id'),
);

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '等待异步窗口超时');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('资料与歌单刷新绑定会话', () {
    test('旧账号资料回包不覆盖新账号，新账号刷新不被旧加载挡住', () async {
      final h = await _Harness.create();
      h.account.attachApi(h.api);

      final first = h.account.refreshProfile();
      expect(h.api.profileRequests, hasLength(1));

      await h.account.importLoginCookie('uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b');
      expect(h.api.profileRequests, hasLength(2));

      h.api.profileRequests[0].complete(_profile('账号 A'));
      await _flush();

      expect(h.account.profile, isNull);
      expect(h.account.profileLoading, isTrue);

      h.api.profileRequests[1].complete(_profile('账号 B'));
      await first;
      await _flush();

      expect(h.account.profile?.nickname, '账号 B');
      expect(h.account.profileLoading, isFalse);
      expect(h.cookieStore.credentials.pacmtoken, 'p-b');
    });

    test('旧账号歌单回包不覆盖新账号，缓存仍按新会话生效', () async {
      final h = await _Harness.create();
      h.account.attachApi(h.api);

      final first = h.account.refreshLibrary();
      expect(h.api.libraryRequests, hasLength(1));

      await h.account.importLoginCookie('uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b');
      expect(h.api.libraryRequests, hasLength(2));

      h.api.libraryRequests[0].complete(_library('list-a'));
      await _flush();

      expect(h.account.library, isNull);
      expect(h.account.libraryLoading, isTrue);

      h.api.libraryRequests[1].complete(_library('list-b'));
      await first;
      await _flush();

      expect(h.account.library?.favoritePlaylist?.id, 'list-b');
      expect(h.account.libraryLoading, isFalse);

      await h.account.refreshLibrary();
      expect(h.api.libraryRequests, hasLength(2));
    });

    test('旧账号的失败结果不污染新账号的错误状态', () async {
      final h = await _Harness.create();
      h.account.attachApi(h.api);

      final profile = h.account.refreshProfile();
      final library = h.account.refreshLibrary();
      expect(h.api.profileRequests, hasLength(1));
      expect(h.api.libraryRequests, hasLength(1));

      await h.account.importLoginCookie('uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b');
      expect(h.api.profileRequests, hasLength(2));
      expect(h.api.libraryRequests, hasLength(2));

      h.api.profileRequests[0].completeError(const MiguApiException('账号 A 资料失败'));
      h.api.libraryRequests[0].completeError(const MiguApiException('账号 A 歌单失败'));
      await _flush();

      expect(h.account.profileError, isNull);
      expect(h.account.libraryError, isNull);
      expect(h.account.profileLoading, isTrue);
      expect(h.account.libraryLoading, isTrue);

      h.api.profileRequests[1].complete(_profile('账号 B'));
      h.api.libraryRequests[1].complete(_library('list-b'));
      await profile;
      await library;
      await _flush();

      expect(h.account.profile?.nickname, '账号 B');
      expect(h.account.library?.favoritePlaylist?.id, 'list-b');
      expect(h.account.profileError, isNull);
      expect(h.account.libraryError, isNull);
      expect(h.account.profileLoading, isFalse);
      expect(h.account.libraryLoading, isFalse);
    });
  });

  group('登录流程落盘后竞态', () {
    test('官方导入在状态落盘期间退出，不触发过期的会话建立回调', () async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.storage
        ..writeGate = gate
        ..writeGateMarker = '"status":"unverified"';

      final importing = h.account.importLoginCookie(
        'uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b',
      );
      await _pumpUntil(() => h.storage.writeGate == null);
      expect(h.cookieStore.credentials.pacmtoken, 'p-b');

      // 退出的删除排在这次写入之后；放行写入，退出才能完成。
      final signOut = h.account.signOut();
      await _flush();
      gate.complete();
      await signOut;
      await importing;
      await _flush();

      expect(h.counters.established, 1);
      expect(h.counters.lost, 1);
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
    });

    test('原生登录在状态落盘期间退出，不重启保活也不恢复票据', () async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.storage
        ..writeGate = gate
        ..writeGateMarker = '"status":"verified"';

      final signing = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      await _pumpUntil(() => h.storage.writeGate == null);

      // 退出的删除排在这次写入之后；放行写入，退出才能完成。
      final signOut = h.account.signOut();
      await _flush();
      gate.complete();
      await signOut;
      await signing;
      await _flush();

      expect(h.counters.established, 1);
      expect(h.counters.lost, 1);
      expect(h.account.hasLogin, isFalse);
      expect(h.account.status, AuthStatus.none);
      expect(h.cookieStore.credentials.pacmtoken, isNull);
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
    });

    test('原生登录落盘期间被官方导入替换，旧流程不碰新会话', () async {
      final h = await _Harness.create();
      final gate = Completer<void>();
      h.storage
        ..writeGate = gate
        ..writeGateMarker = '"status":"verified"';

      final signing = h.account.signInWithSmsCode(phone: '13800000000', code: '248157');
      await _pumpUntil(() => h.storage.writeGate == null);

      final importing = h.account.importLoginCookie(
        'uid=u-c; pacmtoken=p-c; mg_auth_sid=s-c',
      );
      await _flush();
      // 导入的状态写入排在原生登录那次写入之后；放行后两份都按序落盘。
      gate.complete();
      await signing;
      await importing;
      await _flush();

      expect(h.counters.established, 2);
      expect(h.counters.lost, 0);
      expect(h.account.status, AuthStatus.unverified);
      expect(h.cookieStore.credentials.pacmtoken, 'p-c');
      expect(h.cookieStore.credentials.uid, 'u-c');
      expect(await PassportTicketStore(storage: h.storage).read(), isNull);
    });
  });
}
