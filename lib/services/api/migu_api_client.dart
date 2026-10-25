import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/device_identity.dart';
import '../../core/utils/json_read.dart';
import '../auth/session_probe.dart';
import '../auth/session_reject_ledger.dart';
import 'migu_api_exception.dart';
import 'migu_cookie_store.dart';

/// 本身就要求登录的账号接口。只有它们的拒绝才指向本机凭据。
///
/// 歌词、封面、CDN 流地址、公开搜索这些接口回 401 说的是“那条资源拿不到”：
/// 签名地址过期、单条曲目无权限都会这样，跟登录态无关，早前先于把这些当成失效，
/// 一次偶发的歌词 401 就足以清掉用户凭据。
bool isLoginScopedEndpoint(Uri uri) {
  final path = uri.path;
  return path.contains('/user/h5/user-info/') ||
      path.contains('/pc/user/home-page/') ||
      path.contains('/pc/user/h5/queryUserInfo/');
}

/// Dio 封装：统一附带 Referer、设备标识、账号 Cookie，并维护服务端下发的会话 Cookie。
class MiguApiClient {
  MiguApiClient({
    Dio? dio,
    MiguCookieStore? cookieStore,
    SessionRejectLedger? ledger,
    this.sessionEpoch,
    this.onSessionRevoked,
  }) : cookieStore = cookieStore ?? MiguCookieStore.instance,
       _ledger = ledger ?? SessionRejectLedger.instance,
       _dio =
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
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['Referer'] = AppConstants.miguReferer;
          // 与咪咕网页 SDK 一致的基线头；每日推荐接口缺少 imei 会直接拒绝。
          options.headers.putIfAbsent('activityid', () => 'MUSIC-WWW');
          options.headers.putIfAbsent('appid', () => 'h5');
          options.headers.putIfAbsent('channel', () => '014X031');
          options.headers.putIfAbsent('subchannel', () => '014X031');
          options.headers.putIfAbsent('platform', () => 'H5');
          options.headers.putIfAbsent('ua', () => 'Android_migu');
          options.headers.putIfAbsent('version', () => '6.8.8');
          options.headers.putIfAbsent('imei', () => 'h5page');
          options.headers.putIfAbsent('imsi', () => 'h5page');
          options.headers['deviceId'] = await DeviceIdentity.current();
          final epoch = sessionEpoch?.call();
          if (epoch != null) options.extra[_sessionEpochKey] = epoch;
          final cookie = this.cookieStore.cookieHeaderFor(options.uri);
          if (cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          final credentials = this.cookieStore.credentials;
          // Cookie 已经按域名收口，这三个裸凭据头同理：重定向或 CDN 换到
          // 非咪咕域名时，不能把 uid/pacmtoken/msisdn 一起带走。
          if (isMiguHost(options.uri.host)) {
            if (credentials.uid != null) {
              options.headers['uid'] = credentials.uid;
            }
            if (credentials.pacmtoken != null) {
              options.headers['pacmtoken'] = credentials.pacmtoken;
            }
            if (credentials.msisdn != null) {
              options.headers['msisdn'] = credentials.msisdn;
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          // 旧会话的请求回来时既不写新会话的 Cookie，也不把拒绝记到新账号头上。
          if (!_isStaleRequest(response.requestOptions)) {
            await _captureCookies(response);
            _noteFailure(response);
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          final response = error.response;
          if (response != null && !_isStaleRequest(response.requestOptions)) {
            await _captureCookies(response);
            _noteFailure(response);
          }
          handler.next(error);
        },
      ),
    );
  }

  static const String _sessionEpochKey = 'migu_session_epoch';

  final Dio _dio;
  final MiguCookieStore cookieStore;
  final SessionRejectLedger _ledger;

  /// 当前凭据代数；请求发出时记下，回包时用来识别属于旧会话的响应。
  final int Function()? sessionEpoch;

  /// 本机凭据被要求登录的接口回绝时的回调，用来降级状态或确认后退出。
  final VoidCallback? onSessionRevoked;

  /// 这个响应是否属于已经结束或已被替换的会话。
  bool _isStaleRequest(RequestOptions options) {
    final sent = options.extra[_sessionEpochKey];
    if (sent is! int) return false;
    final current = sessionEpoch?.call();
    return current != null && sent != current;
  }

  /// 记下一次「咪咕回绝本机凭据」的证据。
  ///
  /// 证据一律留下（项目没有日志文件，界面是唯一出口）；但只有**要求登录的账号接口**
  /// 且本机确实带过 `pacmtoken` 时才计入失效判定并回报上层，公开接口的 401 只算参考。
  ///
  /// [evidenceGrade] 为假表示这次拒绝只能留档：403 既可能是 Cookie 失效，也可能
  /// 只是这个账号没有那首歌的权限，分不清就不能拿它判死凭据。
  void noteAuthFailure({
    required Uri uri,
    required int status,
    String code = '',
    String info = '',
    bool evidenceGrade = true,
  }) {
    final sentCredentials = cookieStore.credentials.pacmtoken != null;
    final loginScoped = evidenceGrade && isLoginScopedEndpoint(uri) && sentCredentials;
    _ledger.note(
      uri: uri,
      status: status,
      code: code,
      info: info,
      loginScoped: loginScoped,
    );
    if (!loginScoped) return;
    onSessionRevoked?.call();
  }

