/// 一次登录态探测的结论。
enum SessionProbe {
  /// 咪咕仍然接受本机凭据。
  alive,

  /// 咪咕明确表示未登录 / 登录失效；上层会先用留存票据试一次续期，
  /// 续不到才由用户手动重新登录。
  revoked,

  /// 网络异常或返回了看不懂的编码，不改变现有状态。
  unknown,
}

/// 咪咕明确说「你没登录」的文案，逐条列出而不是抓关键词。
///
/// 早先只按 `登录状态`、`token` 这类子串匹配，把「参数里 token 不能为空」这种
/// 请求写法问题也算成了凭据失效，凭据因此被无辜清掉。
const List<String> _revokedMessages = [
  '请先登录',
  '尚未登录',
  '未登录',
  '重新登录',
  '登录已失效',
  '登录失效',
  '登录态失效',
  '登录状态已失效',
  '登录状态失效',
  '会话已失效',
  '登录已过期',
  'token已失效',
  'token失效',
];

/// 咪咕没有统一的“登录失效”错误码，只能按 HTTP 状态、业务编码与文案一起判断。
///
/// 认不准时一律返回 [SessionProbe.unknown]：误判成失效会无谓地打断听歌，
/// 而真正的失效迟早会在下一次取链时暴露出来。
///
/// 403 不算失效：它更可能是这首曲目没有权益，或者是缺官方签名上下文。
SessionProbe classifySessionProbe({
  required int status,
  required String code,
  required String info,
}) {
  if (status == 401) return SessionProbe.revoked;
  if (status < 200 || status >= 300) return SessionProbe.unknown;

  final trimmedCode = code.trim();
  final message = info.trim();
  if (trimmedCode.isEmpty ||
      trimmedCode == '000000' ||
      trimmedCode == '0000' ||
      trimmedCode == '0' ||
      trimmedCode == '200') {
    return SessionProbe.alive;
  }
  if (trimmedCode == '290001') return SessionProbe.revoked;
  if (_revokedMessages.any(message.contains)) return SessionProbe.revoked;
  return SessionProbe.unknown;
}
