import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/auth/migu_rsa.dart';

/// 1024 位模数：块长正好 128 字节。
final String _modulusHex = 'ff' * 128;

/// 用 exponent=1 时密文就是填充块本身，可以直接逐字节校验结构。
Uint8List _decodeBlock(String hex, int length) {
  expect(RegExp(r'^[0-9a-f]+$').hasMatch(hex), isTrue, reason: hex);
  var value = BigInt.parse(hex, radix: 16);
  final bytes = Uint8List(length);
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (value & BigInt.from(0xff)).toInt();
    value = value >> 8;
  }
  expect(value, BigInt.zero);
  return bytes;
}

String _encrypt(String plaintext, {String exponent = '1', Random? random}) =>
    rsaEncryptHex(
      plaintext: plaintext,
      modulusHex: _modulusHex,
      exponentHex: exponent,
      random: random,
    );

void main() {
  group('登录字段 RSA 加密', () {
    test('PKCS#1 v1.5 type-2 结构：00 02 <非零随机> 00 <明文>', () {
      const plaintext = '13800000000';
      final message = utf8.encode(plaintext);
      final block = _decodeBlock(_encrypt(plaintext), 128);
      final separator = 128 - message.length - 1;

      expect(block[0], 0);
      expect(block[1], 2);
      expect(block[separator], 0);
      expect(block.sublist(separator + 1), message);
      expect(block.sublist(2, separator).every((byte) => byte != 0), isTrue);
    });

    test('中文密码按 UTF-8 编码', () {
      const plaintext = '密码abc';
      final message = utf8.encode(plaintext);
      final block = _decodeBlock(_encrypt(plaintext), 128);
      expect(block.sublist(128 - message.length - 1 + 1), message);
    });

    test('输出是小写偶数长度的 16 进制串', () {
      final hex = _encrypt('123456');
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(hex), isTrue);
      expect(hex.length.isEven, isTrue);
    });

    test('同一明文两次结果不同（随机填充）', () {
      expect(_encrypt('13800000000'), isNot(_encrypt('13800000000')));
    });

    test('固定随机源时结果可复现', () {
      expect(
        _encrypt('13800000000', random: Random(20261022)),
        _encrypt('13800000000', random: Random(20261022)),
      );
    });

    test('达到 k-11 的明文仍然可加密，再长一律拒绝', () {
      expect(_encrypt('a' * 117).length, greaterThan(0));
      expect(() => _encrypt('a' * 118), throwsA(isA<FormatException>()));
    });

    test('公钥不可用时给出可展示的提示，不回显输入内容', () {
      for (final modulus in ['', '  ', 'zz', '0', '1']) {
        expect(
          () => rsaEncryptHex(
            plaintext: 'secret-input',
            modulusHex: modulus,
            exponentHex: '010001',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              isNot(contains('secret-input')),
            ),
          ),
          reason: 'modulus=$modulus',
        );
      }
    });

    test('真实指数 65537 下密文长度不超过模数', () {
      final hex = _encrypt('13800000000', exponent: '010001');
      expect(hex.length, lessThanOrEqualTo(256));
      expect(
        BigInt.parse(hex, radix: 16) < BigInt.parse(_modulusHex, radix: 16),
        isTrue,
      );
    });
  });
}
