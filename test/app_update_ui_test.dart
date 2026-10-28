import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/constants/app_constants.dart';
import 'package:migu_lele/core/theme/app_theme.dart';
import 'package:migu_lele/models/theme_accent.dart';
import 'package:migu_lele/pages/about_page.dart';
import 'package:migu_lele/providers/update_provider.dart';
import 'package:migu_lele/services/app_update_service.dart';
import 'package:provider/provider.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final opened = <String>[];

  /// 关于页顶上有 GitHub 图标，图片解码在 fake async 里等不到结束，
  /// 所以这里只用有限次 pump，不用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpAbout(WidgetTester tester, UpdateProvider update) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(ThemeAccent.rose),
        home: ChangeNotifierProvider<UpdateProvider>.value(
          value: update,
          child: const Scaffold(body: AboutPage()),
        ),
      ),
    );
    await settle(tester);
  }

  /// 关于页是一整页滚动内容，按钮可能落在视口外，先滚到可见再点。
  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await settle(tester);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
          final args = call.arguments;
          if (args is Map && args['url'] is String) {
            // 新旧两套 API 都会带 url，这里只关心「有没有真的发起外链」。
            if (call.method == 'launch' || call.method == 'launchUrl') {
              opened.add(args['url'] as String);
            }
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, null);
  });

  testWidgets('点立即检查在页面里给出结论，不跳去 GitHub', (tester) async {
    final adapter = _StubAdapter(
      (_) => _json('{"tag_name": "v1.9.9", "html_url": "https://github.com/x"}'),
    );
    final update = UpdateProvider(_service(adapter));
    await update.load();
    await pumpAbout(tester, update);

    expect(find.text('尚未检查更新'), findsOne);
    await tapText(tester, '立即检查');

    expect(adapter.requests, hasLength(1));
    expect(find.textContaining('发现新版本 v1.9.9'), findsOne);
    expect(find.text('新版本 v1.9.9'), findsOne);
    // 检查这一步不该顺手打开浏览器。
    expect(opened, isEmpty);
  });

  testWidgets('已是最新时写明当前版本，也不跳页', (tester) async {
    final adapter = _StubAdapter(
      (_) => _json('{"tag_name": "v${AppConstants.appVersion}"}'),
    );
    final update = UpdateProvider(_service(adapter));
    await update.load();
    await pumpAbout(tester, update);

    await tapText(tester, '立即检查');

    expect(
      find.textContaining('已是最新版本 v${AppConstants.appVersion}'),
      findsOne,
    );
    expect(find.text('打开发布页'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('查不到时只说这次没查到，不谎称已最新', (tester) async {
    final update = UpdateProvider(
      _service(_StubAdapter((_) => _json('{}', status: 404))),
    );
    await update.load();
    await pumpAbout(tester, update);

    await tapText(tester, '立即检查');

    expect(find.text('仓库还没有发布过版本'), findsOne);
    expect(find.textContaining('已是最新'), findsNothing);
  });

  testWidgets('发现新版本后多给一个打开发布页的入口，检查本身不产生外链', (
    tester,
  ) async {
    final update = UpdateProvider(
      _service(_StubAdapter((_) => _json('{"tag_name": "v1.9.9"}'))),
    );
    await update.load();
    await pumpAbout(tester, update);

    // 打开发布页只作为查到新版本后的第二步，由用户自己点。
    expect(find.text('打开发布页'), findsNothing);
    await tapText(tester, '立即检查');

    expect(find.text('打开发布页'), findsOne);
    expect(opened, isEmpty, reason: '检查这一步不该顺手打开浏览器');
  });
}
