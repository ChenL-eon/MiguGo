import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account_library.dart';
import '../models/auth_session.dart';
import '../models/migu_user_profile.dart';
import '../services/api/auth_session_store.dart';
import '../services/api/migu_api_exception.dart';
import '../services/api/migu_cookie_store.dart';
import '../services/api/migu_music_api.dart';
import '../services/api/passport_ticket_store.dart';
import '../services/api/secure_cookie_storage.dart';
import '../services/auth/migu_passport_api.dart';
import '../services/auth/session_probe.dart';
import '../services/auth/session_probe_diagnostics.dart';
import '../services/auth/session_reject_ledger.dart';

/// 管理咪咕登录凭据与本地认证状态。
///
/// 凭据来源只有两处：账号弹窗里的原生登录（短信验证码、账号密码），
/// 以及图形验证码兜底时临时打开的官方登录窗口。
/// 应用不校验也不推断 VIP 权限，只把用户自己的凭据随请求发送；
/// “已验证”表示咪咕服务端发放或接受了这份凭据。
class AccountProvider extends ChangeNotifier {
  AccountProvider({
    MiguCookieStore? cookieStore,
    AuthSessionStore? authSessionStore,
    PassportTicketStore? passportTicketStore,
    MiguPassportApi? passportApi,
    SessionRejectLedger? ledger,
    this.diagnostics,
    this.onSessionEstablished,
    this.onSessionLost,
    this.onAutoSignOut,
  }) : _cookieStore = cookieStore ?? MiguCookieStore.instance,
       _authSessionStore =
           authSessionStore ?? AuthSessionStore(storage: FlutterSecureCookieStorage()),
       _ticketStore =
           passportTicketStore ??
           PassportTicketStore(storage: FlutterSecureCookieStorage()),
       _injectedPassport = passportApi,
       _ledger = ledger ?? SessionRejectLedger.instance;

  final MiguCookieStore _cookieStore;
  final AuthSessionStore _authSessionStore;
  final PassportTicketStore _ticketStore;
  final MiguPassportApi? _injectedPassport;

  /// 调试版的登录探测记录。调试入口主动换票的结果也写进同一份记录，现场才能
  /// 看出这张票到底换没换到新凭据；正式版自己会不写。
  final SessionProbeDiagnostics? diagnostics;

  /// 「凭据被拒」的取证与计数；里面只有接口地址和服务端编码，没有凭据。
  final SessionRejectLedger _ledger;

  /// 只有走到原生登录才构造网络层，只用官方页面的用户不必多一个 Dio。
  late final MiguPassportApi _passport = _injectedPassport ?? MiguPassportApi();

  /// 拿到新的登录凭据（原生登录或官方窗口读到的会话）后触发，用于重新挂载前台保活。
  final VoidCallback? onSessionEstablished;

  /// 凭据被服务端回绝后触发，用于停掉前台保活。
  final VoidCallback? onSessionLost;

  /// 会话被咪咕明确回绝后触发，宿主需要在这里清凭据并复位播放。
  final Future<void> Function()? onAutoSignOut;

  AuthSession _session = AuthSession.none;
  String? _sessionWarning;
  String? _autoSignOutNotice;
  bool _initialized = false;

  /// 原生登录留下的通行证票据。咪咕在第一次换票时就把这张票用掉了，它换不回
  /// 第二个会话（2026-10-26 真机确认），所以本机只是留着它，供调试入口复测。
  String? _ticket;

  /// 票据的修订号：每次写入、删除或条件清理都 +1。
  /// 被作废的登录只能用自己那次写入的修订号撤回票据，不能碰到新登录的。
  int _ticketRevision = 0;

  /// 正在续期的那次会话代数；旧会话的续期不能占住新会话的名额。
  int? _renewingEpoch;

  /// 凭据代数：换号、退出都会 +1。续期是异步的，恢复执行时必须确认
  /// 期间没有发生换号或退出，否则旧会话的结果会写进新会话。
  int _credentialEpoch = 0;

  /// 登录操作代数：每次发起登录、官方导入或退出都 +1。
  /// 它与 [_credentialEpoch] 不同——请求在途时还没有建立新会话，
  /// 只有发起时记下操作代数，才能让新一次登录作废上一次挂起的登录。
  int _loginAttempt = 0;

