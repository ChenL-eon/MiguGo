import 'dart:convert';

/// 官方音乐站登录完成后要回到的页面。
const String miguMusicLoginCallbackUrl = 'https://music.migu.cn/v5/';

/// 构造官方通行证的全页登录地址。
///
/// 官方音乐站的 newPageMode 通过 `relayState` 告知通行证登录完成后的回跳
/// 地址；缺少该参数时，通行证不会回到咪咕音乐，页面会停在等待 opener 的
/// 登录成功页。官方 JS 的原始构造为：
/// `relayState = btoa(JSON.stringify({callbackURL, activityId}))`，
/// 其中 activityId 仅用于统计，未提供时会被 JSON 序列化省略。
String buildMiguPassportLoginUrl({String callbackUrl = miguMusicLoginCallbackUrl}) {
  final relayState = base64Encode(
    utf8.encode(jsonEncode({'callbackURL': callbackUrl})),
  );
  return Uri.https('passport.migu.cn', '/login', {
    'sourceid': '220029',
    'forceAuthn': 'true',
    'hideRegister': '1',
    'hideForgetPass': '1',
    'relayState': relayState,
  }).toString();
}
