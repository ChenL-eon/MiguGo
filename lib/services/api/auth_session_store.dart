import 'dart:convert';

import '../../models/auth_session.dart';
import 'secure_cookie_storage.dart';

/// 认证状态的持久化封装；只保存状态与时间，不保存 Cookie 值。
class AuthSessionStore {
  AuthSessionStore({required SecureCookieStorage storage, String? key})
    // ignore: prefer_initializing_formals
    : _storage = storage,
      _key = key ?? defaultKey;

  static const String defaultKey = 'migu_auth_session_v1';

  final SecureCookieStorage _storage;
  final String _key;

  Future<AuthSession> read() async {
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return AuthSession.none;
    try {
      final parsed = AuthSession.fromJson(jsonDecode(raw));
      return parsed ?? AuthSession.none;
    } on FormatException {
      return AuthSession.none;
    }
  }

  Future<void> write(AuthSession session) async {
    await _storage.write(_key, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(_key);
  }
}
