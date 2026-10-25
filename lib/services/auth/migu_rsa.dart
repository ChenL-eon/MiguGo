import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 咪咕通行证登录字段的 RSA 加密。
///
/// 必须与网页端 `rsalib.js`（jsbn 版 RSAKey）逐位一致，否则通行证直接判参数错误：
/// - 公钥以 16 进制字符串下发，`n = modulus(16)`、`e = exponent(16)`；
/// - 明文按 PKCS#1 v1.5 第 2 类填充：`00 02 <非零随机填充> 00 <UTF-8 明文>`，
///   块长 `k = (n.bitLength + 7) >> 3`；
/// - 密文取 `m^e mod n`，输出**小写 16 进制，长度为奇数时补一个前导 0**（不做定长补齐）。
String rsaEncryptHex({
  required String plaintext,
  required String modulusHex,
  required String exponentHex,
  Random? random,
}) {
  final modulus = _parseHex(modulusHex);
  final exponent = _parseHex(exponentHex);
  if (modulus == null ||
      modulus <= BigInt.zero ||
      exponent == null ||
      exponent <= BigInt.zero) {
    throw const FormatException('登录公钥格式不正确，请稍后重试。');
  }

  final blockLength = (modulus.bitLength + 7) >> 3;
  final message = utf8.encode(plaintext);
  // 除了 00 02 前缀与结束符，PKCS#1 v1.5 还要求至少 8 个随机填充字节。
  if (message.length + 11 > blockLength) {
    throw const FormatException('输入内容过长，无法完成登录加密。');
  }

  final source = random ?? Random.secure();
  final block = Uint8List(blockLength);
  block[0] = 0;
  block[1] = 2;
  var cursor = 2;
  final paddingEnd = blockLength - message.length - 1;
  while (cursor < paddingEnd) {
    // 填充字节不能为 0，否则服务端解出来的边界会错位。
    final byte = source.nextInt(256);
    if (byte == 0) continue;
    block[cursor] = byte;
    cursor++;
  }
  block[paddingEnd] = 0;
  block.setRange(paddingEnd + 1, blockLength, message);

  var value = BigInt.zero;
  for (final byte in block) {
    value = (value << 8) | BigInt.from(byte);
  }
  final cipher = value.modPow(exponent, modulus);
  final hex = cipher.toRadixString(16);
  return hex.length.isOdd ? '0$hex' : hex;
}

BigInt? _parseHex(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return BigInt.tryParse(text, radix: 16);
}
