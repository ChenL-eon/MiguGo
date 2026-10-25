/// 宽松读取外部 JSON 字段，接口字段偶尔会在数字与字符串之间变化。
int readInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String readString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

Map<String, dynamic>? readMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic> readList(dynamic value) {
  return value is List ? value : const [];
}

List<String> readStringList(dynamic value) {
  return readList(value)
      .map((item) => item?.toString() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}
