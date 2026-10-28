import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/providers/update_provider.dart';
import 'package:migu_lele/services/app_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final FutureOr<ResponseBody> Function(RequestOptions options) reply;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String text, {int status = 200}) => ResponseBody.fromString(
  text,
  status,
  headers: {
    'content-type': [Headers.jsonContentType],
  },
);

AppUpdateService _service(_StubAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return AppUpdateService(dio: dio);
}

/// 只按版本号改变结论，避免测试跟着 appVersion 一起漂。
const String _current = '1.4.2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本检查服务', () {
    test('新版本号判定为有更新，并带上查到的版本', () async {
      final adapter = _StubAdapter(
        (_) => _json('{"tag_name": "v9.9.9", "name": "Beta"}'),
      );
      final result = await _service(adapter).check(currentVersion: _current);

      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, '9.9.9');
    });

    test('版本号相同或更新记录更旧都算已是最新', () async {
      for (final tag in ['v$_current', 'v1.4.1', 'v0.9']) {
        final result = await _service(
          _StubAdapter((_) => _json('{"tag_name": "$tag"}')),
        ).check(currentVersion: _current);
        expect(result.status, UpdateCheckStatus.upToDate, reason: tag);
        expect(result.hasUpdate, isFalse);
      }
    });

    test('四位版本号逐段比大小，不靠字符串字典序', () async {
      final result = await _service(
        _StubAdapter((_) => _json('{"tag_name": "v1.4.10"}')),
      ).check(currentVersion: _current);
      expect(result.status, UpdateCheckStatus.updateAvailable);
    });

    test('请求只打公开发布接口，且不携带任何凭据头', () async {
      final adapter = _StubAdapter((_) => _json('{"tag_name": "v$_current"}'));
      await _service(adapter).check(currentVersion: _current);

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, AppConstants.latestReleaseApiUrl);
      expect(request.headers.keys, isNot(contains('Cookie')));
      expect(request.headers.keys, isNot(contains('Authorization')));
    });

    test('仓库没有发布记录时说人话，不谎报没有更新', () async {
      final result = await _service(
        _StubAdapter((_) => _json('{"message": "Not Found"}', status: 404)),
      ).check(currentVersion: _current);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.failure, '仓库还没有发布过版本');
    });

    test('发布记录里没有可用版本号时按失败处理', () async {
      for (final body in ['{}', '{"tag_name": ""}', '{"tag_name": "nightly"}']) {
        final result = await _service(
          _StubAdapter((_) => _json(body)),
        ).check(currentVersion: _current);
        expect(result.status, UpdateCheckStatus.failed, reason: body);
        expect(result.failure, isNotNull);
      }
    });

    test('被限流时提示稍后再试', () async {
      final result = await _service(
        _StubAdapter((_) => _json('{"message": "rate limited"}', status: 403)),
      ).check(currentVersion: _current);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.failure, contains('稍后再试'));
    });
  });

  group('版本检查状态', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('查到的结论能存下来，重启后读回同一条', () async {
      final first = UpdateProvider(
        _service(_StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'))),
      );
      await first.load();
      await first.check();

      final second = UpdateProvider(
        _service(_StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'))),
      );
      await second.load();

      expect(second.last?.status, UpdateCheckStatus.updateAvailable);
      expect(second.last?.latestVersion, '9.9.9');
      expect(second.checkedAt, isNotNull);
    });

    test('关闭开关后启动检查一次请求都不发', () async {
      SharedPreferences.setMockInitialValues({
        'migu_auto_check_updates_v1': false,
      });
      final adapter = _StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'));
      final provider = UpdateProvider(_service(adapter));
      await provider.load();

      expect(provider.autoCheck, isFalse);
      await provider.checkOnStartup();
      expect(adapter.requests, isEmpty);

      await provider.setAutoCheck(true);
      expect(provider.autoCheck, isTrue);
      await provider.checkOnStartup();
      expect(adapter.requests, hasLength(1));
    });

    test('刚查过就不重复敲门，超过间隔才再查', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'migu_update_check_result_v1',
        '{"status":"upToDate","version":"1.4.2","at":'
        '${DateTime.now().millisecondsSinceEpoch}}',
      );
      final fresh = _StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'));
      final provider = UpdateProvider(_service(fresh));
      await provider.load();

      await provider.checkOnStartup();
      expect(fresh.requests, isEmpty);

      await preferences.setString(
        'migu_update_check_result_v1',
        '{"status":"upToDate","version":"1.4.2","at":'
        '${DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch}}',
      );
      final stale = _StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'));
      final restarted = UpdateProvider(_service(stale));
      await restarted.load();
      await restarted.checkOnStartup();

      expect(stale.requests, hasLength(1));
      expect(restarted.last?.latestVersion, '9.9.9');
    });

    test('失败只说明这次没查到，不抹掉上一次的好结果', () async {
      final provider = UpdateProvider(
        _service(_StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'))),
      );
      await provider.load();
      await provider.check();
      final knownAt = provider.checkedAt!;

      final failing = UpdateProvider(
        _service(_StubAdapter((_) => _json('{}', status: 404))),
      );
      await failing.load();
      expect(failing.last?.latestVersion, '9.9.9');

      final offline = UpdateProvider(
        _service(_StubAdapter((_) => _json('{"message": "server error"}', status: 500))),
      );
      await offline.load();
      await offline.check();

      expect(offline.failure, '检查失败，网络可能不通');
      expect(offline.last?.latestVersion, '9.9.9');
      expect(
        offline.checkedAt?.millisecondsSinceEpoch,
        knownAt.millisecondsSinceEpoch,
      );
    });

    test('存坏的记录当作没查过，关于页照样能打开', () async {
      SharedPreferences.setMockInitialValues({
        'migu_update_check_result_v1': 'not json',
      });
      final provider = UpdateProvider(
        _service(_StubAdapter((_) => _json('{"tag_name": "v9.9.9"}'))),
      );
      await provider.load();

      expect(provider.last, isNull);
      expect(provider.checkedAt, isNull);
    });
  });
}
