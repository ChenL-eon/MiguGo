import 'dart:async';

import 'package:dio/dio.dart';

/// 1024 位测试模数：块长正好 128 字节，足以装下手机号与验证码。
final String _testModulus = 'ff' * 128;

/// 咪咕会把验证码图片直接以 data URL 下发，这里用一张自制的 1x1 PNG 冒充：
/// 字节本身可解码，widget 测试里的 `Image.memory` 才不会报错。
const String _testCaptchaUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

/// 咪咕通行证请求的假适配层：记录每一次请求，按 URL 返回预置响应。
///
/// 只返回写死的假数据，任何情况下都不会真的联网。
class PassportStubAdapter implements HttpClientAdapter {
  PassportStubAdapter({
    String? modulus,
    this.exponent = '010001',
    this.authnStatus = '2000',
    this.authnMessage = '成功',
    this.token = 'STnidStubToken',
    this.validateStatus = 200,
    this.validateCookie = 'pacmtoken=pacm-stub-value; Domain=migu.cn; Path=/; HttpOnly',
    this.renewCookie,
    this.validateBody =
        '{"code":"000000","data":{"msisdn":"138****0000","userId":"u-1"}}',
    this.riskStatus = '2000',
    this.riskMessage = '成功',
    this.riskCaptchaUrl = _testCaptchaUrl,
    this.riskGraphType = '0',
    this.riskSetCookie = 'mgnd_session_id=stub-session; Path=/; HttpOnly',
    this.checkStatus = '2000',
    this.checkMessage = '成功',
    this.networkFail = false,
  }) : modulus = modulus ?? _testModulus;

  final String modulus;
  final String exponent;
  final String authnStatus;
  final String authnMessage;
  final String token;
  final int validateStatus;
  final String validateCookie;

  /// 第二次及以后换票（也就是续期）返回的 Set-Cookie。
  /// 不传则沿用 [validateCookie]；传空串表示咪咕不认这张票据。
  final String? renewCookie;
  final String validateBody;
  final String riskStatus;
  final String riskMessage;
  final String riskCaptchaUrl;
  final String riskGraphType;
  final String riskSetCookie;
  final String checkStatus;
  final String checkMessage;
  final bool networkFail;

  final List<RequestOptions> requests = [];

  int _validateCount = 0;

  List<String> get paths => requests.map((request) => request.uri.toString()).toList();

  /// 请求里出现过的全部文本，用来确认凭据没有混进任何提示或日志。
  String get transcript => requests
      .map((request) => '${request.uri}${request.data ?? ''}${request.queryParameters}')
      .join('|');

  Map<String, String> formData(RequestOptions request) {
    final data = request.data;
    if (data is String) {
      return Uri.splitQueryString(data);
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry('$key', '$value'));
    }
    return const {};
  }

  /// 按出现顺序取回每一次登录提交用的表单，方便核对重试时带了什么。
  List<Map<String, String>> get authnForms => requests
      .where((request) => request.uri.path.startsWith('/authn'))
      .map(formData)
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (networkFail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final url = options.uri.toString();
    if (url.contains('publickey')) {
      return _json(
        '{"status":"2000","result":{"modulus":"$modulus",'
        '"publicExponent":"$exponent"}}',
      );
    }
    if (url.contains('captcha/graph/risk')) {
      return ResponseBody.fromString(
        '{"status":"$riskStatus","message":"$riskMessage",'
        '"result":{"graphtype":"$riskGraphType",'
        '"captchaurl":"$riskCaptchaUrl"}}',
        200,
        headers: {
          'content-type': [Headers.jsonContentType],
          if (riskSetCookie.isNotEmpty) 'set-cookie': [riskSetCookie],
        },
      );
    }
    if (url.contains('captcha/graph/check')) {
      return _json('{"status":"$checkStatus","message":"$checkMessage","result":{}}');
    }
    if (url.contains('token-validate')) {
      final cookie = _validateCount++ == 0 || renewCookie == null
          ? validateCookie
          : renewCookie!;
      return ResponseBody.fromString(
        validateBody,
        validateStatus,
        headers: {
          'content-type': [Headers.jsonContentType],
          if (cookie.isNotEmpty) 'set-cookie': [cookie],
        },
      );
    }
    return _json(
      '{"status":"$authnStatus","message":"$authnMessage",'
      '"result":{"token":"$token"}}',
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String text, {int status = 200}) => ResponseBody.fromString(
  text,
  status,
  headers: {
    'content-type': [Headers.jsonContentType],
  },
);

Dio dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;
