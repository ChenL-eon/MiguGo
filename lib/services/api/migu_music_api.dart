import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/json_read.dart';
import '../../models/account_library.dart';
import '../../models/audio_quality.dart';
import '../../models/home_feed.dart';
import '../../models/migu_user_profile.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../auth/session_probe.dart';
import 'migu_api_client.dart';
import 'migu_api_exception.dart';
import 'migu_response_cipher.dart';

/// 咪咕网页公开接口的业务封装。
///
/// 说明：历史 v3 接口现已 301 重定向到 v5，因此这里使用当前可用的公开 PC 接口；
/// 所有请求均通过 [MiguApiClient] 自动携带 Referer、本地 Cookie 与账号请求头。
/// 不含音频文件解密、下载或批量抓取逻辑；VIP 曲目是否可播完全由服务端按账号权益决定。
class MiguMusicApi {
  /// [onSessionRevoked] 挂在默认构造的 [MiguApiClient] 上；注入 client 时由调用方自行挂载。
  MiguMusicApi({
    MiguApiClient? client,
    this.onAuthVerified,
    this.onAuthRejected,
    this.sessionEpoch,
    void Function()? onSessionRevoked,
  }) : client =
           client ??
           MiguApiClient(
             sessionEpoch: sessionEpoch,
             onSessionRevoked: onSessionRevoked,
           );

  final MiguApiClient client;

  /// 带登录凭据的 VIP 播放请求成功后回调，用于把状态更新为“已验证”。
  final void Function()? onAuthVerified;

  /// 带登录凭据的请求被明确拒绝后回调，用于把状态更新为“可能失效”。
  final void Function()? onAuthRejected;

  /// 当前凭据代数；播放请求发起时记下，回包时只允许仍属于当前会话的结果改状态。
  final int Function()? sessionEpoch;

  bool get hasImportedLogin => client.cookieStore.hasImportedLogin;

  /// 本机凭证里是否含咪咕音乐网页登录会话；用于区分提示文案。
  bool get hasWebSessionCookie => client.cookieStore.hasWebSessionCookie;

  /// 回包时这次请求是否仍属于当前会话；未接入代际时保持原来的回调行为。
  bool _isCurrentSession(int? epoch) =>
      sessionEpoch == null || sessionEpoch!() == epoch;

  /// 首页推送：咪咕每日推荐歌曲与首页推荐歌单。
  ///
  /// 推荐歌单模块失败时只隐藏歌单区，不影响歌曲推送。
  Future<HomeFeed> fetchHomeFeed() async {
    final daily = await client.getJson(
      AppConstants.dailyRecommendUrl,
      query: {'actionId': 1, 'index': 1, 'templateVersion': 5},
    );
    _ensureBusinessOk(daily);

    final songs = HomeFeed.songsFromDailyPayload(daily);
    if (songs.isEmpty) {
      throw const MiguApiException(
        '咪咕今日推荐暂时没有返回歌曲，请稍后再试。',
        kind: MiguErrorKind.invalidResponse,
      );
    }

    var playlists = const <PlaylistSummary>[];
    try {
      final index = await client.getJson(
        AppConstants.homeIndexUrl,
        query: {'templateVersion': 1},
      );
      _ensureBusinessOk(index);
      playlists = HomeFeed.playlistsFromIndexPayload(index);
    } on MiguApiException {
      // 歌单区是附加内容，失败时保留歌曲推送即可。
    }

    return HomeFeed(
      songs: songs,
      playlists: playlists,
      date: HomeFeed.dateFromDailyPayload(daily),
    );
  }

  /// 读取当前登录账号的昵称、头像与会员标识。
  ///
  /// 会员徽标接口失败时只隐藏 VIP 标识，不影响昵称与头像。
  Future<MiguUserProfile> fetchUserProfile() async {
    final payload = await client.getJson(AppConstants.userProfileUrl);
    _ensureBusinessOk(payload);
    final root = readMap(payload);
    final data =
        readMap(root?['data']) ?? readMap(root?['userInfo']) ?? readMap(root?['user']);
    if (data == null) {
      throw const MiguApiException('账号资料暂时无法读取。', kind: MiguErrorKind.invalidResponse);
    }

    var profile = MiguUserProfile.fromPayload(data);
    if (!profile.isVip) {
      final badgeVip = await _fetchVipBadge();
      if (badgeVip) profile = profile.copyWith(isVip: true);
    }
    if (profile.nickname.isEmpty &&
        profile.avatarUrl.isEmpty &&
        profile.userId.isEmpty) {
      throw const MiguApiException('账号资料暂时无法读取。', kind: MiguErrorKind.invalidResponse);
    }
    return profile;
  }

