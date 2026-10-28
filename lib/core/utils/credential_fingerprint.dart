/// 凭证指纹：把任意长度的凭据压成一段可比较、不可还原成原文的短标记。
///
/// 用途是把「这一次请求到底用的是哪一份凭据」写进日志与诊断记录，同时不把
/// 凭据本身落到日志里。它只是相关性标记，FNV-1a 不是密码学摘要，不能当成
/// 完整性校验，更不代表凭据安全。
library;

/// 返回 `<12 位十六进制>/<字节数>`；[value] 为空或 null 时返回 `无`。
String credentialFingerprintOf(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '无';
  // 先把 FNV 偏移量折成正数：Dart 的 int 是 64 位有符号，直接写这个字面量会变成负数。
  var hash = 0xcbf29ce484222325 & _mask64;
  for (final unit in text.codeUnits) {
    hash = _mix(hash, unit & 0xff);
    hash = _mix(hash, (unit >> 8) & 0xff);
  }
  final hex = hash.toRadixString(16).padLeft(16, '0');
  return '${hex.substring(hex.length - 12)}/${text.length}';
}

/// FNV-1a 64 位：乘法结果只保留低 64 位，Dart 的 int 正好是这个宽度。
int _mix(int hash, int byte) => (hash ^ byte) * 0x100000001b3 & _mask64;

const int _mask64 = 0x7fffffffffffffff;
