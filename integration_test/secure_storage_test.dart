import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:migu_lele/services/api/secure_cookie_storage.dart';

/// 真机/桌面端验证系统安全存储可用；只使用独立测试键，不触碰真实登录数据。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('系统安全存储可写入、回读并删除', (tester) async {
    final storage = FlutterSecureCookieStorage();
    const key = 'migu_integration_probe_v1';
    const value = 'probe-value-中文-0123456789';

    await storage.delete(key);
    expect(await storage.read(key), isNull);

    await storage.write(key, value);
    expect(await storage.read(key), value);

    await storage.delete(key);
    expect(await storage.read(key), isNull);
  });
}
