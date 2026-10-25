import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 调用系统原生文件选择框挑选本地图片；目前只有 Windows 桌面端实现了通道。
class NativeFilePicker {
  const NativeFilePicker._();

  static const MethodChannel _channel = MethodChannel('migu_lele/file_picker');

  static bool get supportsImagePicker => Platform.isWindows;

  /// 返回选中图片的绝对路径；用户取消或平台不支持时为 null。
  static Future<String?> pickImage({String? initialDirectory}) async {
    if (!supportsImagePicker) return null;
    try {
      return await _channel.invokeMethod<String>('pickImage', <String, Object?>{
        if (initialDirectory != null && initialDirectory.isNotEmpty)
          'initialDirectory': initialDirectory,
      });
    } on PlatformException catch (error) {
      debugPrint('打开系统文件选择框失败：${error.message}');
      return null;
    }
  }
}
