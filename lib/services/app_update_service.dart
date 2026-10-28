import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';

enum UpdateCheckStatus { upToDate, updateAvailable, failed }

/// 一次版本检查的结论。失败不代表没有新版本，只代表这次没查到。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.latestVersion,
    this.failure,
  });

  factory UpdateCheckResult.failure(String reason) =>
      UpdateCheckResult(status: UpdateCheckStatus.failed, failure: reason);

  final UpdateCheckStatus status;
  final String? latestVersion;
  final String? failure;

  bool get hasUpdate => status == UpdateCheckStatus.updateAvailable;
}

/// 读 GitHub 上最新一条 Release 的 tag，和本机版本号比大小。
class AppUpdateService {
  AppUpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Accept': 'application/vnd.github+json'},
            ),
          );

  final Dio _dio;

  Future<UpdateCheckResult> check({
    String currentVersion = AppConstants.appVersion,
  }) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(AppConstants.latestReleaseApiUrl);
    } on DioException catch (error) {
      return UpdateCheckResult.failure(_describe(error));
    } catch (_) {
      return UpdateCheckResult.failure('检查失败，请稍后再试');
    }

    final data = response.data;
    final tag = data is Map ? '${data['tag_name'] ?? ''}' : '';
    final latest = _versionOf(tag);
    if (latest == null) {
      return UpdateCheckResult.failure('最新发布记录里没有可用的版本号');
    }
    return UpdateCheckResult(
      status: _isNewer(latest, currentVersion)
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.upToDate,
      latestVersion: latest,
    );
  }

  static String _describe(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return '检查超时，网络可能不通';
    }
    return switch (error.response?.statusCode) {
      404 => '仓库还没有发布过版本',
      403 => '请求过于频繁，稍后再试',
      _ => '检查失败，网络可能不通',
    };
  }

  /// tag 允许写成 `v1.2.3` 或 `1.2`，取第一段数字版本号。
  static String? _versionOf(String tag) =>
      RegExp(r'\d+(?:\.\d+){1,3}').firstMatch(tag)?.group(0);

  static bool _isNewer(String candidate, String base) {
    final left = _parts(candidate);
    final right = _parts(base);
    if (left == null || right == null) return false;
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  static List<int>? _parts(String version) {
    final segments = version.split('.');
    final parts = <int>[];
    for (final segment in segments) {
      final value = int.tryParse(segment);
      if (value == null) return null;
      parts.add(value);
    }
    return parts.isEmpty ? null : parts;
  }
}