  /// 从响应里判断这是不是一次「咪咕回绝本机凭据」，并就地取证。
  ///
  /// 只有在这里判断才拿得到真实请求地址，业务码 `290001 请先登录` 也才是 HTTP 200，
  /// 拦截器以外的层只能看到一个 payload，分不清它是哪个接口回来的。
  void _noteFailure(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final uri = response.requestOptions.uri;
    if (status == 401 || status == 403) {
      final (code, info) = _readCodes(response.data);
      noteAuthFailure(
        uri: uri,
        status: status,
        code: code,
        info: info,
        evidenceGrade: status == 401,
      );
      return;
    }
    if (status < 200 || status >= 300) return;

    final map = response.data is Map ? response.data as Map : null;
    if (map == null) return;
    final code = readString(map['code']).trim();
    if (_isSuccessCode(code)) {
      // 要求登录的账号接口成功回包，就是这份凭据仍被接受的最直接证据。
      if (isLoginScopedEndpoint(uri)) _ledger.resetStrikes();
      return;
    }
    final info = _readInfo(map);
    if (classifySessionProbe(status: status, code: code, info: info) !=
        SessionProbe.revoked) {
      return;
    }
    noteAuthFailure(uri: uri, status: status, code: code, info: info);
  }

  static bool _isSuccessCode(String code) =>
      code.isEmpty ||
      code == '000000' ||
      code == '0000' ||
      code == '0' ||
      code == '200';

  (String code, String info) _readCodes(dynamic body) {
    final map = body is Map ? body : const <dynamic, dynamic>{};
    return (readString(map['code']), _readInfo(map));
  }

  static String _readInfo(Map map) {
    final info = readString(map['info']);
    return info.isEmpty ? readString(map['msg']) : info;
  }

  /// 发起请求并返回原始响应，供播放地址接口检查 3xx Location 或二进制响应体。
  Future<Response<dynamic>> getRaw(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool followRedirects = true,
    ResponseType responseType = ResponseType.json,
  }) async {
    try {
      return await _dio.get<dynamic>(
        url,
        queryParameters: query,
        options: Options(
          headers: headers,
          followRedirects: followRedirects,
          responseType: responseType,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  /// 获取 JSON；HTTP 非 2xx 统一转换为可展示异常。
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query}) async {
    final response = await getRaw(url, query: query);
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw _mapStatus(status, fallback: '咪咕服务暂时不可用');
    }
    return response.data;
  }

  /// 获取 LRC 等纯文本内容。
  Future<String> getText(String url) async {
    final response = await getRaw(url, responseType: ResponseType.plain);
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw _mapStatus(status, fallback: '歌词加载失败');
    }
    final data = response.data;
    return data is String ? data : data?.toString() ?? '';
  }

  Future<void> _captureCookies(Response<dynamic> response) async {
    try {
      await cookieStore.capture(response);
    } catch (_) {
      debugPrint('记录服务端下发的 Cookie 失败，本次响应仍继续处理。');
    }
  }

  MiguApiException _mapStatus(int status, {required String fallback}) {
    if (status == 429) {
      return const MiguApiException(
        '请求过于频繁，咪咕服务已临时限流，请稍后再试。',
        kind: MiguErrorKind.rateLimited,
      );
    }
    if (status == 401) {
      return const MiguApiException(
        '咪咕服务要求重新登录，登录状态可能已失效。',
        kind: MiguErrorKind.authRequired,
        loginRequired: true,
      );
    }
    if (status == 403) {
      return const MiguApiException(
        '咪咕服务拒绝了本次请求：登录可能已失效，或当前账号没有相应权限。',
        kind: MiguErrorKind.authRejected,
        permissionDenied: true,
        loginRequired: true,
      );
    }
    if (status >= 500) {
      return MiguApiException(
        '咪咕服务暂时不可用（HTTP $status），请稍后重试。',
        kind: MiguErrorKind.server,
      );
    }
    return MiguApiException(
      '$fallback（HTTP $status）。',
      kind: MiguErrorKind.invalidResponse,
    );
  }

  MiguApiException _mapDioError(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const MiguApiException(
        '网络连接超时，请检查网络后重试。',
        kind: MiguErrorKind.timeout,
      ),
      DioExceptionType.connectionError => const MiguApiException(
        '网络连接失败，请检查网络设置。',
        kind: MiguErrorKind.network,
      ),
      DioExceptionType.badCertificate => const MiguApiException(
        '证书校验失败，已停止连接。',
        kind: MiguErrorKind.network,
      ),
      DioExceptionType.cancel => const MiguApiException('请求已取消。'),
      _ => const MiguApiException('网络请求失败，请稍后重试。', kind: MiguErrorKind.network),
    };
  }
}
