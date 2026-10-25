import 'secure_cookie_storage.dart';

/// 原生登录时咪咕通行证签发的登录票据。
///
/// 它不能直接取播放地址，只在账号接口回绝本机凭据时用来再换一次
/// `pacmtoken`；换不到就按凭据失效处理。与 Cookie 分开存放，便于
/// 「退出登录」与「改用官方页面重新登录」明确地把它一起丢掉。
class PassportTicketStore {
  PassportTicketStore({required SecureCookieStorage storage, String? key})
    // ignore: prefer_initializing_formals
    : _storage = storage,
      _key = key ?? defaultKey;

  static const String defaultKey = 'migu_passport_ticket_v1';

  final SecureCookieStorage _storage;
  final String _key;
  Future<void> _queue = Future<void>.value();

  Future<String?> read() async {
    final raw = await _storage.read(_key);
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> write(String ticket) {
    final trimmed = ticket.trim();
    if (trimmed.isEmpty) return clear();
    return _enqueue(() => _storage.write(_key, trimmed));
  }

  Future<void> clear() => _enqueue(() => _storage.delete(_key));

  /// 写入与删除按调用顺序串行：旧登录在途的票据写入不会晚于之后发起的
  /// 退出或新登录的删除落盘，最终存储状态对应最后一次操作。
  Future<void> _enqueue(Future<void> Function() task) {
    final result = _queue.then((_) => task());
    // 一次失败不能卡死后续操作；调用方仍能通过返回的 Future 收到异常。
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
