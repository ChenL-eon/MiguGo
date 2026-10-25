import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/theme/android_tokens.dart';
import 'package:migu_lele/core/theme/app_theme.dart';
import 'package:migu_lele/models/theme_accent.dart';
import 'package:migu_lele/widgets/android/android_choice.dart';
import 'package:migu_lele/widgets/android/android_feedback.dart';
import 'package:migu_lele/widgets/android/android_sheet.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(ThemeAccent.rose),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('提示条区分普通与错误：浮动样式、时长与图标都不同', (tester) async {
    late BuildContext snackContext;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            snackContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    showAndroidSnack(snackContext, '已加入我喜欢');
    await tester.pump();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.behavior, SnackBarBehavior.floating);
    expect(snack.duration, const Duration(milliseconds: 2600));
    expect(find.text('已加入我喜欢'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

    // 定时器留在树上会污染后续用例，收掉再继续。
    ScaffoldMessenger.of(snackContext).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('已加入我喜欢'), findsNothing);

    showAndroidSnack(snackContext, '网络不太顺畅', isError: true);
    await tester.pump();

    final errorSnack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(errorSnack.duration, const Duration(milliseconds: 4200));
    expect(find.text('网络不太顺畅'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);

    ScaffoldMessenger.of(snackContext).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('网络不太顺畅'), findsNothing);
  });

  testWidgets('提示条叠放时后一次覆盖前一次', (tester) async {
    late BuildContext snackContext;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            snackContext = context;
            return const Text('占位');
          },
        ),
      ),
    );

    showAndroidSnack(snackContext, '第一条');
    await tester.pump();
    showAndroidSnack(snackContext, '第二条');
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);

    ScaffoldMessenger.of(snackContext).removeCurrentSnackBar();
    await tester.pumpAndSettle();
  });

  testWidgets('确认框把主操作与取消回传成布尔值', (tester) async {
    var confirmed = false;
    Future<void> open(BuildContext context, {bool destructive = false}) async {
      confirmed = await showAndroidConfirm(
        context,
        title: '退出登录',
        message: '退出后将清除本机凭据。',
        destructive: destructive,
      );
    }

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(open(context, destructive: true)),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('退出后将清除本机凭据。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('告知框只有一个关闭动作', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAndroidNotice(context, title: '云盘', message: '暂不支持查看云盘歌单。'),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('知道了'), findsOneWidget);
    expect(find.text('取消'), findsNothing);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('云盘'), findsNothing);
  });

  testWidgets('行内错误条按需渲染重试与关闭', (tester) async {
    var retried = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _wrap(
        AndroidInlineError(
          title: '加载更多失败',
          message: '第 2 页没有取回来。',
          onRetry: () => retried++,
          onDismiss: () => dismissed++,
        ),
      ),
    );

    expect(find.text('加载更多失败'), findsOneWidget);
    expect(find.text('第 2 页没有取回来。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, 1);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(dismissed, 1);

    await tester.pumpWidget(_wrap(const AndroidInlineError(message: '只有文案')));
    expect(find.text('重试'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('单选面板高亮当前项并把选择回传', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAndroidChoiceSheet<int?>(
                context,
                title: '睡眠定时',
                subtitle: '到点后停止播放',
                options: const [
                  AndroidChoiceOption<int?>(value: null, label: '不开启'),
                  AndroidChoiceOption<int?>(
                    value: 15,
                    label: '15 分钟',
                    icon: Icons.bedtime_rounded,
                  ),
                ],
                selected: null,
                onSelected: (value) => picked = value,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('睡眠定时'), findsOneWidget);
    expect(find.text('到点后停止播放'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    final onColor = tester.widget<Text>(find.text('不开启')).style?.color;
    final offColor = tester.widget<Text>(find.text('15 分钟')).style?.color;
    expect(onColor, isNot(offColor));

    await tester.tap(find.text('15 分钟'));
    await tester.pumpAndSettle();

    expect(picked, 15);
    expect(find.text('睡眠定时'), findsNothing);
  });

  testWidgets('单选面板可空值也能被选中', (tester) async {
    String? picked = 'rose';
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAndroidChoiceSheet<String?>(
                context,
                title: '主题色',
                options: [
                  AndroidChoiceOption<String?>(
                    value: 'rose',
                    label: '玫粉',
                    swatch: Colors.pink,
                  ),
                  AndroidChoiceOption<String?>(value: null, label: '跟随系统'),
                ],
                selected: picked,
                onSelected: (value) => picked = value,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(DecoratedBox), findsWidgets);

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('主题色'), findsNothing);
  });

  testWidgets('操作表内容不自带标题栏重复', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAndroidSheet<void>(
                context: context,
                title: '播放列表',
                subtitle: '共 0 首 · 点击切歌',
                scrollable: false,
                contentPadding: const EdgeInsets.only(top: AndroidSpacing.sm),
                builder: (_) => const Text('列表还是空的'),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('播放列表'), findsOneWidget);
    expect(find.text('共 0 首 · 点击切歌'), findsOneWidget);
    expect(find.text('列表还是空的'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}