  /// 认证状态的修订号：每次改写 [_session] 都 +1。
  /// 落盘是异步的，排队期间若已经退出、换号或产生更新的状态，旧快照不能再写回。
  int _sessionRevision = 0;

  /// 认证状态的落盘队列：写入与退出时的删除都按发起顺序串行执行。
  Future<void> _authPersistQueue = Future<void>.value();
  MiguMusicApi? _api;
  MiguUserProfile? _profile;
  bool _profileLoading = false;
  int _profileRequest = 0;
  int _profileLoadingEpoch = -1;
  String? _profileError;
  AccountLibrary? _library;
  bool _libraryLoading = false;
  int _libraryRequest = 0;
  int _libraryLoadingEpoch = -1;
  String? _libraryError;

  bool get hasLogin => _cookieStore.hasImportedLogin;

  /// 当前凭据代数；网络层用它标记请求发起时属于哪一次会话。
  int get credentialEpoch => _credentialEpoch;

  MiguUserProfile? get profile => _profile;

  bool get isVip => _profile?.isVip ?? false;

  bool get profileLoading => _profileLoading;

  String? get profileError => _profileError;

  AccountLibrary? get library => _library;

  bool get libraryLoading => _libraryLoading;

  String? get libraryError => _libraryError;

  String get avatarUrl => _profile?.avatarUrl ?? '';

  String get displayName {
    if (!hasLogin) return '未登录';
    final nickname = _profile?.nickname.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final phone = _profile?.maskedPhone ?? '';
    if (phone.isNotEmpty) return phone;
    return '咪咕音乐账号';
  }

  /// 网络层在账号创建之后才能构造，这里补挂资料请求入口。
  void attachApi(MiguMusicApi api) {
    _api = api;
  }

  Future<void> refreshProfile() async {
    final api = _api;
    if (!hasLogin || api == null) return;
    final epoch = _credentialEpoch;
    // 只挡住同一会话里的重复请求；换号后旧请求不该让新会话永远等下去。
    if (_profileLoading && _profileLoadingEpoch == epoch) return;
    final request = ++_profileRequest;
    _profileLoading = true;
    _profileLoadingEpoch = epoch;
    _profileError = null;
    notifyListeners();
    try {
      final profile = await api.fetchUserProfile();
      if (!_stillOwnsRequest(request, epoch)) return;
      _profile = profile;
    } on MiguApiException catch (error) {
      if (!_stillOwnsRequest(request, epoch)) return;
      _profileError = error.message;
    } catch (_) {
      if (!_stillOwnsRequest(request, epoch)) return;
      _profileError = '账号资料暂时无法读取。';
    } finally {
      if (request == _profileRequest) {
        _profileLoading = false;
        notifyListeners();
      }
    }
  }

  /// 这次异步请求是否仍属于当前会话，且没有被同会话的更新请求取代。
  bool _stillOwnsRequest(int request, int epoch) =>
      hasLogin && _credentialEpoch == epoch && request == _profileRequest;

  bool _stillOwnsLibraryRequest(int request, int epoch) =>
      hasLogin && _credentialEpoch == epoch && request == _libraryRequest;

  int get cookieCount => _cookieStore.importedCookieCount;

  /// 读取当前账号的我喜欢、自建歌单与收藏歌单；只读，不改动账号内容。
  Future<void> refreshLibrary({bool force = false}) async {
    final api = _api;
    if (!hasLogin || api == null) return;
    final epoch = _credentialEpoch;
    // 换号后旧请求仍在飞，也不能让新账号的歌单刷新被跳过。
    if (_libraryLoading && _libraryLoadingEpoch == epoch) return;
    if (!force && _library != null) return;
    final request = ++_libraryRequest;
    _libraryLoading = true;
    _libraryLoadingEpoch = epoch;
    _libraryError = null;
    notifyListeners();
    try {
      final library = await api.fetchAccountLibrary();
      if (!_stillOwnsLibraryRequest(request, epoch)) return;
      _library = library;
    } on MiguApiException catch (error) {
      if (!_stillOwnsLibraryRequest(request, epoch)) return;
      _libraryError = error.message;
    } catch (_) {
      if (!_stillOwnsLibraryRequest(request, epoch)) return;
      _libraryError = '账号歌单暂时无法读取。';
    } finally {
      if (request == _libraryRequest) {
        _libraryLoading = false;
        notifyListeners();
      }
    }
  }