  /// 探一次登录态：只用本机已有凭据请求账号资料。
  ///
  /// 网页端还在用 `/pc/user/h5/queryUserInfo/v1.0`，但它要求官方签名上下文里的
  /// `uid`；本机凭据失效时它只会回 `299999 uid不能为空`，信号不如
  /// `/user/h5/user-info/v1.0` 明确（失效回 `290001 请先登录`），因此探后者。
  ///
  /// 门槛只看 `pacmtoken`：原生通行证登录只拿到这一份凭据，`uid` 是网页快照才有的
  /// 同名 Cookie。要求 `uid` 会让原生登录账号的保活永不发请求；而账号资料接口本身
  /// 并不要求 `uid`（`fetchUserProfile` 同样不带 `uid` 也在用这个地址）。缺 `uid`
  /// 时最坏是回一条说不清的失败，`classifySessionProbe` 把它归到 unknown，不会误判失效。
  /// 这里只做只读探测，不请求任何续期接口，也不会替用户重新登录。
  Future<SessionProbe> checkSessionAlive() async {
    final credentials = client.cookieStore.credentials;
    if (credentials.pacmtoken == null) return SessionProbe.unknown;
    try {
      final response = await client.getRaw(AppConstants.userProfileUrl);
      final map = readMap(response.data);
      return classifySessionProbe(
        status: response.statusCode ?? 0,
        code: readString(map?['code']),
        info: readString(map?['info'] ?? map?['msg']),
      );
    } on MiguApiException catch (error) {
      return error.kind == MiguErrorKind.authRequired
          ? SessionProbe.revoked
          : SessionProbe.unknown;
    } catch (_) {
      return SessionProbe.unknown;
    }
  }

  Future<bool> _fetchVipBadge() async {
    try {
      final payload = await client.getJson(AppConstants.userBadgeUrl);
      final map = readMap(payload);
      if (map != null) {
        final code = readString(map['code']).trim();
        if (code.isNotEmpty && code != '000000' && code != '200') {
          return false;
        }
        return MiguUserProfile.detectVip(map['data'] ?? map);
      }
      return MiguUserProfile.detectVip(payload);
    } catch (_) {
      return false;
    }
  }

  /// 读取当前登录账号的我喜欢、自建歌单与收藏歌单。
  ///
  /// 只读：不新建、不收藏，也不改动账号里的内容。
  Future<AccountLibrary> fetchAccountLibrary() async {
    final payload = await client.getJson(AppConstants.userHomePageUrl);
    _ensureBusinessOk(payload);
    final data = readMap(payload is Map ? payload['data'] : null);
    if (data == null) {
      throw const MiguApiException('账号歌单暂时无法读取。', kind: MiguErrorKind.invalidResponse);
    }
    return AccountLibrary.fromHomePageJson(data);
  }

