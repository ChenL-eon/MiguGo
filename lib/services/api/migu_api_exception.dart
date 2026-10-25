/// 接口失败原因，用于区分网络、限流、鉴权与权限问题。
enum MiguErrorKind {
  generic,
  network,
  timeout,
  rateLimited,
  authRequired,
  authRejected,
  permissionDenied,

  /// 接口本身不发放该曲目的播放地址，与本机登录状态无关。
  playbackUnavailable,
  server,
  invalidResponse,
}

/// 面向界面的咪咕接口异常，包含可直接展示的中文说明。
class MiguApiException implements Exception {
  const MiguApiException(
    this.message, {
    this.kind = MiguErrorKind.generic,
    this.permissionDenied = false,
    this.loginRequired = false,
  });

  final String message;
  final MiguErrorKind kind;
  final bool permissionDenied;
  final bool loginRequired;

  /// 是否应引导用户检查或重新导入登录凭据。
  bool get canRelogin =>
      loginRequired ||
      kind == MiguErrorKind.authRequired ||
      kind == MiguErrorKind.authRejected ||
      kind == MiguErrorKind.permissionDenied;

  @override
  String toString() => message;
}
