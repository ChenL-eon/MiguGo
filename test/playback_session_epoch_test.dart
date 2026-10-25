import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/auth_session.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/api/passport_ticket_store.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/passport_stub.dart';
import 'support/reject_ledger.dart';

const _vipSong = Song(
  contentId: 'content-vip',
  copyrightId: 'copyright-vip',
  name: 'VIP 测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 200),
  isVipOnly: true,
);

/// 播放请求的响应由测试手动放行，用来把换号窗口撑在请求与回包之间。
class _GatedAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Completer<ResponseBody>> responses = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    responses.add(response);
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _Harness {
  _Harness._(
    this.storage,
    this.cookieStore,
    this.account,
    this.adapter,
    this.api,
    this.ledger,
  );

  final FakeSecureCookieStorage storage;
  final MiguCookieStore cookieStore;
  final AccountProvider account;
  final _GatedAdapter adapter;
  final MiguMusicApi api;
  final SessionRejectLedger ledger;

  static Future<_Harness> create() async {
    final storage = FakeSecureCookieStorage();
    final cookieStore = MiguCookieStore(secureStorage: storage);
    await cookieStore.init();
    final (ledger, _) = testLedger();
    final account = AccountProvider(
      cookieStore: cookieStore,
      authSessionStore: AuthSessionStore(storage: storage),
      passportTicketStore: PassportTicketStore(storage: storage),
      passportApi: MiguPassportApi(dio: dioWith(PassportStubAdapter())),
      ledger: ledger,
    );
    await account.initialize();
    await account.signInWithSmsCode(phone: '13800000000', code: '248157');

    final adapter = _GatedAdapter();
    final api = MiguMusicApi(
      client: MiguApiClient(
        dio: Dio()..httpClientAdapter = adapter,
        cookieStore: cookieStore,
        ledger: ledger,
        sessionEpoch: () => account.credentialEpoch,
        onSessionRevoked: account.markSessionRevoked,
      ),
      onAuthVerified: account.markVerified,
      onAuthRejected: account.markRejected,
      sessionEpoch: () => account.credentialEpoch,
    );
    return _Harness._(storage, cookieStore, account, adapter, api, ledger);
  }
}

ResponseBody _jsonBody(String text, int status, {String? setCookie}) {
  return ResponseBody.fromString(
    text,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (setCookie != null) 'set-cookie': [setCookie],
    },
  );
}

ResponseBody _unauthorized({String? setCookie}) =>
    _jsonBody('{"code":"290001","info":"请先登录"}', 401, setCookie: setCookie);

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

  test('换号后旧播放 401 不改新账号状态，也不写新账号证据', () async {
    final h = await _Harness.create();
    final playback = expectLater(
      h.api.resolvePlaybackUrl(_vipSong),
      throwsA(isA<MiguApiException>()),
    );
    await _pumpUntil(() => h.adapter.requests.isNotEmpty);
    expect(h.adapter.requests.single.uri.path, '/strategy/pc/listen/v2.0');

    await h.account.importLoginCookie('uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b');
    expect(h.account.status, AuthStatus.unverified);
    expect(h.ledger.last, isNull);

    h.adapter.responses.single.complete(
      _unauthorized(setCookie: 'pacmtoken=p-old; Domain=migu.cn; Path=/'),
    );
    await playback;
    await _flush();

    expect(h.account.status, AuthStatus.unverified);
    expect(h.account.hasLogin, isTrue);
    expect(h.cookieStore.credentials.pacmtoken, 'p-b');
    expect(h.cookieStore.credentials.uid, 'u-b');
    expect(h.cookieStore.loginSnapshot['mg_auth_sid'], 's-b');
    expect(h.ledger.last, isNull);
    expect(h.ledger.strikes, 0);
    expect(h.account.autoSignOutNotice, isNull);
    expect(await PassportTicketStore(storage: h.storage).read(), isNull);
  });

  test('换号后旧播放成功不把新账号标成已验证', () async {
    final h = await _Harness.create();
    final playback = h.api.resolvePlaybackUrl(_vipSong);
    await _pumpUntil(() => h.adapter.requests.isNotEmpty);

    await h.account.importLoginCookie('uid=u-b; pacmtoken=p-b; mg_auth_sid=s-b');
    expect(h.account.status, AuthStatus.unverified);

    h.adapter.responses.single.complete(
      _jsonBody(
        '{"code":"000000","info":"操作成功","data":{'
        '"url":"https://cdn.example.com/vip.mp3"}}',
        200,
      ),
    );
    expect(await playback, 'https://cdn.example.com/vip.mp3');
    await _flush();

    expect(h.account.status, AuthStatus.unverified);
    expect(h.cookieStore.credentials.pacmtoken, 'p-b');
    expect(h.ledger.last, isNull);
  });

  test('同一会话的播放 401 仍会标记失效并留下证据', () async {
    final h = await _Harness.create();
    final playback = expectLater(
      h.api.resolvePlaybackUrl(_vipSong),
      throwsA(isA<MiguApiException>()),
    );
    await _pumpUntil(() => h.adapter.requests.isNotEmpty);
    h.adapter.responses.single.complete(_unauthorized());
    await playback;
    await _flush();

    expect(h.account.status, AuthStatus.rejected);
    expect(h.ledger.last, isNotNull);
    expect(h.ledger.last!.path, '/strategy/pc/listen/v2.0');
    expect(h.ledger.last!.status, 401);
    expect(h.cookieStore.credentials.pacmtoken, 'pacm-stub-value');
  });
}
