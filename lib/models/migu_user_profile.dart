import '../core/constants/app_constants.dart';
import '../core/utils/json_read.dart';

/// 咪咕账号公开资料：昵称、头像与会员标识，全部来自用户自己的登录会话。
class MiguUserProfile {
  const MiguUserProfile({
    this.nickname = '',
    this.avatarUrl = '',
    this.userId = '',
    this.msisdn = '',
    this.isVip = false,
  });

  final String nickname;
  final String avatarUrl;
  final String userId;
  final String msisdn;
  final bool isVip;

  String get maskedPhone {
    final digits = msisdn.trim();
    if (digits.length < 7) return '';
    return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
  }

  MiguUserProfile copyWith({bool? isVip}) {
    return MiguUserProfile(
      nickname: nickname,
      avatarUrl: avatarUrl,
      userId: userId,
      msisdn: msisdn,
      isVip: isVip ?? this.isVip,
    );
  }

  factory MiguUserProfile.fromPayload(dynamic payload) {
    final root = readMap(payload) ?? const <String, dynamic>{};
    final data =
        readMap(root['userInfo']) ??
        readMap(root['user']) ??
        readMap(root['data']) ??
        root;

    final nickname = _firstString(data, const [
      'nickName',
      'nickname',
      'userName',
      'userNickName',
      'name',
    ]);
    final rawAvatar = _firstString(data, const [
      'smallIcon',
      'bigIcon',
      'avatar',
      'avatarUrl',
      'headPic',
      'headImg',
      'portrait',
      'userIcon',
      'icon',
    ]);
    final userId = _firstString(data, const ['userId', 'uid', 'id']);
    final msisdn = _firstString(data, const [
      'msisdn',
      'phone',
      'mobile',
      'phoneNumber',
    ]);

    return MiguUserProfile(
      nickname: nickname,
      avatarUrl: _normalizeImageUrl(rawAvatar),
      userId: userId,
      msisdn: msisdn,
      isVip: detectVip(data),
    );
  }

  /// 会员标识可能出现在 `isVip`、`vipLevel`、会员图标等不同形态里。
  static const Set<String> _memberFields = {
    'member',
    'ismember',
    'memberflag',
    'memberlevel',
    'membertype',
    'memberstatus',
    'membername',
    'membership',
    'membershipstatus',
    'memberinfo',
    'membericon',
    'membertag',
    'memberexpire',
  };

  static bool detectVip(dynamic payload) {
    var found = false;

    bool checkKey(String key, dynamic value) {
      final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');
      final isVipField = normalized.contains('vip');
      final isMemberField = _memberFields.contains(normalized);
      if (!isVipField && !isMemberField) {
        return false;
      }
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value > 0;
      final text = value.toString().trim().toLowerCase();
      if (text.isEmpty || text == '0' || text == 'false' || text == 'no') {
        return false;
      }
      if (text == '1' || text == 'true' || text == 'y' || text == 'yes') {
        return true;
      }
      return text.contains('vip') || text.contains('会员');
    }

    void visit(dynamic node) {
      if (found) return;
      if (node is Map) {
        for (final entry in node.entries) {
          if (checkKey(entry.key.toString(), entry.value)) {
            found = true;
            return;
          }
          visit(entry.value);
          if (found) return;
        }
        return;
      }
      if (node is List) {
        for (final item in node) {
          visit(item);
          if (found) return;
        }
      }
    }

    visit(payload);
    return found;
  }

  static String _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = readString(data[key]).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _normalizeImageUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '${AppConstants.miguImageBase}$url';
    return url;
  }
}
