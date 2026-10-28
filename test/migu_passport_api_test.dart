import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/services/auth/migu_passport_api.dart';

import 'support/passport_stub.dart';

final RegExp _hex = RegExp(r'^[0-9a-f]+$');
final RegExp _fingerprint = RegExp(r'^[0-9a-f]{32}$');

const String _phone = '13800000000';

void main() {
  group('原生登录：账号密码', () {
    test('公钥→加密→authn→换票的顺序、来源与表单常量都符合官方网页', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      final session = await api.loginWithPassword(_phone, 'pw-secret');

      expect(stub.requests.map((request) => request.uri.path), [
        '/password/publickey',
        '/authn',
        '/user/h5/token-validate/v3.0',
      ]);
      expect(stub.requests.first.uri.host, 'passport.migu.cn');
      expect(stub.requests.last.uri.host, 'c.musicapp.migu.cn');

      final authn = stub.requests[1];
      expect(authn.headers['Referer'], AppConstants.passportReferer);
      expect(authn.headers['Origin'], 'https://passport.migu.cn');
      expect(authn.contentType, Headers.formUrlEncodedContentType);

      final form = stub.formData(authn);
      expect(form['isAsync'], 'true');
      expect(form['sourceID'], AppConstants.passportSourceId);
      expect(form['imgcodeType'], '1');
      expect(form['appType'], '0');
      expect(form['relayState'], '');
      expect(form['captcha'], '');
      expect(form['loginID'], matches(_hex));
      expect(form['enpassword'], matches(_hex));
      expect(form['fingerPrint'], matches(_fingerprint));
      expect(form['fingerPrintDetail'], form['fingerPrint']);

      final validate = stub.requests[2];
      expect(validate.queryParameters['token'], 'STnidStubToken');
      expect(validate.queryParameters['type'], '2');
      expect(validate.queryParameters['sourceId'], AppConstants.passportSourceId);
      expect(validate.queryParameters['activityId'], AppConstants.passportActivityId);
      expect(
        validate.headers['Cookie'],
        'idmpauth=true@passport.migu.cn',
        reason: '不带这条声明时咪咕不发放音乐站会话',
      );
      expect(validate.headers['Referer'], AppConstants.miguReferer);
      expect(validate.headers['Origin'], 'https://music.migu.cn');

      expect(session.cookies, {'pacmtoken': 'pacm-stub-value'});
      expect(session.maskedPhone, '138****0000');
      expect(session.userId, 'u-1');

      // 密码只在加密块里出现，任何请求原文都不该带上它。
      expect(stub.transcript, isNot(contains('pw-secret')));
    });

    test('每次登录重新取公钥，不复用上一次的结果', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));
      await api.loginWithPassword(_phone, 'pw-1');
      await api.loginWithPassword(_phone, 'pw-2');

      expect(stub.paths.where((url) => url.contains('publickey')), hasLength(2));
    });

    test('咪咕拒绝时提示里带状态码，但不带密码', () async {
      final stub = PassportStubAdapter(authnStatus: '0063', authnMessage: '用户名或密码错误');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            allOf(contains('0063'), isNot(contains('pw-secret'))),
          ),
        ),
      );
      expect(stub.paths.any((url) => url.contains('token-validate')), isFalse);
    });

    test('被要求图形验证码时标记 captchaRequired 并停止后续换票', () async {
      final stub = PassportStubAdapter(authnStatus: '0071', authnMessage: '请输入图片验证码');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.captchaRequired,
            'captchaRequired',
            isTrue,
          ),
        ),
      );
      expect(stub.requests, hasLength(2));
    });

    test('账号或密码为空时不联网', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword('  ', 'pw'),
        throwsA(isA<MiguLoginException>()),
      );
      await expectLater(
        api.loginWithPassword('13800000000', ''),
        throwsA(isA<MiguLoginException>()),
      );
      expect(stub.requests, isEmpty);
    });
  });

  group('原生登录：短信验证码', () {
    test('发码用 GET，登录用 POST，两次共用同一份伪造指纹', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub), random: Random(20261022));

      await api.sendSmsCode(_phone);
      await api.loginWithSmsCode(_phone, '248157');

      expect(stub.requests, hasLength(5));
      expect(stub.requests[0].uri.path, '/password/publickey');
      expect(stub.requests[2].uri.path, '/password/publickey');

      final send = stub.requests[1];
      expect(send.method, 'GET');
      expect(send.uri.path, '/login/dynamicpassword');
      expect(send.queryParameters['imgcodeType'], '2');
      expect(send.queryParameters['captcha'], '');
      expect(send.queryParameters['sourceID'], AppConstants.passportSourceId);
      expect(send.queryParameters['msisdn'], matches(_hex));
      expect(send.queryParameters['fingerPrint'], matches(_fingerprint));

      final authn = stub.requests[3];
      expect(authn.method, 'POST');
      expect(authn.uri.path, '/authn/dynamicpassword');
      final form = stub.formData(authn);
      expect(form['imgcodeType'], '2');
      expect(form['appType'], '');
      expect(form['securityCode'], '7619');
      expect(form['msisdn'], matches(_hex));
      expect(form['dynamicPassword'], matches(_hex));
      expect(form['fingerPrint'], send.queryParameters['fingerPrint']);
      expect(stub.requests[4].uri.path, '/user/h5/token-validate/v3.0');

      // 验证码只以加密块的形式出现在请求里。
      expect(stub.transcript, isNot(contains('248157')));
      expect(stub.transcript, isNot(contains(_phone)));
    });

    test('验证码格式不正确或手机号非法时不联网', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithSmsCode(_phone, 'abc'),
        throwsA(isA<MiguLoginException>()),
      );
      await expectLater(
        api.sendSmsCode('1234567890a'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            contains('手机号'),
          ),
        ),
      );
      expect(stub.requests, isEmpty);
    });

    test('发码失败按咪咕状态提示，不泄露手机号', () async {
      final stub = PassportStubAdapter(authnStatus: '0100', authnMessage: '今日发送次数已达上限');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.sendSmsCode(_phone),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            allOf(contains('0100'), isNot(contains(_phone))),
          ),
        ),
      );
    });

    test('发码触发风控时被识别为需要图形验证码', () async {
      final stub = PassportStubAdapter(authnStatus: '0071', authnMessage: '请先输入图形验证码');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.sendSmsCode(_phone),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.captchaRequired,
            'captchaRequired',
            isTrue,
          ),
        ),
      );
      expect(stub.requests, hasLength(2));
    });
  });

  group('原生登录：图形验证码', () {
    test('取图带 imgcodeType 与 showType，返回的是解好码的图片字节', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      final first = await api.fetchGraphCaptcha(MiguImgcodeType.sms);
      final second = await api.fetchGraphCaptcha(
        MiguImgcodeType.password,
        refresh: true,
      );

      final risk = stub.requests.first;
      expect(risk.uri.host, 'passport.migu.cn');
      expect(risk.uri.path, '/captcha/graph/risk');
      expect(risk.queryParameters['imgcodeType'], '2');
      expect(risk.queryParameters['showType'], '0');
      expect(risk.queryParameters['sourceid'], AppConstants.passportSourceId);
      expect(first.graphType, '0');
      expect(
        first.image.first,
        0x89,
        reason: 'data URL 里的 base64 已还原成图片字节，界面直接交给 Image.memory',
      );
      expect(first.image.length, greaterThan(60));

      // 「换一张」与官方页面一样用 showType=1，两种登录方式各自编号。
      expect(stub.requests.last.queryParameters['imgcodeType'], '1');
      expect(stub.requests.last.queryParameters['showType'], '1');
      expect(second.image, first.image);
    });

    test('取图得到的通行证会话 Cookie 会一路带回登录，但不进音乐站', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      await api.fetchGraphCaptcha(MiguImgcodeType.sms);
      await api.verifyGraphCaptcha(MiguImgcodeType.sms, '7k2m');
      await api.loginWithSmsCode(_phone, '248157', captcha: '7k2m');

      expect(stub.requests.map((request) => request.uri.path), [
        '/captcha/graph/risk',
        '/captcha/graph/check',
        '/password/publickey',
        '/authn/dynamicpassword',
        '/user/h5/token-validate/v3.0',
      ]);
      // 答案记在这份会话上，少带一次就等于重新回答；取图那次还没有会话。
      for (final request in stub.requests.skip(1).take(3)) {
        expect(
          request.headers['Cookie'],
          contains('mgnd_session_id=stub-session'),
          reason: request.uri.path,
        );
      }
      expect(
        stub.requests.last.headers['Cookie'],
        'idmpauth=true@passport.migu.cn',
        reason: '换票只声明通行证已认证，不携带验证码会话',
      );
    });

    test('校验答案用 GET 明文提交', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      await api.verifyGraphCaptcha(MiguImgcodeType.password, ' 7k2m ');

      final check = stub.requests.first;
      expect(check.method, 'GET');
      expect(check.uri.path, '/captcha/graph/check');
      expect(check.queryParameters['captcha'], '7k2m');
      expect(check.queryParameters['imgcodeType'], '1');
      expect(check.queryParameters['sourceid'], AppConstants.passportSourceId);
    });

    test('没填字符时不联网，直接要求补填', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.verifyGraphCaptcha(MiguImgcodeType.sms, '  '),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.captchaRequired,
            'captchaRequired',
            isTrue,
          ),
        ),
      );
      expect(stub.requests, isEmpty);
    });

    test('咪咕判错时提示换一张，仍然要用户重答', () async {
      final stub = PassportStubAdapter(checkStatus: '4002', checkMessage: '验证码错误或已失效');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.verifyGraphCaptcha(MiguImgcodeType.sms, 'zzzz'),
        throwsA(
          isA<MiguLoginException>()
              .having((error) => error.captchaRequired, 'captchaRequired', isTrue)
              .having((error) => error.message, 'message', contains('换一张')),
        ),
      );
    });

    test('图片解不开时承认做不到，交给官方页面', () async {
      final stub = PassportStubAdapter(riskCaptchaUrl: '');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.fetchGraphCaptcha(MiguImgcodeType.sms),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.officialOnly,
            'officialOnly',
            isTrue,
          ),
        ),
      );
    });

    test('用户照图输入的字符随发码与登录一起提交', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub), random: Random(20261022));

      await api.sendSmsCode(_phone, captcha: '7k2m');
      expect(stub.requests.last.queryParameters['captcha'], '7k2m');

      await api.loginWithPassword(_phone, 'pw-secret', captcha: ' 9x ');
      final form = stub.authnForms.single;
      expect(form['captcha'], '9x');
      expect(form['enpassword'], matches(_hex));
      // 图形验证码是明文，密码与短信码依旧只以加密块出现。
      expect(stub.transcript, isNot(contains('pw-secret')));
    });
  });

  group('原生登录：会话交换与异常', () {
    test('没有 pacmtoken 时不写入会话，也不回显票据', () async {
      final stub = PassportStubAdapter(validateCookie: '');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            allOf(contains('音乐站登录凭据'), isNot(contains('STnidStubToken'))),
          ),
        ),
      );
    });

    test('换票被服务端拒绝时提示状态码', () async {
      final stub = PassportStubAdapter(validateStatus: 503);
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            allOf(contains('503'), isNot(contains('pw-secret'))),
          ),
        ),
      );
    });

    test('公钥响应缺字段时给出可读提示', () async {
      final stub = _BrokenKeyStub();
      final api = MiguPassportApi(dio: Dio()..httpClientAdapter = stub);

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            contains('公钥'),
          ),
        ),
      );
    });

    test('网络不通时统一提示检查网络', () async {
      final stub = PassportStubAdapter(networkFail: true);
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.loginWithPassword(_phone, 'pw-secret'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            contains('网络'),
          ),
        ),
      );
    });
  });

  group('会话续期', () {
    test('用留存票据再换一次会话，票据随结果原样带回', () async {
      final stub = PassportStubAdapter();
      final api = MiguPassportApi(dio: dioWith(stub));

      final session = await api.renewSession('STnidStubToken');

      final request = stub.requests.single;
      expect(request.uri.path, '/user/h5/token-validate/v3.0');
      expect(request.queryParameters['token'], 'STnidStubToken');
      expect(request.queryParameters['type'], '2');
      expect(request.queryParameters['sourceId'], AppConstants.passportSourceId);
      expect(request.queryParameters['activityId'], AppConstants.passportActivityId);
      expect(request.headers['Cookie'], 'idmpauth=true@passport.migu.cn');
      expect(session.cookies, {'pacmtoken': 'pacm-stub-value'});
      expect(session.token, 'STnidStubToken');
    });

    test('票据不被接受时给出续期专属提示，且不回显票据', () async {
      final stub = PassportStubAdapter(validateCookie: '');
      final api = MiguPassportApi(dio: dioWith(stub));

      await expectLater(
        api.renewSession('STnidStubToken'),
        throwsA(
          isA<MiguLoginException>().having(
            (error) => error.message,
            'message',
            allOf(contains('没有接受'), isNot(contains('STnidStubToken'))),
          ),
        ),
      );
    });

    test('200 不发凭据时记下业务码，字段名只认 status 会读成空', () async {
      // 真机续期就是这一档：HTTP 200、不下发 Set-Cookie。
      final api = MiguPassportApi(
        dio: dioWith(
          PassportStubAdapter(
            validateCookie: '',
            validateBody: '{"code":"199999","message":"系统繁忙"}',
          ),
        ),
      );

      final error = await _renewalError(api);

      expect(error.httpStatus, 200);
      expect(error.officialCode, '199999');
      expect(error.bodyHint, '');
      expect(error.transient, isTrue);
    });

    test('读不出业务码时记下回包形态，服务端原文一律不进记录', () async {
      final html = await _renewalError(
        MiguPassportApi(dio: dioWith(_PlainBodyStub('<html>风控拦截</html>'))),
      );
      expect(html.httpStatus, 200);
      expect(html.officialCode, '');
      expect(html.bodyHint, '非 JSON');
      expect(html.message, isNot(contains('风控拦截')));

      final empty = await _renewalError(
        MiguPassportApi(dio: dioWith(_PlainBodyStub('   '))),
      );
      expect(empty.bodyHint, '空回包');
    });
  });
}

Future<MiguLoginException> _renewalError(MiguPassportApi api) async {
  try {
    await api.renewSession('STnidStubToken');
  } on MiguLoginException catch (error) {
    return error;
  }
  throw StateError('续期没有按预期失败');
}

/// 回一份不是 JSON 的正文：内容类型不对时 dio 不解码，正好用来测形态识别。
class _PlainBodyStub implements HttpClientAdapter {
  _PlainBodyStub(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['text/plain; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BrokenKeyStub implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"status":"2000","result":{}}',
      200,
      headers: {
        'content-type': [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
