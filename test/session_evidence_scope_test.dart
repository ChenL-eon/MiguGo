import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/auth/session_reject_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';
import 'support/reject_ledger.dart';

const String _userInfoUrl = 'https://app.c.nf.migu.cn/user/h5/user-info/v1.0';
const String _pacmCheckUrl = 'https://c.musicapp.migu.cn/mgateway/api/checkPacMtoken';

/// 账号接口缺 `uid` 也回「请先登录」，这种回能不能被算成凭据失效。
///
/// 原生登录本机没有 `uid`，一旦计入，两次就够把还好用的凭据自动退掉。
/// 2026-10-25 实测：这三个账号接口对「不带凭据」「只带假 pacmtoken」「假
/// pacmtoken 再加 uid」回的是同一句 `290001 请先登录`，所以它分不清过期与缺参；
/// 只认 `pacmtoken` 的官方校验接口（未登录时回 `850001 未登录`）才说得出凭据本身。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(MiguApiClient, SessionRejectLedger, List<int>)> build(
    String rawCookies,
  ) async {
    final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
    await store.init();
    await store.importLoginCookies(rawCookies);
    final (ledger, _) = testLedger();
    final revoked = <int>[];
    final client = MiguApiClient(
      cookieStore: store,
      ledger: ledger,
      onSessionRevoked: () => revoked.add(1),
    );
    return (client, ledger, revoked);
  }

  void reject(
    MiguApiClient client, {
    String url = _userInfoUrl,
    String code = '290001',
    String info = '请先登录',
  }) => client.noteAuthFailure(
    uri: Uri.parse(url),
    status: 200,
    code: code,
    info: info,
  );

  test('只有 pacmtoken 的原生登录：缺 uid 的回绝只留证据', () async {
    final (client, ledger, revoked) = await build('pacmtoken=p1');

    reject(client);

    expect(revoked, isEmpty);
    expect(ledger.strikes, 0);
    expect(ledger.lastAccount, isNull);
    // 证据仍然留下，界面上说得出最近一次是被谁拒的。
    expect(ledger.last?.path, '/user/h5/user-info/v1.0');
    expect(ledger.last?.loginScoped, isFalse);
  });

  test('账号歌单与资料接口缺 uid 时一视同仁', () async {
    final (client, ledger, revoked) = await build('pacmtoken=p1');

    for (final url in const [
      'https://app.c.nf.migu.cn/pc/user/home-page/v2.0',
      'https://app.c.nf.migu.cn/pc/user/h5/queryUserInfo/v1.0',
      _userInfoUrl,
    ]) {
      reject(client, url: url);
    }

    expect(revoked, isEmpty);
    expect(ledger.strikes, 0);
    expect(ledger.lastAccount, isNull);
  });

  test('带上 uid 后，同一条回绝照常计入失效判定', () async {
    final (client, ledger, revoked) = await build('pacmtoken=p1; uid=u1');

    reject(client);

    expect(revoked, hasLength(1));
    expect(ledger.strikes, 1);
    expect(ledger.lastAccount?.path, '/user/h5/user-info/v1.0');
  });

  test('官方校验接口只认 pacmtoken，它说未登录就算凭据被拒', () async {
    // 缺 uid 也一样算：这个接口不需要 uid，「未登录」只能是这份 pacmtoken 的问题。
    final (client, ledger, revoked) = await build('pacmtoken=p1');

    reject(client, url: _pacmCheckUrl, code: '850001', info: '未登录');

    expect(revoked, hasLength(1));
    expect(ledger.strikes, 1);
    expect(ledger.lastAccount?.path, '/mgateway/api/checkPacMtoken');
  });

  test('本机没带凭据时，官方校验接口的未登录不打扰用户', () async {
    final (client, ledger, revoked) = await build('sid=s1');

    reject(client, url: _pacmCheckUrl, code: '850001', info: '未登录');

    expect(revoked, isEmpty);
    expect(ledger.strikes, 0);
  });
}
