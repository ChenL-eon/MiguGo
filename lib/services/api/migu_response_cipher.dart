import 'dart:convert';
import 'dart:typed_data';

/// 咪咕部分播放接口的响应体传输编码。
///
/// 站点自己的网页 SDK 会给这类响应套上 4 字节头
/// （`0xAB 0xCD 0x01 <随机偏移>`），正文逐字节为
/// `明文 + 偏移 - 密钥`。这里只负责读取 JSON 响应体，
/// 不涉及音频文件本身，也不做任何下载。
class MiguResponseCipher {
  const MiguResponseCipher._();

  static const int _magicFirst = 0xAB;
  static const int _magicSecond = 0xCD;
  static const int _version = 1;

  /// 生产环境（env=0）随网页 SDK 一起下发的密钥。
  static const String productionKey = 'Jk8qzuePiJ1qE3mDYhLQ3T73DtDoAhLP';

  /// 解密响应体；格式不符时返回 null。
  static Uint8List? decrypt(List<int> data, {String key = productionKey}) {
    if (data.length < 4 || key.isEmpty) return null;
    if (data[0] != _magicFirst || data[1] != _magicSecond || data[2] != _version) {
      return null;
    }

    final offset = data[3];
    final keyBytes = utf8.encode(key);
    final plain = Uint8List(data.length - 4);
    for (var i = 0; i < plain.length; i++) {
      plain[i] = (data[i + 4] + offset - keyBytes[i % keyBytes.length]) & 0xFF;
    }
    return plain;
  }

  /// 解密并解析为 JSON；不是该编码或内容损坏时返回 null。
  static dynamic decodeJson(List<int> data, {String key = productionKey}) {
    final plain = decrypt(data, key: key);
    if (plain == null) return null;
    try {
      return jsonDecode(utf8.decode(plain));
    } catch (_) {
      return null;
    }
  }
}