  /// 本机凭证里是否含咪咕音乐网页登录会话。
  bool get hasWebSessionCookie => _cookieStore.hasWebSessionCookie;

  /// 本机有凭据、但缺咪咕音乐登录会话：VIP 请求会被直接拦下并提示。
  bool get hasIncompleteLogin => hasLogin && !hasWebSessionCookie;

  AuthStatus get status => _session.status;

  /// 上一次会话被咪咕明确回绝、因而被自动退出的说明；重新登录才收起。
  ///
  /// [signOut] 不清这条：自动退出正是走它，清了用户就看不到自己为什么掉线，
  /// 而手动退出只可能发生在重新登录之后，那时这条已经被收起了。
  String? get autoSignOutNotice => _autoSignOutNotice;

  DateTime? get importedAt => _session.importedAt;

  DateTime? get lastCheckedAt => _session.lastCheckedAt;

  String get statusLabel {
    if (hasIncompleteLogin) return '已登录，缺少音乐登录会话';
    return switch (_session.status) {
      AuthStatus.none => _autoSignOutNotice == null ? '未登录' : '登录已失效，已自动退出',
      AuthStatus.unverified => '已保存登录凭据',
      AuthStatus.verified => '登录凭据已验证',
      AuthStatus.rejected => '登录可能已失效',
    };
  }

  String get statusHint {
    if (hasIncompleteLogin) {
      return '本机凭据里没有咪咕音乐的登录会话（pacmtoken / mg_auth_sid）。'
          'VIP 曲目需要它才能向咪咕申请播放地址；重新登录一次即可覆盖这份旧凭据。';
    }
    return switch (_session.status) {
      AuthStatus.none => _autoSignOutNotice ?? '未登录时，原生播放器只播放免费曲目。',
      AuthStatus.unverified =>
        '已保存登录凭据。VIP 曲目会用这份凭据向咪咕申请播放地址，'
            '能否播放由账号权益决定；如果咪咕拒绝，可点播放页的“官方页面播放”兜底。',
      AuthStatus.verified => '咪咕服务端已接受当前登录凭据。VIP 曲目能否播放，仍由账号权益决定。',
      AuthStatus.rejected =>
        '最近一次请求被拒绝：登录可能已失效，也可能是账号没有该歌曲权限。'
            '本机留存的登录票据在登录那一次就被咪咕用掉了，换不来新凭据，'
            '在上方重新登录一次即可恢复。'
            '${_rejectedEvidenceSuffix()}',
    };
  }

  /// 说明这次「可能失效」到底是哪个接口回的什么，并讲清凭据还在、还差几次才退登。
  String _rejectedEvidenceSuffix() {
    // 账号请求之后常跟着歌词、封面这类公开请求，它们也失败时不能顶掉真正的原因。
    final evidence = _ledger.lastAccount ?? _ledger.last;
    if (evidence == null) return '';
    final confirmed = _ledger.strikes >= 2 ? '已凑够两次，即将自动退出。' : '凭据仍保留。';
    return '$confirmed最近一次拒绝：${evidence.summary}';
  }

  /// 安全存储或迁移异常；非空时界面必须明确提示。
  String? get storageWarning => _sessionWarning ?? _cookieStore.storageWarning;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    var stored = AuthSession.none;
    try {
      stored = await _authSessionStore.read();
    } on SecureCookieStorageException {
      _sessionWarning = '无法读取登录状态记录，当前状态以本次运行为准。';
    }

    if (!_cookieStore.hasImportedLogin) {
      _setSession(AuthSession.none);
    } else {
      // 上次的“已验证”不能跨重启直接采信，重启后统一回到未验证。
      _setSession(
        AuthSession(
          status: AuthStatus.unverified,
          importedAt: stored.importedAt ?? DateTime.now(),
        ),
      );
    }

