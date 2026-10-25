import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 登录凭据的安全存储抽象，便于在测试中替换为内存实现。
abstract class SecureCookieStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 安全存储不可用时抛出，消息中不包含任何 Cookie 值。
class SecureCookieStorageException implements Exception {
  const SecureCookieStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 使用系统凭据保护的实现。
///
/// - Android：数据由 Keystore 派生密钥加密，系统备份已关闭；
/// - Windows：插件用 DPAPI 按当前用户账户加密，密文写在应用数据目录的
///   flutter_secure_storage.dat 里，换一个 Windows 账户无法解密。
///
/// `resetOnError` 关闭，避免加密数据异常时静默清空全部登录信息，
/// 错误交由上层提示用户重新登录。
class FlutterSecureCookieStorage implements SecureCookieStorage {
  FlutterSecureCookieStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      throw const SecureCookieStorageException('无法读取系统安全存储。');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      throw const SecureCookieStorageException('无法写入系统安全存储。');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      throw const SecureCookieStorageException('无法删除系统安全存储中的凭据。');
    }
  }
}
