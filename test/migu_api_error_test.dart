import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/audio_quality.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_api_exception.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/api/migu_response_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _vipSong = Song(
  contentId: 'content-vip',
  copyrightId: 'copyright-vip',
  name: 'VIP 测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 200),
  isVipOnly: true,
);

const _freeSong = Song(
  contentId: 'content-free',
  copyrightId: 'copyright-free',
  name: '免费测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 180),
  isVipOnly: false,
);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String text, int status, {Map<String, List<String>>? headers}) {
  return ResponseBody.fromString(
    text,
    status,
    headers:
        headers ??
        {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
  );
}

/// 按站点格式把 JSON 封成播放策略接口返回的响应体。
ResponseBody _sealedBody(String text, {int status = 200, int offset = 91}) {
  final key = utf8.encode(MiguResponseCipher.productionKey);
  final plain = utf8.encode(text);
  final bytes = <int>[0xAB, 0xCD, 1, offset];
  for (var i = 0; i < plain.length; i++) {
    bytes.add((plain[i] - offset + key[i % key.length]) & 0xFF);
  }
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<MiguCookieStore> createCookieStore() async {
    final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
    await store.init();
    return store;
  }

  group('通用接口错误分类', () {
    Future<MiguApiException> captureError(int status, String body) async {
      final adapter = _FakeAdapter((_) => _body(body, status));
      final dio = Dio()..httpClientAdapter = adapter;
      final client = MiguApiClient(dio: dio, cookieStore: await createCookieStore());
      try {
        await client.getJson('https://app.u.nf.migu.cn/test');
        fail('应当抛出 MiguApiException');
      } on MiguApiException catch (error) {
        return error;
      }
    }

    test('401 识别为需要重新登录', () async {
      final error = await captureError(401, '{}');
      expect(error.kind, MiguErrorKind.authRequired);
      expect(error.loginRequired, isTrue);
      expect(error.canRelogin, isTrue);
    });

    test('403 识别为可能失效或无权限', () async {
      final error = await captureError(403, '{}');
      expect(error.kind, MiguErrorKind.authRejected);
      expect(error.permissionDenied, isTrue);
      expect(error.message, contains('可能已失效'));
    });

    test('429 识别为限流', () async {
      final error = await captureError(429, '{}');
      expect(error.kind, MiguErrorKind.rateLimited);
      expect(error.message, contains('限流'));
    });

    test('5xx 识别为服务端错误', () async {
      final error = await captureError(503, '{}');
      expect(error.kind, MiguErrorKind.server);
    });

    test('连接超时映射为 timeout', () async {
      final adapter = _FakeAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = MiguApiClient(dio: dio, cookieStore: await createCookieStore());

      try {
        await client.getJson('https://app.u.nf.migu.cn/test');
        fail('应当抛出 MiguApiException');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.timeout);
      }
    });

    test('断网映射为 network', () async {
      final adapter = _FakeAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final client = MiguApiClient(dio: dio, cookieStore: await createCookieStore());

      try {
        await client.getJson('https://app.u.nf.migu.cn/test');
        fail('应当抛出 MiguApiException');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.network);
      }
    });
  });

  group('播放地址与认证回调', () {
    test('未导入凭据的 VIP 歌曲直接提示登录，不发起网络请求', () async {
      final adapter = _FakeAdapter((_) => _body('{}', 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final client = MiguApiClient(dio: dio, cookieStore: await createCookieStore());
      final api = MiguMusicApi(client: client);

      try {
        await api.resolvePlaybackUrl(_vipSong);
        fail('应当抛出无法播放异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.playbackUnavailable);
        expect(error.loginRequired, isTrue);
        expect(error.message, contains('VIP 专享'));
        expect(error.message, contains('账号入口'));
        expect(error.message, isNot(contains('pacmtoken')));
      }
      expect(adapter.requests, isEmpty);
    });

    test('VIP 播放使用账号凭据走播放策略接口，并标记为已验证', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies(
        'mg_auth_uid=u1; pacmtoken=p1; mg_auth_msisdn=13800000000',
      );
      final adapter = _FakeAdapter(
        (_) => _sealedBody(
          '{"code":"000000","info":"操作成功","data":{'
          '"url":"https://cdn.example.com/vip.mp3","audioFormatType":"HQ"}}',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = MiguApiClient(dio: dio, cookieStore: cookieStore);
      var verified = 0;
      var rejected = 0;
      final api = MiguMusicApi(
        client: client,
        onAuthVerified: () => verified++,
        onAuthRejected: () => rejected++,
      );

      final url = await api.resolvePlaybackUrl(_vipSong);

      expect(url, 'https://cdn.example.com/vip.mp3');
      expect(verified, 1);
      expect(rejected, 0);
      final request = adapter.requests.single;
      expect(request.uri.path, '/strategy/pc/listen/v2.0');
      expect(request.uri.queryParameters['toneFlag'], 'HQ');
      expect(request.uri.queryParameters['copyrightId'], 'copyright-vip');
      expect(request.headers['signature'], '1');
      expect(request.headers['uid'], 'u1');
      expect(request.headers['pacmtoken'], 'p1');
      expect(request.headers['msisdn'], '13800000000');
      expect(request.headers['Cookie'], contains('pacmtoken=p1'));
    });

    test('VIP 的 HQ 没有地址时回退 PQ', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (options) => options.uri.queryParameters['toneFlag'] == 'PQ'
            ? _sealedBody(
                '{"code":"000000","data":{'
                '"url":"https://cdn.example.com/pq.mp3"}}',
              )
            : _sealedBody(
                '{"code":"000000","data":{"cannotCode":"440022",'
                '"dialogInfo":{"text":"会员专属音质，请先登录"}}}',
              ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
      );

      final url = await api.resolvePlaybackUrl(_vipSong);

      expect(url, 'https://cdn.example.com/pq.mp3');
      expect(adapter.requests.map((r) => r.uri.queryParameters['toneFlag']), [
        'HQ',
        'PQ',
      ]);
      expect(verified, 1);
    });

    test('VIP 的至臻直发时按 ZQ24 请求并采用地址', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (_) => _sealedBody(
          '{"code":"000000","data":{'
          '"url":"https://cdn.example.com/zq24.flac","audioFormatType":"ZQ24"}}',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
      );

      final url = await api.resolvePlaybackUrl(_vipSong, quality: AudioQuality.zq24);

      expect(url, 'https://cdn.example.com/zq24.flac');
      expect(adapter.requests.single.uri.queryParameters['toneFlag'], 'ZQ24');
      expect(verified, 1);
    });

    test('VIP 的 ZQ24 被服务端拒绝后回退 SQ', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (options) => options.uri.queryParameters['toneFlag'] == 'SQ'
            ? _sealedBody(
                '{"code":"000000","data":{'
                '"url":"https://cdn.example.com/sq.flac","audioFormatType":"SQ"}}',
              )
            : _sealedBody(
                '{"code":"000000","data":{"cannotCode":"440008",'
                '"dialogInfo":{"text":"应版权方要求，该高品质音乐开通会员后即可无限畅享"}}}',
              ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
      );

      final url = await api.resolvePlaybackUrl(_vipSong, quality: AudioQuality.zq24);

      expect(url, 'https://cdn.example.com/sq.flac');
      expect(adapter.requests.map((r) => r.uri.queryParameters['toneFlag']), [
        'ZQ24',
        'SQ',
      ]);
      expect(verified, 1);
    });

    test('服务端把 ZQ24 静默降为 SQ 时仍采用可用地址', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (_) => _sealedBody(
          '{"code":"000000","data":{'
          '"url":"https://cdn.example.com/sq.flac","audioFormatType":"SQ"}}',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
      );

      final url = await api.resolvePlaybackUrl(_vipSong, quality: AudioQuality.zq24);

      expect(url, 'https://cdn.example.com/sq.flac');
      expect(adapter.requests.single.uri.queryParameters['toneFlag'], 'ZQ24');
    });

    test('免费曲目选择至臻时走策略接口但不标记账号已验证', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (_) => _sealedBody(
          '{"code":"000000","data":{'
          '"url":"https://cdn.example.com/free-zq24.flac",'
          '"audioFormatType":"ZQ24"}}',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
      );

      final url = await api.resolvePlaybackUrl(_freeSong, quality: AudioQuality.zq24);

      expect(url, 'https://cdn.example.com/free-zq24.flac');
      final request = adapter.requests.single;
      expect(request.uri.path, '/strategy/pc/listen/v2.0');
      expect(request.uri.queryParameters['toneFlag'], 'ZQ24');
      expect(verified, 0);
    });

    test('VIP 接口不发放地址时转述服务端文案，不标记登录失效', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter(
        (_) => _sealedBody(
          '{"code":"000000","data":{"cannotCode":"440022",'
          '"dialogInfo":{"text":"会员专属音质，请先登录"}}}',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      var rejected = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
        onAuthRejected: () => rejected++,
      );

      try {
        await api.resolvePlaybackUrl(_vipSong);
        fail('应当抛出权限异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.permissionDenied);
        expect(error.permissionDenied, isTrue);
        expect(error.loginRequired, isTrue);
        expect(error.message, contains('会员专属音质'));
        expect(error.message, isNot(contains('可能已失效')));
      }
      expect(adapter.requests.length, 2);
      expect(verified, 0);
      expect(rejected, 0);
    });

    test('免费歌曲成功不会误判为已验证', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('uid=u1');
      final adapter = _FakeAdapter(
        (_) => _body('{"url":"https://cdn.example.com/free.mp3"}', 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
      );

      final url = await api.resolvePlaybackUrl(_freeSong);

      expect(url, 'https://cdn.example.com/free.mp3');
      expect(verified, 0);
    });

    test('VIP 请求被 403 拒绝时只说明权益，不翻转登录状态', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('pacmtoken=p1; uid=u1');
      final adapter = _FakeAdapter((_) => _body('{}', 403));
      final dio = Dio()..httpClientAdapter = adapter;
      var verified = 0;
      var rejected = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthVerified: () => verified++,
        onAuthRejected: () => rejected++,
      );

      try {
        await api.resolvePlaybackUrl(_vipSong);
        fail('应当抛出权限异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.permissionDenied);
        expect(error.permissionDenied, isTrue);
        expect(error.canRelogin, isTrue);
        expect(error.message, contains('权益'));
        expect(error.message, isNot(contains('可能已失效')));
      }
      expect(verified, 0);
      expect(rejected, 0);
    });

    test('本机 Cookie 缺少登录凭据时说明原因，不误报登录失效', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('passID=p1; task-session-id=t1');
      final adapter = _FakeAdapter((_) => _body('{}', 200));
      final dio = Dio()..httpClientAdapter = adapter;
      var rejected = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthRejected: () => rejected++,
      );

      expect(api.hasWebSessionCookie, isFalse);
      try {
        await api.resolvePlaybackUrl(_vipSong);
        fail('应当抛出无法播放异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.playbackUnavailable);
        expect(error.message, contains('账号入口'));
        expect(error.message, isNot(contains('pacmtoken')));
        expect(error.message, isNot(contains('可能已失效')));
      }
      expect(adapter.requests, isEmpty);
      expect(rejected, 0);
    });

    test('免费曲目返回 200002 时说明是音源问题', () async {
      final adapter = _FakeAdapter(
        (_) => _body('{"code":"200002","info":"PE参数格式错误"}', 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: await createCookieStore()),
      );

      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出无法播放异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.playbackUnavailable);
        expect(error.message, contains('免费音源'));
      }
    });

    test('带凭据的 401 无论歌曲类型都标记为已失效', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('uid=u1');
      final adapter = _FakeAdapter((_) => _body('{}', 401));
      final dio = Dio()..httpClientAdapter = adapter;
      var rejected = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthRejected: () => rejected++,
      );

      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出认证异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.authRejected);
      }
      expect(rejected, 1);
    });

    test('免费歌曲 403 不误判登录失效', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('uid=u1');
      final adapter = _FakeAdapter((_) => _body('{}', 403));
      final dio = Dio()..httpClientAdapter = adapter;
      var rejected = 0;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
        onAuthRejected: () => rejected++,
      );

      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出权限异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.permissionDenied);
      }
      expect(rejected, 0);
    });

    test('播放请求 429 与 5xx 分别映射限流与服务端错误', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('uid=u1');
      var status = 429;
      final adapter = _FakeAdapter((_) => _body('{}', status));
      final dio = Dio()..httpClientAdapter = adapter;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
      );

      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出限流异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.rateLimited);
      }

      status = 502;
      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出服务端异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.server);
      }
    });

    test('网络断开时播放错误保持 network 分类', () async {
      final cookieStore = await createCookieStore();
      await cookieStore.importLoginCookies('uid=u1');
      final adapter = _FakeAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final api = MiguMusicApi(
        client: MiguApiClient(dio: dio, cookieStore: cookieStore),
      );

      try {
        await api.resolvePlaybackUrl(_freeSong);
        fail('应当抛出网络异常');
      } on MiguApiException catch (error) {
        expect(error.kind, MiguErrorKind.network);
        expect(error.canRelogin, isFalse);
      }
    });
  });
}
