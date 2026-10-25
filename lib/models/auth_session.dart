/// 登录凭据的本地状态。
///
/// - [none]：没有导入任何凭据；
/// - [unverified]：已导入，但尚未得到咪咕服务端确认；
/// - [verified]：登录后的播放请求成功，仅代表最近一次校验通过；
/// - [rejected]：带凭据的播放请求被拒绝，可能失效，也可能是账号无该歌曲权限。
enum AuthStatus { none, unverified, verified, rejected }

/// 认证会话的元数据，不包含 Cookie 值本身。
class AuthSession {
  const AuthSession({required this.status, this.importedAt, this.lastCheckedAt});

  static const AuthSession none = AuthSession(status: AuthStatus.none);

  final AuthStatus status;
  final DateTime? importedAt;
  final DateTime? lastCheckedAt;

  bool get hasImportedCredentials => status != AuthStatus.none;

  AuthSession copyWith({
    AuthStatus? status,
    DateTime? importedAt,
    DateTime? lastCheckedAt,
    bool clearImportedAt = false,
    bool clearLastCheckedAt = false,
  }) {
    return AuthSession(
      status: status ?? this.status,
      importedAt: clearImportedAt ? null : importedAt ?? this.importedAt,
      lastCheckedAt: clearLastCheckedAt ? null : lastCheckedAt ?? this.lastCheckedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'importedAt': importedAt?.toIso8601String(),
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
  };

  static AuthSession? fromJson(dynamic json) {
    if (json is! Map) return null;
    final status = switch (json['status']?.toString()) {
      'none' => AuthStatus.none,
      'unverified' => AuthStatus.unverified,
      'verified' => AuthStatus.verified,
      'rejected' => AuthStatus.rejected,
      _ => null,
    };
    if (status == null) return null;
    return AuthSession(
      status: status,
      importedAt: DateTime.tryParse(json['importedAt']?.toString() ?? ''),
      lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? ''),
    );
  }
}
