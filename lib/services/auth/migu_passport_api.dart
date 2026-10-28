import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import 'migu_rsa.dart';

/// 原生登录失败。
///
/// [message] 只包含我们自己组织的中文提示与咪咕返回的状态码，
/// 绝不包含密码、验证码、票据或 Cookie 值。
class MiguLoginException implements Exception {
  const MiguLoginException(
    this.message, {
    this.captchaRequired = false,
    this.officialOnly = false,
    this.networkInterrupted = false,
    this.transient = false,
    this.httpStatus,
    this.officialCode = '',
    this.bodyHint = '',
  });

  final String message;

  /// 换票请求的 HTTP 状态，只给调试记录读，不进界面文案。
  final int? httpStatus;

  /// 咪咕回包里的业务码（如 `199999`）；只有码，不含它的提示文案。
  ///
  /// 换票接口的文案可能夹带请求内容本身，所以一路只取码、不取原文。
  final String officialCode;

  /// 回包读不出业务码时的形态（`非 JSON` / `空回包` / `JSON 里没有码`）。
  ///
  /// 真机曾连续三次续期只读得出 `HTTP 200`、码是空的，事后查明是键名只认
  /// `status`；留这一笔是为了那种什么都读不出的回包至少还能分得开。
  final String bodyHint;

  /// 咪咕要求先过图形验证码：界面应显示验证码图片与输入框，由用户本人识别。
  final bool captchaRequired;

  /// 咪咕这次要的是滑块等我们无法呈现的验证：只能交给官方页面。
  final bool officialOnly;

  /// 请求根本没到达咪咕（连接失败、超时、域名解析）。
  ///
  /// 上层要把它和“咪咕明确回绝”分开：没问到结果就不能当成凭据作废的证据，
  /// 否则弱网里凑够两次取证会把用户永久登出。
  final bool networkInterrupted;

  /// 咪咕答了，但答案暂时不能用来判定票据作废。
  ///
  /// `token-validate` 对失效票据也可能回 HTTP 200 + 业务码 `199999 系统繁忙`；
  /// 5xx、429、403 与缺少 `pacmtoken` 的 2xx 同样分不清是票据问题还是服务抖动。
  /// 这类失败只能把状态降级，不能替用户确认“凭据已作废”。
  final bool transient;

  @override
  String toString() => 'MiguLoginException: $message';
}

/// 图形验证码归属的登录方式；取值与官方页面一致（1=账号密码，2=短信）。
enum MiguImgcodeType { password, sms }

/// 一张从咪咕取回的图形验证码。
class MiguGraphCaptcha {
  const MiguGraphCaptcha({required this.image, required this.graphType});

  /// 已解码的 JPEG 字节，直接交给 `Image.memory` 显示。
  final Uint8List image;

  /// 咪咕标注的验证形式，`0` 是普通图形验证码。
  final String graphType;
}

/// 登录成功后本机需要保存的会话。
class MiguLoginSession {
  const MiguLoginSession({
    required this.cookies,
    this.maskedPhone,
    this.userId,
    this.token,
  });

  /// 需要写入本机凭据的 Cookie；目前只有取链用的 `pacmtoken`。
  final Map<String, String> cookies;

  /// 咪咕返回的打码手机号，仅用于界面确认“登录成了哪个账号”。
  final String? maskedPhone;

  final String? userId;

  /// 通行证签发的登录票据，只留在本机安全存储里，不随任何普通请求发送。
  /// 它在换出本次会话的那一次请求里就用掉了，换不来第二个会话，
  /// 本机留着只给调试入口复测（`AccountProvider.debugRenewNow`）。
  final String? token;
}

