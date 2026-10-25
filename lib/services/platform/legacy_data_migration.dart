import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 旧版 Windows 产品名是 “Migu Lele”，path_provider 因此把登录凭证与设置
/// 存在对应目录；更名后目录会变为 MiguGo，这里一次性复制旧文件避免数据丢失。
Future<void> migrateLegacyWindowsData() async {
  if (!Platform.isWindows) return;
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return;

  final separator = Platform.pathSeparator;
  final legacyDir = Directory('$appData${separator}cn.migulele${separator}Migu Lele');
  if (!await legacyDir.exists()) return;

  final Directory currentDir;
  try {
    currentDir = await getApplicationSupportDirectory();
  } catch (error) {
    debugPrint('读取当前数据目录失败，跳过旧数据迁移：$error');
    return;
  }
  if (currentDir.path.toLowerCase() == legacyDir.path.toLowerCase()) return;

  try {
    await currentDir.create(recursive: true);
    await for (final entity in legacyDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(separator).last;
      final target = File('${currentDir.path}$separator$name');
      if (await target.exists()) continue;
      await entity.copy(target.path);
      debugPrint('已迁移旧版本地数据：$name');
    }
  } catch (error) {
    debugPrint('迁移旧版本地数据失败，将继续使用新目录：$error');
  }
}
