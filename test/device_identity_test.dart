import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => DeviceIdentity.reset());

  test('首次启动生成 UUID 并落盘，之后一直复用', () async {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentity.reset();

    final first = await DeviceIdentity.current();
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('migu_device_uuid_v1'), first);

    // 重启：进程内的缓存没了，只能从盘上取回同一个值。
    DeviceIdentity.reset();
    expect(await DeviceIdentity.current(), first);
  });

  test('盘上已有标识时直接沿用，不再新建', () async {
    SharedPreferences.setMockInitialValues({'migu_device_uuid_v1': 'fixed-id'});
    DeviceIdentity.reset();
    expect(await DeviceIdentity.current(), 'fixed-id');
  });

  test('同一进程内多次调用只读一次存储', () async {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentity.reset();
    final a = await DeviceIdentity.current();
    final b = await DeviceIdentity.current();
    expect(a, b);

    // 缓存生效后，即使底层存储被换掉也不会改变本次运行的标识。
    SharedPreferences.setMockInitialValues({'migu_device_uuid_v1': 'other'});
    expect(await DeviceIdentity.current(), a);
  });
}