/// 咪咕通行证原生登录：账号密码、短信验证码，以及用票据换音乐站会话。
///
/// 这里**不复用**全局网络层：登录请求必须干净，不能带上本机旧的 `pacmtoken`
/// 或统计 Cookie，否则一次失败的登录会把已有会话一起污染掉。
class MiguPassportApi {
  MiguPassportApi({Dio? dio, Random? random})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': AppConstants.userAgent,
                'Accept': 'application/json, text/plain, */*',
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
              },
            ),
          ),
      _random = random ?? Random.secure() {
    _fingerprint = _randomFingerprint();
  }

  static final RegExp _cnMobile = RegExp(r'^1[3-9]\d{9}$');

  final Dio _dio;
  final Random _random;

  /// 通行证把图形验证码的答案记在 `mgnd_session_id` 这类会话 Cookie 上，
  /// 取图、校验与随后的登录必须带上同一份，否则校验必然不通过。
  /// 只发给通行证域名，不会带进音乐站的任何请求；换到音乐站会话后当场清空。
  final Map<String, String> _passportCookies = {};

  /// 一次登录会话共用同一个伪造指纹：官方页面里它是浏览器指纹，发码与校验
  /// 两次请求取值不同反而更容易被风控判定为异常。
  late final String _fingerprint;

  String _randomFingerprint() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// 发送短信验证码。[captcha] 是用户照图输入的图形验证码，未被风控时留空。
  Future<void> sendSmsCode(String phone, {String captcha = ''}) async {
    _requirePhone(phone);
    final key = await _publicKey();
    final query = {
      'isAsync': 'true',
      'msisdn': _encrypt(phone, key),
      'captcha': captcha.trim(),
      'sourceID': AppConstants.passportSourceId,
      'imgcodeType': '2',
      'fingerPrint': _fingerprint,
      'fingerPrintDetail': _fingerprint,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final body = await _request(
      () => _dio.get<dynamic>(
        AppConstants.passportSmsSendUrl,
        queryParameters: query,
        options: _passportOptions(),
      ),
    );
    _requireSuccess(body, '验证码发送失败');
  }

  /// 短信验证码登录，成功后换取并返回本机需要保存的会话凭据。
  Future<MiguLoginSession> loginWithSmsCode(
    String phone,
    String code, {
    String captcha = '',
  }) async {
    _requirePhone(phone);
    final trimmed = code.trim();
    if (!_isNumericCode(trimmed)) {
      throw const MiguLoginException('请输入短信验证码。');
    }
    final key = await _publicKey();
    final form = {
      'isAsync': 'true',
      'msisdn': _encrypt(phone, key),
      'dynamicPassword': _encrypt(trimmed, key),
      'captcha': captcha.trim(),
      'appType': '',
      // 通行证页对短信登录固定携带该安全码，属于站点自身的表单常量。
      'securityCode': '7619',
      'sourceID': AppConstants.passportSourceId,
      'imgcodeType': '2',
      'fingerPrint': _fingerprint,
      'fingerPrintDetail': _fingerprint,
    };

    final body = await _request(
      () => _dio.post<dynamic>(
        AppConstants.passportSmsAuthnUrl,
        data: form,
        options: _passportOptions(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    _requireSuccess(body, '登录失败');
    return _exchangeToken(_readToken(body), method: '短信验证码');
  }

  /// 账号密码登录。密码只在本次请求里加密传输，本机不做任何保存。
  Future<MiguLoginSession> loginWithPassword(
    String username,
    String password, {
    String captcha = '',
  }) async {
    final account = username.trim();
    if (account.isEmpty || password.isEmpty) {
      throw const MiguLoginException('请填写账号和密码。');
    }
    final key = await _publicKey();
    final form = {
      'isAsync': 'true',
      'loginID': _encrypt(account, key),
      'enpassword': _encrypt(password, key),
      'captcha': captcha.trim(),
      'appType': '0',
      // 直连通行证时官方页面就传空串；回跳地址由网页流程使用，这里不需要。
      'relayState': '',
      'sourceID': AppConstants.passportSourceId,
      'imgcodeType': '1',
      'fingerPrint': _fingerprint,
      'fingerPrintDetail': _fingerprint,
    };

    final body = await _request(
      () => _dio.post<dynamic>(
        AppConstants.passportPasswordAuthnUrl,
        data: form,
        options: _passportOptions(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    _requireSuccess(body, '账号或密码不正确');
    return _exchangeToken(_readToken(body), method: '账号密码');
  }

  /// 取一张图形验证码。[refresh] 对应官方页面的「换一张」。
  Future<MiguGraphCaptcha> fetchGraphCaptcha(
    MiguImgcodeType type, {
    bool refresh = false,
  }) async {
    final body = await _request(
      () => _dio.get<dynamic>(
        AppConstants.passportCaptchaRiskUrl,
        queryParameters: {
          'imgcodeType': _imgcodeTypeValue(type),
          'showType': refresh ? '1' : '0',
          'sourceid': AppConstants.passportSourceId,
        },
        options: _passportOptions(),
      ),
    );
    _requireSuccess(body, '图形验证码取不到');
    final result = _asMap(body['result']) ?? const <dynamic, dynamic>{};
    final image = _decodeDataImage(result['captchaurl']?.toString());
    if (image == null) {
      throw const MiguLoginException(
        '咪咕返回的图形验证码无法显示，请稍后重试或改用官方页面登录。',
        officialOnly: true,
      );
    }
    return MiguGraphCaptcha(
      image: image,
      graphType: result['graphtype']?.toString().trim() ?? '',
    );
  }

  /// 把用户照图输入的字符交给官方校验一次。咪咕只有在这一步通过之后
  /// 才会在本次会话上摘掉风险标记，随后的登录才可能放行。
  Future<void> verifyGraphCaptcha(MiguImgcodeType type, String captcha) async {
    final value = captcha.trim();
    if (value.isEmpty) {
      throw const MiguLoginException('请输入图片里的字符。', captchaRequired: true);
    }
    final body = await _request(
      () => _dio.get<dynamic>(
        AppConstants.passportCaptchaCheckUrl,
        queryParameters: {
          'imgcodeType': _imgcodeTypeValue(type),
          'captcha': value,
          'sourceid': AppConstants.passportSourceId,
        },
        options: _passportOptions(),
      ),
    );
    if (body['status']?.toString().trim() == '2000') return;
    throw const MiguLoginException('图形验证码不对或已过期，请换一张再试。', captchaRequired: true);
  }

  String _imgcodeTypeValue(MiguImgcodeType type) =>
      type == MiguImgcodeType.sms ? '2' : '1';

  /// 官方把图片直接以 `data:image/jpeg;base64,...` 下发，这里只剥掉前缀。
  Uint8List? _decodeDataImage(String? dataUrl) {
    final text = dataUrl?.trim() ?? '';
    if (text.isEmpty) return null;
    final separator = text.indexOf(',');
    if (!text.startsWith('data:') || separator < 0) return null;
    try {
      return base64Decode(text.substring(separator + 1));
    } on FormatException {
      return null;
    }
  }

  void _requirePhone(String phone) {
    if (!_cnMobile.hasMatch(phone.trim())) {
      throw const MiguLoginException('请输入 11 位中国移动手机号。');
    }
  }

  bool _isNumericCode(String value) => RegExp(r'^\d{4,8}$').hasMatch(value);

  String _encrypt(String value, _RsaKey key) => rsaEncryptHex(
    plaintext: value,
    modulusHex: key.modulus,
    exponentHex: key.exponent,
    // 生产环境的 _random 就是 Random.secure()；填充与指纹共用一个熵源。
    random: _random,
  );

  /// 公钥每次登录都重新取：官方会轮换密钥，缓存旧公钥会直接导致加密结果不被接受。
  Future<_RsaKey> _publicKey() async {
    final body = await _request(
      () => _dio.post<dynamic>(
        AppConstants.passportPublicKeyUrl,
        options: _passportOptions(),
      ),
    );
    final result = _asMap(body['result']);
    final modulus = result?['modulus']?.toString().trim() ?? '';
    final exponent = result?['publicExponent']?.toString().trim() ?? '';
    if (modulus.isEmpty || exponent.isEmpty) {
      throw const MiguLoginException('没能取得咪咕登录公钥，请稍后重试。');
    }
    return (modulus: modulus, exponent: exponent);
  }

  /// 用本机留存的登录票据再换一次音乐站会话。
  ///
  /// 咪咕是否仍认这张票由它决定：票据过期、被吊销或已经用过都会在这里失败。
  /// 调用方按「续期没成功」处理，不重试、不换另一套接口。
  Future<MiguLoginSession> renewSession(String ticket) =>
      _exchangeToken(ticket, method: '登录', renewal: true);

  /// 用登录票据换音乐站会话；`pacmtoken` 是原生取 VIP 播放地址唯一的凭据。
  Future<MiguLoginSession> _exchangeToken(
    String token, {
    required String method,
    bool renewal = false,
  }) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        AppConstants.passportTokenValidateUrl,
        queryParameters: {
          'token': token,
          'type': '2',
          'sourceId': AppConstants.passportSourceId,
          'activityId': AppConstants.passportActivityId,
        },
        options: Options(
          headers: const {
            'Referer': AppConstants.miguReferer,
            'Origin': 'https://music.migu.cn',
            // 换票必须声明通行证已认证，否则咪咕不发放会话。
            'Cookie': 'idmpauth=true@passport.migu.cn',
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    } on DioException {
      throw MiguLoginException(
        renewal ? '会话续期时网络中断，请稍后重试。' : '登录已经通过，但换取音乐站会话时网络中断，请重试。',
        networkInterrupted: true,
      );
    }

    final status = response.statusCode ?? 0;
    // 两种字段名都可能用（status / code），只认一个会把码读成空；正文偶尔不被
    // dio 解码成 Map（内容类型不对），那时自己也解一次，否则形态会说成“非 JSON”。
    final decoded = _decodeBody(response.data);
    final body = _asMap(decoded) ?? const <dynamic, dynamic>{};
    final officialCode = _bodyCode(body);
    final bodyHint = _bodyHint(decoded, officialCode);
    if (status < 200 || status >= 300) {
      throw MiguLoginException(
        renewal
            ? '咪咕暂时没有接受会话续期请求（HTTP $status）。'
            : '$method登录已提交，但咪咕拒绝了会话请求（HTTP $status）。',
        // 只有 HTTP 401 是明确的“这张票据不被接受”；5xx、429、403 都可能
        // 只是服务抖动或风控临时拦截，不能拿来确认凭据作废。
        transient: renewal && status != 401,
        httpStatus: status,
        officialCode: officialCode,
        bodyHint: bodyHint,
      );
    }

    final pacmtoken = _cookieValue(response, 'pacmtoken') ?? '';
    if (pacmtoken.isEmpty) {
      // 不回显服务端原文：这个接口的提示文案可能夹带请求内容本身。
      throw MiguLoginException(
        renewal ? '咪咕暂时没有接受这张登录票据。' : '咪咕没有下发音乐站登录凭据，请重试或改用官方页面登录。',
        // 实测失效票据会回 HTTP 200 + 199999「系统繁忙」，与真正的服务抖动
        // 无法区分；续期时只能按暂时失败处理，不能直接判死本机凭据。
        transient: renewal,
        httpStatus: status,
        officialCode: officialCode,
        bodyHint: bodyHint,
      );
    }

    final data = _asMap(body['data']);
    final msisdn = data?['msisdn']?.toString().trim() ?? '';
    final cookies = <String, String>{'pacmtoken': pacmtoken};
    // 会话换到了，图形验证码那张会话就没有下一步用途：按声明当场丢掉，
    // 别让它跟着实例活到下一次取图。换票失败时留着，用户重填验证码还要用。
    _passportCookies.clear();
    return MiguLoginSession(
      cookies: cookies,
      maskedPhone: msisdn.isEmpty ? null : msisdn,
      userId: data?['userId']?.toString().trim(),
      token: token,
    );
  }

  Options _passportOptions({String? contentType}) {
    final session = _passportCookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    return Options(
      contentType: contentType,
      headers: {
        'Referer': AppConstants.passportReferer,
        'Origin': 'https://passport.migu.cn',
        if (session.isNotEmpty) 'Cookie': session,
      },
      followRedirects: false,
      validateStatus: (status) => status != null && status < 600,
    );
  }

  /// 记下通行证下发的会话 Cookie，供同一域名下的后续请求带回。
  void _capturePassportCookies(Response<dynamic> response) {
    for (final header in response.headers.map['set-cookie'] ?? const <String>[]) {
      final pair = header.split(';').first;
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        _passportCookies.remove(name);
      } else {
        _passportCookies[name] = value;
      }
    }
  }

  /// 统一发一次通行证请求：把 HTTP 状态与解析失败都折叠成不含凭据的提示。
  Future<Map<dynamic, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    Response<dynamic> response;
    try {
      response = await send();
    } on DioException {
      throw const MiguLoginException('无法连接咪咕登录服务，请检查网络后重试。');
    }
    _capturePassportCookies(response);
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw MiguLoginException('咪咕登录服务暂时不可用（HTTP $status），请稍后重试。');
    }
    final body = _asMap(response.data);
    if (body == null) {
      throw const MiguLoginException('咪咕登录服务返回了无法识别的内容，请稍后重试。');
    }
    return body;
  }

  /// 通行证用 `status=2000` 表示成功；其他状态一律视为失败。
  void _requireSuccess(Map<dynamic, dynamic> body, String fallback) {
    final status = body['status']?.toString().trim() ?? '';
    if (status == '2000') return;
    final hint = body['message']?.toString() ?? '';
    final captcha = hint.contains('验证码') || hint.contains('图形') || hint.contains('频繁');
    if (captcha) {
      throw const MiguLoginException(
        '咪咕要求先通过图形验证码，请输入图片中的字符后重试。',
        captchaRequired: true,
      );
    }
    throw MiguLoginException('$fallback（咪咕返回 $status）。');
  }

  String _readToken(Map<dynamic, dynamic> body) {
    final result = _asMap(body['result']);
    final token = result?['token']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw const MiguLoginException('咪咕没有返回登录票据，请稍后重试。');
    }
    return token;
  }

  Map<dynamic, dynamic>? _asMap(dynamic value) => value is Map ? value : null;

  /// 回包里的业务码：`status` 与 `code` 都试，取到哪个算哪个。
  String _bodyCode(Map<dynamic, dynamic> body) {
    for (final key in const ['status', 'code']) {
      final value = body[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// 只有读不出业务码时才记回包形态。
  ///
  /// 真机续期连续回 `HTTP 200` 却没有码，光这两样分不出「票据换不动」与
  /// 「中间有个东西把请求挡下了」，形态才是剩下的那条线索。
  String _bodyHint(dynamic data, String code) {
    if (code.isNotEmpty) return '';
    if (data is Map) return 'JSON 里没有码';
    if (data is String) return data.trim().isEmpty ? '空回包' : '非 JSON';
    return '没有回包体';
  }

  /// dio 因为内容类型没帮忙解码时自己解一次；解不动就原样交回。
  dynamic _decodeBody(dynamic data) {
    if (data is! String || data.trim().isEmpty) return data;
    try {
      return jsonDecode(data);
    } catch (_) {
      return data;
    }
  }

  String? _cookieValue(Response<dynamic> response, String name) {
    for (final header in response.headers.map['set-cookie'] ?? const <String>[]) {
      for (final item in header.split(',')) {
        final pair = item.trim().split(';').first;
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        if (pair.substring(0, separator).trim() != name) continue;
        final value = pair.substring(separator + 1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }
}

typedef _RsaKey = ({String modulus, String exponent});
