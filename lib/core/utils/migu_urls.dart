import '../constants/app_constants.dart';

/// 将接口返回的相对资源路径补全为咪咕 CDN 地址。
///
/// 应用禁止明文流量，历史数据中的 http 地址统一升级为 https。
String? resolveMiguAssetUrl(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('https://')) return value;
  if (value.startsWith('http://')) {
    return 'https://${value.substring('http://'.length)}';
  }
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('/')) return '${AppConstants.miguImageBase}$value';
  return '${AppConstants.miguImageBase}/$value';
}
