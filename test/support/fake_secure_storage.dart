import 'package:migu_lele/services/api/secure_cookie_storage.dart';

/// 内存版安全存储，用于验证迁移、持久化与失败分支。
class FakeSecureCookieStorage implements SecureCookieStorage {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;
  final Set<String> failWriteKeys = {};
  final Set<String> failDeleteKeys = {};
  int writeCount = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw const SecureCookieStorageException('测试：读取失败');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites || failWriteKeys.contains(key)) {
      throw const SecureCookieStorageException('测试：写入失败');
    }
    writeCount++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes || failDeleteKeys.contains(key)) {
      throw const SecureCookieStorageException('测试：删除失败');
    }
    values.remove(key);
  }
}
