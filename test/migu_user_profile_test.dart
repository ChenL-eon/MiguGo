import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/lyrics_style.dart';
import 'package:migu_lele/models/migu_user_profile.dart';

void main() {
  group('MiguUserProfile', () {
    test('解析昵称、头像、手机号与会员字段', () {
      final profile = MiguUserProfile.fromPayload({
        'nickName': '小咪',
        'smallIcon': '//d.musicapp.migu.cn/avatar.png',
        'userId': 123456,
        'msisdn': '13812345678',
        'vipLevel': 2,
      });

      expect(profile.nickname, '小咪');
      expect(profile.avatarUrl, 'https://d.musicapp.migu.cn/avatar.png');
      expect(profile.userId, '123456');
      expect(profile.maskedPhone, '138****5678');
      expect(profile.isVip, isTrue);
    });

    test('兼容嵌套 userInfo 与相对头像路径', () {
      final profile = MiguUserProfile.fromPayload({
        'code': '000000',
        'userInfo': {
          'userName': '测试用户',
          'headPic': '/v1/avatar/head.jpg',
          'uid': 'u-1',
        },
      });

      expect(profile.nickname, '测试用户');
      expect(profile.avatarUrl, 'https://d.musicapp.migu.cn/v1/avatar/head.jpg');
      expect(profile.userId, 'u-1');
      expect(profile.isVip, isFalse);
    });

    test('非会员字段不会被误判为 VIP', () {
      final profile = MiguUserProfile.fromPayload({
        'nickName': '普通账号',
        'memberLevel': 0,
        'vipFlag': '0',
        'memberAmount': 12,
      });

      expect(profile.isVip, isFalse);
    });

    test('会员文案与布尔值都能识别', () {
      expect(MiguUserProfile.detectVip({'vipName': '咪咕黄金会员'}), isTrue);
      expect(MiguUserProfile.detectVip({'isMember': true}), isTrue);
      expect(
        MiguUserProfile.detectVip({
          'data': [
            {'key': 'normal'},
            {'vipLevel': 1},
          ],
        }),
        isTrue,
      );
      expect(MiguUserProfile.detectVip({'vipLevel': 0}), isFalse);
    });

    test('maskedPhone 在号码过短时返回空串', () {
      expect(const MiguUserProfile(msisdn: '12345').maskedPhone, '');
      expect(const MiguUserProfile(msisdn: '13812345678').maskedPhone, '138****5678');
    });

    test('copyWith 只覆盖会员标识', () {
      const source = MiguUserProfile(nickname: 'A', avatarUrl: 'B');
      final updated = source.copyWith(isVip: true);
      expect(updated.nickname, 'A');
      expect(updated.avatarUrl, 'B');
      expect(updated.isVip, isTrue);
    });
  });

  group('DesktopLyricsColor', () {
    test('未知或空名称回退为白色', () {
      expect(DesktopLyricsColor.fromName(null), DesktopLyricsColor.white);
      expect(DesktopLyricsColor.fromName('unknown'), DesktopLyricsColor.white);
    });

    test('按名称还原已保存的颜色', () {
      expect(DesktopLyricsColor.fromName('gold'), DesktopLyricsColor.gold);
      expect(DesktopLyricsColor.fromName('mint'), DesktopLyricsColor.mint);
    });
  });
}
