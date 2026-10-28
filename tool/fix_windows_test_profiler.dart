import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length > 1) {
    stderr.writeln(
      'Usage on Windows: dart tool/fix_windows_test_profiler.dart [flutter-sdk-path]',
    );
    exitCode = 64;
    return;
  }
  final project = File.fromUri(Platform.script).parent.parent;
  final sdk = Directory(
    args.isEmpty ? '${project.path}/.tooling/flutter' : args.single,
  ).absolute;
  final cache = '${sdk.path}/bin/cache';
  final version = jsonDecode(
    File('$cache/flutter.version.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final engine = File('$cache/engine.stamp').readAsStringSync().trim();
  if (version['frameworkVersion'] != '3.47.7' ||
      version['dartSdkVersion'] != '3.13.5' ||
      engine != 'deb287481e3ce9468f3434937ced4240a70539ca') {
    throw StateError(
      'Only verified for Flutter 3.47.7 / Dart 3.13.5. Reassess dart-lang/sdk#64627 before changing another SDK.',
    );
  }

  final source = File(
    '${sdk.path}/packages/flutter_tools/lib/src/test/flutter_tester_device.dart',
  );
  final originalText = source.readAsStringSync();
  final newline = originalText.contains('\r\n') ? '\r\n' : '\n';
  const original =
      "      if (debuggingOptions.enableDartProfiling) '--enable-dart-profiling',";
  final patched = [
    '      // Windows profiler stack walk crashes in Dart 3.13.5 (dart-lang/sdk#64627).',
    '      if (debuggingOptions.enableDartProfiling && !platform.isWindows)',
    "        '--enable-dart-profiling',",
  ].join(newline);
  final alreadyPatched = originalText.contains(patched);
  if (!alreadyPatched && original.allMatches(originalText).length != 1) {
    throw StateError(
      'Unexpected flutter_tester_device.dart contents; no files changed.',
    );
  }
  final snapshot = File('$cache/flutter_tools.snapshot');
  final sourceBackup = File(
    '$cache/flutter_tester_device.dart.before-no-profiler',
  );
  final snapshotBackup = File(
    '$cache/flutter_tools.snapshot.before-no-profiler',
  );
  if (alreadyPatched &&
      (!sourceBackup.existsSync() || !snapshotBackup.existsSync())) {
    throw StateError('Profiler backups are missing; no files changed.');
  }
  if (!alreadyPatched) {
    if (sourceBackup.existsSync() || snapshotBackup.existsSync()) {
      throw StateError(
        'Existing profiler backups need review; no files changed.',
      );
    }
    source.copySync(sourceBackup.path);
    snapshot.copySync(snapshotBackup.path);
  }

  final temporary = Directory('$cache/').createTempSync('test-profiler-fix-');
  try {
    if (!alreadyPatched) {
      source.writeAsStringSync(originalText.replaceFirst(original, patched));
    }
    final compiled = File('${temporary.path}/flutter_tools.snapshot');
    final result = await Process.run(
      '$cache/dart-sdk/bin/dart.exe',
      [
        '--verbosity=error',
        '--snapshot=${compiled.path}',
        '--snapshot-kind=app-jit',
        '--packages=${sdk.path}/packages/flutter_tools/.dart_tool/package_config.json',
        '--no-enable-mirrors',
        '${sdk.path}/packages/flutter_tools/bin/flutter_tools.dart',
      ],
      workingDirectory: sdk.path,
      environment: {'FLUTTER_ROOT': sdk.path},
    );
    if (result.exitCode != 0) {
      stderr.write(result.stdout);
      stderr.write(result.stderr);
      throw StateError(
        'Tool compilation failed (${result.exitCode}); original snapshot retained.',
      );
    }
    compiled.renameSync(snapshot.path);
  } catch (_) {
    if (!alreadyPatched) source.writeAsStringSync(originalText);
    rethrow;
  } finally {
    temporary.deleteSync(recursive: true);
  }
  stdout.writeln(
    'Windows-test-only workaround applied; flutter test runs without CPU sampling.',
  );
  stdout.writeln(
    'Original source and snapshot retained in $cache (*.before-no-profiler).',
  );
}