    try {
      _ticket = await _ticketStore.read();
    } on SecureCookieStorageException {
      _ticket = null;
    }
    if (!_cookieStore.hasImportedLogin && _ticket != null) {
      // 凭据已经不在这台机器上，票据单独留着就是一份多余凭据。
      _ticket = null;
      try {
        await _ticketStore.clear();
      } on SecureCookieStorageException {
        // 下次启动再清，读不到凭据时这张票也无从使用。
      }
    }
    notifyListeners();
  }

  /// 保存官方登录窗口读到的 Cookie；应用内没有手动粘贴入口。
  Future<int> importLoginCookie(String raw) async {
    final attempt = ++_loginAttempt;
    final epoch = ++_credentialEpoch;
    // 官方页面登录没有登录票据；旧票据必须在覆盖 Cookie 之前丢掉，
    // 否则在途续期仍认旧票据，能在写入新凭据的间隙把旧账号换回来。
    await _forgetTicket();
    if (!_isCurrentLogin(attempt, epoch)) return 0;
    final count = await _cookieStore.importLoginCookies(raw);
    // 写凭据期间可能已经退出或被另一次登录替换，旧流程不能再改当前状态。
    if (!_isCurrentLogin(attempt, epoch)) return count;
    // 新凭据不带旧账：上一次会话的失败不能算到这一次头上。
    _ledger.clear();
    _setSession(AuthSession(status: AuthStatus.unverified, importedAt: DateTime.now()));
    _profile = null;
    _profileError = null;
    _library = null;
    _libraryError = null;
    _sessionWarning = null;
    _autoSignOutNotice = null;
    notifyListeners();
    await _persistSession();
    // 落盘期间退出或换号时，旧登录流程不能再恢复保活或改新会话的数据。
    if (!_isCurrentLogin(attempt, epoch)) return count;
    onSessionEstablished?.call();
    if (hasWebSessionCookie) {
      unawaited(refreshProfile());
      unawaited(refreshLibrary(force: true));
    }
    return count;
  }

  /// 这次登录操作是否仍然有效：期间没有发起更新的登录，也没有建立新会话或退出。
  bool _isCurrentLogin(int attempt, int epoch) =>
      _loginAttempt == attempt && _credentialEpoch == epoch;

  /// 取一张图形验证码交给用户本人识别；应用不自动识别图片内容。
  Future<MiguGraphCaptcha> requestLoginCaptcha({
    required MiguImgcodeType type,
    bool refresh = false,
  }) => _passport.fetchGraphCaptcha(type, refresh: refresh);

  /// 把用户输入的字符交给咪咕校验；通过后本次会话的风险标记才会被摘掉。
  Future<void> verifyLoginCaptcha({
    required MiguImgcodeType type,
    required String captcha,
  }) => _passport.verifyGraphCaptcha(type, captcha);

  /// 原生登录第一步：请咪咕下发短信验证码。验证码只在这一次请求里出现，本机不保存。
  Future<void> requestLoginCode(String phone, {String captcha = ''}) =>
      _passport.sendSmsCode(phone, captcha: captcha);

  /// 原生登录：短信验证码。返回咪咕给出的打码手机号，可能为空。
  Future<String?> signInWithSmsCode({
    required String phone,
    required String code,
    String captcha = '',
  }) => _applyLoginSession(
    () => _passport.loginWithSmsCode(phone, code, captcha: captcha),
  );

  /// 原生登录：账号密码。密码只在请求中加密传输，本机绝不保存。
  Future<String?> signInWithPassword({
    required String username,
    required String password,
    String captcha = '',
  }) => _applyLoginSession(
    () => _passport.loginWithPassword(username, password, captcha: captcha),
  );

  /// 保存原生登录换来的会话，并按「服务端已发放凭据」更新状态。
  Future<String?> _applyLoginSession(Future<MiguLoginSession> Function() login) async {
    // 请求还没发出就先占住这一次操作；期间退出或开始另一次登录时，
    // 网络回来的旧结果不能再写凭据、改状态或恢复保活。
    final attempt = ++_loginAttempt;
    final session = await login();
    if (_loginAttempt != attempt) return null;
    final epoch = ++_credentialEpoch;
    // 先丢掉旧票据再覆盖 Cookie：旧账号的票配上新账号的 Cookie，
    // 一旦触发续期就会把人换回上一个账号。
    await _forgetTicket();
    if (!_isCurrentLogin(attempt, epoch)) return null;
    final applied = await _cookieStore.applyNativeLoginSession(session.cookies);
    if (!_isCurrentLogin(attempt, epoch)) {
      // 凭据已经写进去了，这次登录却被更新的操作作废。只能按完整快照撤回：
      // 期间新登录若已换过凭据，快照或修订号不同，这里保持新凭据不动。
      await _cookieStore.clearLoginCookiesIfUnchanged(
        snapshot: applied.snapshot,
        revision: applied.revision,
      );
      return null;
    }
    // 票据是本次登录最后一项异步提交：写失败只提示，不影响会话本身；
    // “已验证”必须等它落盘之后再提交，否则期间被作废的登录会留下假会话。
    _sessionWarning = null;
    _autoSignOutNotice = null;
    final ticketRevision = await _rememberTicket(session.token);
    if (!_isCurrentLogin(attempt, epoch)) {
      // 这次登录已被作废：只撤回它自己写下的 Cookie 与票据。
      // 期间若有新登录换过值，凭据快照、修订号或票据修订号会对不上，不会误删。
      await _discardStaleLogin(
        applied: applied,
        ticket: session.token,
        ticketRevision: ticketRevision,
      );
      return null;
    }
    _ledger.clear();
    final now = DateTime.now();
    _setSession(
      AuthSession(status: AuthStatus.verified, importedAt: now, lastCheckedAt: now),
    );
    _profile = null;
    _profileError = null;
    _library = null;
    _libraryError = null;
    notifyListeners();
    await _persistSession();
    if (!_isCurrentLogin(attempt, epoch)) return null;
    onSessionEstablished?.call();
    unawaited(refreshProfile());
    unawaited(refreshLibrary(force: true));
    return session.maskedPhone;
  }

  /// 带凭据的 VIP 播放请求成功，说明咪咕服务端接受了当前登录。
  void markVerified() {
    if (!_cookieStore.hasImportedLogin) return;
    // 凭据被接受过一次，之前的失败就不再算数；否则旧账会和新的一次凑成“确认失效”。
    _ledger.resetStrikes();
    if (_session.status == AuthStatus.verified) return;
    _setSession(
      _session.copyWith(status: AuthStatus.verified, lastCheckedAt: DateTime.now()),
    );
    notifyListeners();
    unawaited(_persistSession());
  }

  /// 带凭据的播放请求被 401/403 或业务权限码拒绝。
  ///
  /// 403 无法区分“Cookie 失效”和“账号无该歌曲权限”，因此状态只描述为可能失效。
  void markRejected() {
    if (!_cookieStore.hasImportedLogin) return;
    _setSession(
      _session.copyWith(status: AuthStatus.rejected, lastCheckedAt: DateTime.now()),
    );
    notifyListeners();
    unawaited(_persistSession());
  }

  /// 咪咕回绝了一个要求登录的账号接口（HTTP 401 或业务码“请先登录”）。
  ///
  /// 第一次只把状态降级、把证据留下，凭据照旧保留；隔过
  /// [SessionRejectLedger.confirmGap] 之后再次被拒，才认定这份凭据真的作废，
  /// 走自动退出。期间只要有一次账号接口成功，计数就清零。
  ///
  /// 这里原来会先用留存的通行证票据静默换一次会话再裁决。2026-10-26 真机确认
  /// 那张票在第一次换票时就被咪咕消耗掉了：会话还认的时候（同一份凭据几秒前刚回
  /// `000000`），拿签发不到一分钟的票据再换一次，回的是 `HTTP 200 + 199999`，
  /// 不下发新的 `pacmtoken`。那次请求注定失败，却因为分类成「分不清票据问题还是
  /// 服务抖动」而只走到 `markRejected`，把上面这套两步判定整段吞掉——界面长期
  /// 挂着已经死掉的凭据，功能坏着却不自动退出，只能用户手动重登。所以自动路径
  /// 不再发这个请求；换票本身留给 [debugRenewNow] 复测用。
  ///
  /// 403 不走这里——那可能只是这首歌没有权益，见 [markRejected]。
  void markSessionRevoked() {
    if (!hasLogin) return;
    // 一次手动续期在飞时不叠加裁决，等它自己收尾。
    if (_renewingEpoch == _credentialEpoch) return;
    _applyRevocation();
  }

  /// 往调试记录里写一条续期事件，[verdict] 借用探测那三个值表示结果。
  ///
  /// [error] 带上时顺手记它的 HTTP 状态与业务码：「分不清票据还是服务抖动」
  /// 这一档全靠这两个数才有意义，只看句子分不出是 403 风控还是 200+199999。
  void _noteRenewal(
    SessionProbe verdict,
    String note, {
    bool rotated = false,
    MiguLoginException? error,
  }) {
    final diagnostics = this.diagnostics;
    if (diagnostics == null || !diagnostics.enabled) return;
    unawaited(
      diagnostics.record(
        SessionProbeRecord(
          at: DateTime.now(),
          trigger: SessionProbeDiagnostics.renewalTrigger,
          verdict: verdict,
          officialStatus: error?.httpStatus,
          officialCode: error?.officialCode ?? '',
          // 借 officialInfo 这一格放回包形态；探测行才用它装服务端文案。
          officialInfo: error?.bodyHint ?? '',
          rotated: rotated,
          note: note,
        ),
      ),
    );
  }

  /// 调试用：不等探测判死，立刻用留存票据试一次换票，结果照旧写进探测记录。
  ///
  /// 「票据到底换不回第二个会话」就是这个入口测出来的：2026-10-26 在刚登录完、
  /// 同一份凭据几秒前才回过 `000000` 的当口按下，两次都拿到 `HTTP 200 + 199999`
  /// 且不下发新的 `pacmtoken`。自动路径因此不再发这个请求（见 [markSessionRevoked]），
  /// 但保留这条手动测法：哪天咪咕改了新接口或让票据可复用，一次点击就能看出来。
  String debugRenewNow() {
    final ticket = _ticket;
    if (!hasLogin || ticket == null) {
      _noteRenewal(SessionProbe.unknown, '调试：本机没有可用票据');
      return '本机没有留存票据，这次没试';
    }
    // 一次只让一个续期在飞，别叠上去把结果搅混。
    if (_renewingEpoch == _credentialEpoch) {
      _noteRenewal(SessionProbe.unknown, '调试：已有一次续期在飞，这次不叠加');
      return '已有一次续期在飞，这次没叠加';
    }
    _noteRenewal(SessionProbe.unknown, '调试：主动发起一次续期');
    unawaited(_renewSession(ticket));
    return '已发起一次换票';
  }

  void _applyRevocation() {
    if (!hasLogin) return;
    if (_ledger.strikes < 2) {
      markRejected();
      return;
    }
    _confirmRevoked();
  }

  /// 用留存的登录票据换一份新会话；只有 [debugRenewNow] 会走这里。
  Future<void> _renewSession(String ticket) async {
    final epoch = _credentialEpoch;
    // 换票期间的凭据改写只认这一代登录：期间退出或换号，结果不准写回。
    final generation = _cookieStore.webSyncToken;
    _renewingEpoch = epoch;
    try {
      final renewed = await _passport.renewSession(ticket);
      final pacmtoken = renewed.cookies['pacmtoken'] ?? '';
      if (pacmtoken.isEmpty) {
        _noteRenewal(SessionProbe.unknown, '咪咕回包了，但没下发新的 pacmtoken');
        return;
      }
      // 期间用户可能已经退出或换了账号，那份凭证不能写回去。
      if (!_isCurrentSession(epoch, ticket)) return;

      await _cookieStore.applyRenewedCredentials(
        renewed.cookies,
        loginGeneration: generation,
      );
      // 写凭据本身也要 await：期间若完成换号或退出，只认新的那份会话。
      if (!_isCurrentSession(epoch, ticket)) return;

      _ledger.clear();
      final now = DateTime.now();
      _setSession(
        AuthSession(
          status: AuthStatus.verified,
          importedAt: _session.importedAt ?? now,
          lastCheckedAt: now,
        ),
      );
      _profileError = null;
      _sessionWarning = null;
      notifyListeners();
      await _persistSession();
      // 状态落盘本身也可能跨越退出登录：收尾回调只能在会话仍然有效时触发。
      if (!_isCurrentSession(epoch, ticket)) return;
      _noteRenewal(
        SessionProbe.alive,
        '换到新凭据并写回，计数清零，状态回到已验证',
        rotated: true,
      );
      onSessionEstablished?.call();
      unawaited(_refreshAfterRenewal());
    } on MiguLoginException catch (error) {
      // 请求没到达咪咕就谈不上「凭据被拒」：弱网里一次掉线不该替服务端把账记满，
      // 更不该把用户永久登出。状态保持原样，等下一次真的问到结果再说。
      if (error.networkInterrupted) {
        _noteRenewal(SessionProbe.unknown, '请求没到达咪咕，没问到结果');
        return;
      }
      if (!_isCurrentSession(epoch, ticket)) return;
      // 咪咕答了但答案分不清票据问题还是服务抖动：只降级状态，凭据原样保留。
      // 只有 HTTP 401 这种明确回绝才允许进入作废判定。
      if (error.transient) {
        _noteRenewal(
          SessionProbe.unknown,
          '咪咕答了但分不清票据问题还是服务抖动',
          error: error,
        );
        markRejected();
        return;
      }
      _noteRenewal(SessionProbe.revoked, '咪咕明确回绝这张票据', error: error);
      _applyRevocation();
    } catch (_) {
      // 意料之外的错误同样证明不了凭据作废：只降级状态、留证据，凭据照旧保留。
      _noteRenewal(SessionProbe.unknown, '意料之外的异常，证明不了凭据作废');
      if (_isCurrentSession(epoch, ticket)) markRejected();
    } finally {
      // 只结束自己那一次；期间新会话可能已经发起了新的续期。
      if (_renewingEpoch == epoch) _renewingEpoch = null;
    }
  }

  /// 续期途中凭据是否仍属于发起它的那次会话。
  bool _isCurrentSession(int epoch, String ticket) =>
      hasLogin && _credentialEpoch == epoch && _ticket == ticket;

  /// 续期成功后重拉刚才失败的那两份数据，界面才不会停在旧错误上。
  Future<void> _refreshAfterRenewal() async {
    // 让正在收尾的那个请求先把错误写进状态，再重新发起。
    await Future<void>.delayed(Duration.zero);
    if (!hasLogin) return;
    unawaited(refreshProfile());
    unawaited(refreshLibrary(force: true));
  }

  /// 写入票据并返回这次写入的修订号；空票据不写盘，返回 null。
  ///
  /// Future 返回只代表存储操作结束，调用方仍须用修订号确认期间没有
  /// 新登录或退出改写票据。
  Future<int?> _rememberTicket(String? token) async {
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      _ticket = null;
      _ticketRevision++;
      return null;
    }
    _ticket = trimmed;
    final revision = ++_ticketRevision;
    try {
      await _ticketStore.write(trimmed);
    } on SecureCookieStorageException {
      _setSessionWarning('系统安全存储不可用，登录票据只留在本次运行内，重启后调试入口没法再复测。');
    }
    return revision;
  }

  Future<void> _forgetTicket() async {
    _ticket = null;
    _ticketRevision++;
    try {
      await _ticketStore.clear();
    } on SecureCookieStorageException {
      _setSessionWarning('系统安全存储不可用，本机登录票据未能删除。');
    }
  }

  /// 只撤回 [revision] 那次写入的票据；期间已有新登录或退出时保持原样。
  ///
  /// 比较与内存修改同步完成，不会给新登录留下插队窗口。删除排在票据队列里，
  /// 会晚于旧写入、早于之后的新登录写入，因此旧票据不会重新落盘。
  Future<void> _forgetTicketIfCurrent({
    required String? ticket,
    required int? revision,
  }) async {
    final trimmed = ticket?.trim() ?? '';
    if (trimmed.isEmpty || revision == null) return;
    if (_ticketRevision != revision || _ticket != trimmed) return;
    _ticket = null;
    _ticketRevision++;
    try {
      await _ticketStore.clear();
    } on SecureCookieStorageException {
      _setSessionWarning('系统安全存储不可用，本机登录票据未能删除。');
    }
  }

  /// 撤回一次已被作废的登录：先作废票据，再按完整快照撤回 Cookie。
  Future<void> _discardStaleLogin({
    required ({Map<String, String> snapshot, int revision}) applied,
    required String? ticket,
    required int? ticketRevision,
  }) async {
    await _forgetTicketIfCurrent(ticket: ticket, revision: ticketRevision);
    await _cookieStore.clearLoginCookiesIfUnchanged(
      snapshot: applied.snapshot,
      revision: applied.revision,
    );
  }

  void _confirmRevoked() {
    final evidence = _ledger.lastAccount ?? _ledger.last;
    onSessionLost?.call();
    _autoSignOutNotice =
        '咪咕已拒绝本机保存的登录凭据'
        '${evidence == null ? '' : '（最近一次：${evidence.summary}）'}，'
        '已自动退出登录并清空播放列表。重新登录一次即可继续听需要登录的曲目。';
    notifyListeners();
    _ledger.clear();
    unawaited(onAutoSignOut?.call());
  }

  /// 退出登录：清掉本机保存的凭据与状态记录，并停掉前台保活。
  ///
  /// 咪咕没有登出接口，这一步只动本机；设置、搜索历史与导入歌单不在清除范围内。
  Future<void> signOut() async {
    _loginAttempt++;
    _credentialEpoch++;
    // 退出先在内存里完成，并把删除排进各自的队列，之后才等存储。
    // 这样新登录只能排在这次退出后面：旧退出的回调、保活停止和删除
    // 不会在 B 已经登录成功后再补一次，更不会删掉 B 刚写入的状态。
    final cookiesCleared = _cookieStore.clearLoginCookies();
    // 票据是凭据的一部分，退出就不该在这台机器上留下它。
    final ticketCleared = _forgetTicket();
    // 凭据已经不在这台机器上了，被拒记录留着也解释不了任何东西。
    _ledger.clear();
    _setSession(AuthSession.none);
    // 让在途请求作废，不能等它们回来再改一次状态或清掉下一次登录的加载态。
    _profileRequest++;
    _libraryRequest++;
    _profile = null;
    _profileError = null;
    _profileLoading = false;
    _library = null;
    _libraryError = null;
    _libraryLoading = false;
    _sessionWarning = null;
    notifyListeners();
    onSessionLost?.call();
    // 删除同样要在第一个 await 之前入队：B 写入的认证状态会排在它后面，
    // 旧退出才不会在存储完成顺序上删掉 B 的记录。
    final authCleared = _clearAuthSession();
    await cookiesCleared;
    await ticketCleared;
    await authCleared;
  }

  Future<void> _clearAuthSession() async {
    try {
      await _enqueueAuthPersist(() async {
        await _authSessionStore.clear();
      });
    } on SecureCookieStorageException {
      _setSessionWarning('系统安全存储不可用，本次运行内已退出，重启后可能仍需再退一次。');
    }
  }

  void _setSession(AuthSession session) {
    _session = session;
    _sessionRevision++;
  }

  Future<void> _enqueueAuthPersist(Future<void> Function() task) {
    final result = _authPersistQueue.then((_) => task());
    _authPersistQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _persistSession() {
    final revision = _sessionRevision;
    final snapshot = _session;
    return _enqueueAuthPersist(() async {
      // 排队期间可能已经退出、换号或产生了更新的状态；旧快照不能再落盘。
      if (revision != _sessionRevision) return;
      try {
        await _authSessionStore.write(snapshot);
      } on SecureCookieStorageException {
        _setSessionWarning('系统安全存储不可用，登录状态仅在本次运行内有效。');
      }
    });
  }

  void _setSessionWarning(String message) {
    if (_sessionWarning == message) return;
    _sessionWarning = message;
    notifyListeners();
  }
}
