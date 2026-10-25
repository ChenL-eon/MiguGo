import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_response_cipher.dart';

/// 按站点格式封装明文，用于验证解码器。
List<int> seal(String text, {int offset = 73}) {
  final key = utf8.encode(MiguResponseCipher.productionKey);
  final plain = utf8.encode(text);
  final bytes = <int>[0xAB, 0xCD, 1, offset];
  for (var i = 0; i < plain.length; i++) {
    bytes.add((plain[i] - offset + key[i % key.length]) & 0xFF);
  }
  return bytes;
}

void main() {
  group('播放响应体解码', () {
    test('按站点格式还原 JSON', () {
      const text = '{"code":"000000","data":{"url":"https://cdn.example.com/a.mp3"}}';

      final decoded = MiguResponseCipher.decodeJson(seal(text));

      expect(decoded, isA<Map>());
      expect(decoded['code'], '000000');
      expect(decoded['data']['url'], 'https://cdn.example.com/a.mp3');
    });

    test('偏移字节取边界值时仍可还原', () {
      for (final offset in [0, 1, 127, 255]) {
        const text = '{"ok":true}';
        final decoded = MiguResponseCipher.decodeJson(seal(text, offset: offset));
        expect(decoded?['ok'], isTrue, reason: 'offset=$offset');
      }
    });

    test('拒绝缺少魔数、版本不符或长度不足的数据', () {
      expect(MiguResponseCipher.decrypt([0x41, 0x42, 0x43, 0x44]), isNull);
      expect(MiguResponseCipher.decrypt([0xAB, 0xCD]), isNull);
      expect(MiguResponseCipher.decrypt([0xAB, 0xCD, 2, 1, 2, 3]), isNull);
    });

    test('内容不是 JSON 或密钥为空时返回 null', () {
      expect(MiguResponseCipher.decodeJson(seal('not-json')), isNull);
      expect(MiguResponseCipher.decrypt(seal('{"ok":true}'), key: ''), isNull);
    });
  });
}