  /// 搜索单曲。
  Future<List<Song>> searchSongs(
    String keyword, {
    int pageNo = 1,
    int pageSize = 30,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];

    final payload = await client.getJson(
      AppConstants.songSearchUrl,
      query: {'text': text, 'pageNo': pageNo, 'pageSize': pageSize},
    );
    _ensureBusinessOk(payload);

    dynamic rawList;
    if (payload is List) {
      rawList = payload;
    } else if (payload is Map) {
      rawList =
          payload['songList'] ??
          readMap(payload['data'])?['songList'] ??
          readMap(payload['songResultData'])?['result'];
    }
    if (rawList is! List) {
      throw const MiguApiException('歌曲搜索返回了无法识别的数据。');
    }

    return rawList
        .map(readMap)
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJson)
        .where((song) => song.contentId.isNotEmpty && song.name.isNotEmpty)
        .toList();
  }

  /// 搜索公开歌单。
  Future<List<PlaylistSummary>> searchPlaylists(
    String keyword, {
    int pageNo = 1,
    int pageSize = 20,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];

    final payload = await client.getJson(
      AppConstants.playlistSearchUrl,
      query: {
        'text': text,
        'pageNo': pageNo,
        'pageSize': pageSize,
        'searchSwitch': jsonEncode({'songlist': 1}),
      },
    );
    _ensureBusinessOk(payload);

    if (payload is! Map) {
      throw const MiguApiException('歌单搜索返回了无法识别的数据。');
    }
    final resultData =
        readMap(payload['songListResultData']) ??
        readMap(payload['songlistResultData']) ??
        readMap(readMap(payload['data'])?['songListResultData']);
    final rawList = resultData?['result'] ?? resultData?['list'];

    return readList(rawList)
        .map(readMap)
        .whereType<Map<String, dynamic>>()
        .map(PlaylistSummary.fromSearchJson)
        .where((playlist) => playlist.id.isNotEmpty)
        .toList();
  }

  Future<PlaylistSummary> fetchPlaylistInfo(String playlistId) async {
    final payload = await client.getJson(
      AppConstants.playlistInfoUrl,
      query: {'playlistId': playlistId},
    );
    _ensureBusinessOk(payload);
    final data = readMap(payload is Map ? payload['data'] : null);
    if (data == null) {
      throw const MiguApiException('歌单不存在或暂时无法访问。');
    }
    final playlist = PlaylistSummary.fromInfoJson(data);
    if (playlist.id.isEmpty) {
      throw const MiguApiException('歌单信息不完整，请稍后重试。');
    }
    return playlist;
  }

  Future<PlaylistSongsPage> fetchPlaylistSongs(
    String playlistId, {
    int pageNo = 1,
    int pageSize = 50,
  }) async {
    final payload = await client.getJson(
      AppConstants.playlistSongsUrl,
      query: {'pageNo': pageNo, 'pageSize': pageSize, 'playlistId': playlistId},
    );
    _ensureBusinessOk(payload);
    final data = readMap(payload is Map ? payload['data'] : null);
    if (data == null) {
      throw const MiguApiException('歌单歌曲暂时无法加载。');
    }

    final songs = readList(data['songList'])
        .map(readMap)
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJson)
        .where((song) => song.contentId.isNotEmpty)
        .toList();

    return PlaylistSongsPage(
      songs: songs,
      totalCount: readInt(data['totalCount'], songs.length),
      pageNo: pageNo,
      pageSize: pageSize,
    );
  }

  /// 获取待播放歌曲的临时在线播放地址。
  ///
  /// 免费曲目走 `listenSong.do`（成功时 302 + Location 明文地址）；
  /// VIP 曲目走网页播放器使用的 strategy 接口，由咪咕按当前账号权益
  /// 决定是否发放地址。地址只用于本次在线播放，不落盘。
  Future<String> resolvePlaybackUrl(
    Song song, {
    AudioQuality quality = AudioQuality.hq,
  }) async {
    if (song.contentId.isEmpty || song.copyrightId.isEmpty) {
      throw const MiguApiException(
        '歌曲信息不完整，无法获取播放链接。',
        kind: MiguErrorKind.invalidResponse,
      );
    }

    if (song.isVipOnly) return _resolveVipPlaybackUrl(song, quality);
    return _resolveFreePlaybackUrl(song, quality);
  }

  /// 免费曲目：登录账号且选择了更高音质时先走策略接口，失败再回退标准音质；
  /// 未登录时直接使用无需权益的 listenSong.do，保证任何情况下都能试听。
  Future<String> _resolveFreePlaybackUrl(Song song, AudioQuality quality) async {
    if (quality != AudioQuality.pq && hasImportedLogin) {
      try {
        // 免费曲目的高音质尝试不作为登录有效性的判据；
        // 认证状态交给后面的 listenSong.do 请求决定。
        final result = await _tryStrategyPlaybackUrl(song, quality, reportAuth: false);
        final url = result.url;
        if (url != null) return url;
      } on MiguApiException {
        // 账号没有该音质权益或策略接口临时异常时，仍回退到免费标准音质。
      }
    }
    return _resolveListenSongUrl(song);
  }

  Future<String> _resolveListenSongUrl(Song song) async {
    final sentCredentials = hasImportedLogin;
    final requestEpoch = sessionEpoch?.call();
    final response = await client.getRaw(
      AppConstants.listenSongUrl,
      query: {
        'toneFlag': AppConstants.playbackToneFlag,
        'netType': '00',
        'ua': 'Android_migu',
        'version': '5.1',
        'copyrightId': song.copyrightId,
        'contentId': song.contentId,
        'resourceType': song.playbackResourceType,
        'channel': '0',
      },
      followRedirects: false,
      responseType: ResponseType.plain,
    );

    final status = response.statusCode ?? 0;

    // 接口以 3xx + Location 返回带时效的 CDN 流地址。
    if (status >= 300 && status < 400) {
      final location = response.headers.value('location')?.trim();
      final uri = location == null ? null : Uri.tryParse(location);
      if (uri != null && uri.hasScheme && uri.scheme == 'https') {
        return uri.toString();
      }
      throw const MiguApiException(
        '咪咕返回的播放地址无效，已停止播放。',
        kind: MiguErrorKind.invalidResponse,
      );
    }

    if (status >= 200 && status < 300) {
      final body = _decodeBody(response.data);
      final directUrl = _extractDirectUrl(body);
      if (directUrl != null) return directUrl;
    }

    if (status == 401) {
      if (sentCredentials && _isCurrentSession(requestEpoch)) {
        onAuthRejected?.call();
      }
      throw const MiguApiException(
        '咪咕服务要求重新登录：登录状态可能已失效，请在账号面板重新登录一次。',
        kind: MiguErrorKind.authRejected,
        permissionDenied: true,
        loginRequired: true,
      );
    }

    // 服务端用业务码区分“参数不被接受”和“账号无权限”，两者提示完全不同。
    final failure = _businessFailure(response.data);

    if (failure != null && failure.code == '200002') {
      final detail = failure.info.isEmpty
          ? failure.code
          : '${failure.code} ${failure.info}';
      throw MiguApiException(
        '咪咕取链接口拒绝了本次请求（服务端返回 $detail），'
        '这首曲目可能已下架或暂无免费音源。',
        kind: MiguErrorKind.playbackUnavailable,
      );
    }

    if (status == 403 || _isPermissionFailure(failure)) {
      // 本机压根没有官方登录会话时，不能把原因说成“登录已失效”。
      final incompleteLogin = hasImportedLogin && !hasWebSessionCookie;
      // 403 绝大多数是这首曲目本身没有权益，不足以判定登录失效，
      // 因此这里不翻转认证状态；只有 401 才认为凭据被服务端拒绝。
      throw MiguApiException(
        incompleteLogin
            ? '本机保存的凭据里没有咪咕音乐的登录会话（pacmtoken）。'
                  '请在账号面板重新登录一次。'
            : '咪咕服务端拒绝了本次播放请求：当前账号可能没有这首歌曲的权限，'
                  '请确认账号权益；如果整站都无法播放，再重新登录一次。',
        kind: MiguErrorKind.permissionDenied,
        permissionDenied: true,
        loginRequired: true,
      );
    }

    if (status == 429) {
      throw const MiguApiException(
        '请求过于频繁，咪咕服务已临时限流，请稍后再试。',
        kind: MiguErrorKind.rateLimited,
      );
    }

    if (status >= 500) {
      throw const MiguApiException('咪咕服务暂时无法提供播放链接，请稍后再试。', kind: MiguErrorKind.server);
    }

    throw const MiguApiException(
      '暂时无法获取播放链接，请稍后再试。',
      kind: MiguErrorKind.invalidResponse,
    );
  }

  /// VIP 曲目取链：从用户选择的音质开始，按账号权益逐级回退到标准音质。
  ///
  /// 地址由咪咕按账号权益发放；本机只负责把用户自己的登录凭据随请求发送，
  /// 不对音频做任何解密或保存。
  Future<String> _resolveVipPlaybackUrl(Song song, AudioQuality quality) async {
    final credentials = client.cookieStore.credentials;
    if (credentials.pacmtoken == null) {
      throw const MiguApiException(
        '这首歌曲是咪咕 VIP 专享，需要先登录咪咕账号。'
        '请点开账号入口，完成咪咕官方网页登录后再试。'
        '也可以点“官方页面播放”，由内嵌的咪咕官方播放器完成登录与鉴权。',
        kind: MiguErrorKind.playbackUnavailable,
        loginRequired: true,
      );
    }

    final requestEpoch = sessionEpoch?.call();
    final result = await _tryStrategyPlaybackUrl(song, quality);
    final url = result.url;
    if (url != null) {
      if (_isCurrentSession(requestEpoch)) onAuthVerified?.call();
      return url;
    }

    final dialog = result.dialog ?? '';
    final cannotCode = result.cannotCode ?? '';
    final detail = dialog.isNotEmpty
        ? dialog
        : cannotCode.isNotEmpty
        ? '咪咕返回 $cannotCode'
        : '接口没有返回可用的音频地址';
    final attempted = AudioQuality.fallbackChain(quality)
        .map((item) => item.label)
        .join(' / ');
    throw MiguApiException(
      '咪咕没有为这首 VIP 曲目发放播放地址（已依次尝试 $attempted）：$detail。'
      '请确认当前账号的 VIP 权益覆盖这首歌曲；数字专辑等需要单独购买的曲目需要先在咪咕购买。'
      '也可以点“官方页面播放”，改由内嵌的咪咕官方播放器播放。',
      kind: MiguErrorKind.permissionDenied,
      permissionDenied: true,
      loginRequired: true,
    );
  }

  /// 按所选音质从高到低请求播放策略接口；返回最后一级的失败信息用于提示。
  Future<({String? url, String? cannotCode, String? dialog})> _tryStrategyPlaybackUrl(
    Song song,
    AudioQuality quality, {
    bool reportAuth = true,
  }) async {
    ({String? url, String? cannotCode, String? dialog})? last;
    for (final level in AudioQuality.fallbackChain(quality)) {
      final result = await _requestStrategyListen(
        song,
        level.toneFlag,
        reportAuth: reportAuth,
      );
      if (result.url != null) return result;
      last = result;
    }
    return last ?? (url: null, cannotCode: null, dialog: null);
  }

  Future<({String? url, String? cannotCode, String? dialog})> _requestStrategyListen(
    Song song,
    String toneFlag, {
    bool reportAuth = true,
  }) async {
    final requestEpoch = sessionEpoch?.call();
    final response = await client.getRaw(
      AppConstants.vipListenUrl,
      query: {
        'scene': '',
        'netType': '01',
        'resourceType': AppConstants.playbackResourceType,
        'copyrightId': song.copyrightId,
        'contentId': song.contentId,
        'toneFlag': toneFlag,
      },
      headers: {
        'signature': '1',
        'birth': 'h5page',
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        'activityid': 'MUSIC-WWW',
        'appid': 'h5',
        'channel': '014X031',
        'subchannel': '014X031',
        'platform': 'H5',
        'test': '00',
        'ua': 'Android_migu',
        'version': '6.8.8',
        'imei': 'h5page',
        'imsi': 'h5page',
        'origin': AppConstants.miguReferer,
      },
      responseType: ResponseType.bytes,
    );

    final status = response.statusCode ?? 0;
    if (status == 401) {
      if (reportAuth && _isCurrentSession(requestEpoch)) {
        onAuthRejected?.call();
      }
      throw const MiguApiException(
        '咪咕要求重新登录：登录状态可能已失效，请在账号面板重新登录一次。',
        kind: MiguErrorKind.authRejected,
        permissionDenied: true,
        loginRequired: true,
      );
    }
    if (status == 403) {
      // 策略接口的 403 同样更可能是曲目权益问题，不据此判定登录失效。
      throw const MiguApiException(
        '咪咕拒绝了本次播放请求：当前账号可能没有这首歌曲的权益，'
        '请确认 VIP 覆盖范围；数字专辑等需要单独购买的曲目需要先购买。',
        kind: MiguErrorKind.permissionDenied,
        permissionDenied: true,
        loginRequired: true,
      );
    }
    if (status == 429) {
      throw const MiguApiException(
        '请求过于频繁，咪咕服务已临时限流，请稍后再试。',
        kind: MiguErrorKind.rateLimited,
      );
    }
    if (status >= 500) {
      throw const MiguApiException('咪咕服务暂时无法提供播放链接，请稍后再试。', kind: MiguErrorKind.server);
    }
    if (status < 200 || status >= 300) {
      throw MiguApiException(
        '咪咕播放策略接口返回异常（HTTP $status）。',
        kind: MiguErrorKind.invalidResponse,
      );
    }

    final payload = _decodeListenPayload(response.data);
    if (payload is! Map) {
      throw const MiguApiException(
        '咪咕播放策略接口返回了无法识别的数据。',
        kind: MiguErrorKind.invalidResponse,
      );
    }

    final code = readString(payload['code']).trim();
    final info = readString(payload['info'] ?? payload['msg']).trim();
    if (code.isNotEmpty && code != '000000' && code != '200') {
      throw MiguApiException(
        info.isEmpty ? '咪咕播放策略接口返回异常（$code）。' : '咪咕播放策略接口返回异常：$info',
        kind: MiguErrorKind.playbackUnavailable,
      );
    }

    final url = _extractDirectUrl(payload);
    if (url != null) return (url: url, cannotCode: null, dialog: null);

    final data = readMap(payload['data']);
    final dialog = readString(readMap(data?['dialogInfo'])?['text']).trim();
    final cannotCode = readString(data?['cannotCode']).trim();
    return (
      url: null,
      cannotCode: cannotCode.isEmpty ? null : cannotCode,
      dialog: dialog.isEmpty ? null : dialog,
    );
  }

  /// 播放策略接口的响应体是站点自身编码；同时兼容明文 JSON。
  dynamic _decodeListenPayload(dynamic data) {
    if (data is List<int>) {
      final decoded = MiguResponseCipher.decodeJson(data);
      if (decoded != null) return decoded;
      return _decodeBody(utf8.decode(data, allowMalformed: true));
    }
    return _decodeBody(data);
  }

  /// 读取 LRC 歌词；当搜索/歌单条目缺少歌词地址时，用单曲名做一次公开搜索补全。
  Future<String?> fetchLyrics(Song song) async {
    var lyricUrl = song.lyricUrl;

    if (lyricUrl == null || lyricUrl.isEmpty) {
      lyricUrl = await _findLyricUrlBySearch(song);
    }
    if (lyricUrl == null || lyricUrl.isEmpty) return null;

    try {
      final text = await client.getText(lyricUrl);
      final normalized = text.replaceFirst('\uFEFF', '').trim();
      if (normalized.isEmpty) return null;
      final hasTimestamp = RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]')
          .hasMatch(normalized);
      return hasTimestamp ? normalized : null;
    } on MiguApiException {
      return null;
    }
  }

  Future<String?> _findLyricUrlBySearch(Song song) async {
    final artist = song.artistNames.isNotEmpty ? song.artistNames.first : '';
    final query = '${song.name} $artist'.trim();
    if (query.isEmpty) return null;

    try {
      final candidates = await searchSongs(query, pageSize: 10);
      Song? exact;
      Song? sameName;
      for (final candidate in candidates) {
        if (candidate.contentId == song.contentId && candidate.hasLyric) {
          exact = candidate;
          break;
        }
        if (sameName == null && candidate.name == song.name && candidate.hasLyric) {
          sameName = candidate;
        }
      }
      return (exact ?? sameName)?.lyricUrl;
    } on MiguApiException {
      return null;
    }
  }

  /// 业务编码不是成功就抛错；是否算“登录失效”由网络层带着真实请求地址去判定。
  ///
  /// 这里只决定异常种类与文案：同样的 `290001` 从账号接口回来是凭据问题，
  /// 从公开接口回来只说明那次请求本身没被接受，两者不能一起上报。
  void _ensureBusinessOk(dynamic payload) {
    if (payload is! Map) return;
    final code = readString(payload['code']).trim();
    if (code.isEmpty || code == '000000' || code == '200') return;
    final info = readString(payload['info'] ?? payload['msg']).trim();
    final revoked =
        classifySessionProbe(status: 200, code: code, info: info) ==
        SessionProbe.revoked;
    throw MiguApiException(
      info.isEmpty ? '咪咕服务返回异常（$code）。' : '咪咕服务返回异常：$info',
      kind: revoked ? MiguErrorKind.authRequired : MiguErrorKind.invalidResponse,
      loginRequired: revoked,
    );
  }

  dynamic _decodeBody(dynamic body) {
    if (body is Map || body is List) return body;
    if (body is String && body.trim().isNotEmpty) {
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    return null;
  }

  String? _extractDirectUrl(dynamic body) {
    final map = readMap(body);
    if (map == null) return null;
    final candidates = <dynamic>[
      map['url'],
      map['playUrl'],
      readMap(map['data'])?['url'],
      readMap(map['data'])?['playUrl'],
    ];
    for (final candidate in candidates) {
      final url = Uri.tryParse(candidate?.toString() ?? '');
      if (url != null && url.scheme == 'https') return url.toString();
    }
    return null;
  }

  /// 解析咪咕业务层的拒绝码；成功响应返回 null。
  ({String code, String info})? _businessFailure(dynamic body) {
    final map = readMap(_decodeBody(body));
    if (map == null) return null;
    final code = readString(
      map['businessCode'] ?? map['code'] ?? readMap(map['data'])?['code'],
    ).trim();
    if (code.isEmpty || code == '000000' || code == '200') return null;
    return (code: code, info: readString(map['info'] ?? map['msg']).trim());
  }

  /// 明确表示账号权限不足的业务码；参数格式类错误不属于此列。
  bool _isPermissionFailure(({String code, String info})? failure) {
    if (failure == null) return false;
    return const {'200003', '200004', '403'}.contains(failure.code);
  }
}
