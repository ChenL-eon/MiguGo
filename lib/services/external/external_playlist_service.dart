import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/external_playlist_urls.dart';
import '../../core/utils/json_read.dart';
import '../../models/imported_playlist.dart';

/// 读取第三方平台公开歌单：只发公开 GET 请求，不携带任何咪咕或第三方账号凭据。
class ExternalPlaylistService {
  ExternalPlaylistService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': AppConstants.userAgent,
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
              },
            ),
          );

  final Dio _dio;

  Future<ExternalPlaylist> fetchPlaylist(
    ExternalPlaylistLink link, {
    int maxTracks = 0,
  }) async {
    final resolved = link.needsResolution ? await _resolve(link) : link;
    final id = resolved.id;
    if (id == null || id.isEmpty) {
      throw ExternalPlaylistException(
        '没有从链接里识别出${resolved.platform.label}歌单 ID，'
        '请复制歌单页面里的完整分享链接再试。',
      );
    }

    switch (resolved.platform) {
      case ExternalPlatform.netease:
        final response = await _get(
          'https://music.163.com/api/v6/playlist/detail',
          platform: resolved.platform,
          // 匿名请求默认只返回前 10 首完整曲目；n=1000 才尝试返回整个歌单。
          query: {'id': id, 'n': '1000'},
          headers: const {
            'Referer': 'https://music.163.com/',
            'Accept': 'application/json',
          },
        );
        final extraSongs = await _neteaseExtraSongs(
          response.data,
          platform: resolved.platform,
          maxTracks: maxTracks,
        );
        return ExternalPlaylist.fromNeteasePayload(
          response.data,
          sourceUrl: resolved.url.toString(),
          extraSongs: extraSongs,
        );
      case ExternalPlatform.qqMusic:
        final response = await _get(
          'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
          platform: resolved.platform,
          query: {
            'type': '1',
            'json': '1',
            'utf8': '1',
            'onlysong': '0',
            'disstid': id,
            'format': 'json',
            'g_tk': '5381',
            'loginUin': '0',
            'hostUin': '0',
            'inCharset': 'utf8',
            'outCharset': 'utf-8',
            'notice': '0',
            'platform': 'yqq.json',
            'needNewCode': '0',
          },
          headers: const {
            'Referer': 'https://y.qq.com/',
            'Origin': 'https://y.qq.com',
            'Accept': 'application/json',
          },
        );
        return ExternalPlaylist.fromQqPayload(
          response.data,
          sourceUrl: resolved.url.toString(),
        );
      case ExternalPlatform.kugou:
        final response = await _get(
          'https://www.kugou.com/yy/special/single/$id.html',
          platform: resolved.platform,
          headers: const {
            'Referer': 'https://www.kugou.com/',
            'Accept': 'text/html,application/xhtml+xml',
          },
          responseType: ResponseType.plain,
        );
        final html = response.data is String ? response.data as String : '';
        final full = await _kugouFullTracks(
          id,
          platform: resolved.platform,
          maxTracks: maxTracks,
        );
        return ExternalPlaylist.fromKugouPage(
          html,
          sourceUrl: resolved.url.toString(),
          apiSongs: full.songs,
          apiTotal: full.total,
        );
    }
  }

  /// 网易云详情接口经常只返回 6~10 首，但 trackIds 是完整的；
  /// 缺失部分改用公开的歌曲详情接口按 50 首一批补拉。
  Future<List<dynamic>> _neteaseExtraSongs(
    dynamic payload, {
    required ExternalPlatform platform,
    required int maxTracks,
  }) async {
    final missing = ExternalPlaylist.neteaseMissingTrackIds(payload);
    if (missing.isEmpty) return const [];
    final wanted = maxTracks > 0 && missing.length > maxTracks
        ? missing.sublist(0, maxTracks)
        : missing;

    final songs = <dynamic>[];
    for (var index = 0; index < wanted.length; index += 50) {
      final batch = wanted.sublist(index, math.min(index + 50, wanted.length));
      final ids = batch.map(int.tryParse).whereType<int>().toList();
      if (ids.isEmpty) continue;
      try {
        final detail = await _get(
          'https://music.163.com/api/song/detail',
          platform: platform,
          query: {'ids': jsonEncode(ids)},
          headers: const {
            'Referer': 'https://music.163.com/',
            'Accept': 'application/json',
          },
        );
        songs.addAll(readList(readMap(detail.data)?['songs']));
      } on ExternalPlaylistException {
        break;
      }
    }
    return songs;
  }

  /// 酷狗网页只公开前 30 首，移动接口能按页取到完整歌单。
  Future<({List<dynamic> songs, int total})> _kugouFullTracks(
    String id, {
    required ExternalPlatform platform,
    required int maxTracks,
  }) async {
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      return (songs: const <dynamic>[], total: 0);
    }

    final songs = <dynamic>[];
    var total = 0;
    const pageSize = 100;
    for (var page = 1; page <= 50; page++) {
      final dynamic payload;
      try {
        final response = await _get(
          'https://mobiles.kugou.com/api/v3/special/song',
          platform: platform,
          query: {
            'specialid': id,
            'page': '$page',
            'pagesize': '$pageSize',
            'plat': '0',
            'version': '8000',
          },
          headers: const {
            'Referer': 'https://www.kugou.com/',
            'Accept': 'application/json',
          },
        );
        payload = response.data;
      } on ExternalPlaylistException {
        break;
      }

      final data = readMap(readMap(payload)?['data']);
      total = math.max(total, readInt(data?['total']));
      final pageSongs = readList(data?['info']);
      if (pageSongs.isEmpty) break;
      songs.addAll(pageSongs);
      if (maxTracks > 0 && songs.length >= maxTracks) break;
      if (total > 0 && songs.length >= total) break;
      if (pageSongs.length < pageSize) break;
    }
    return (songs: songs, total: total);
  }

  /// 短链先跟随 302，再从跳转结果或页面脚本中找出带歌单 ID 的地址。
  Future<ExternalPlaylistLink> _resolve(ExternalPlaylistLink link) async {
    final response = await _get(
      link.url.toString(),
      platform: link.platform,
      headers: const {'Accept': 'text/html,application/xhtml+xml'},
      responseType: ResponseType.plain,
    );
    final body = response.data is String ? response.data as String : '';
    final candidates = <String>[response.realUri.toString(), ..._urlsInPage(body)];

    ExternalPlaylistLink? otherPlatform;
    for (final candidate in candidates) {
      final parsed = parseExternalPlaylistLink(candidate);
      if (parsed == null || parsed.needsResolution) continue;
      if (parsed.platform == link.platform) return parsed;
      otherPlatform ??= parsed;
    }
    if (otherPlatform != null) return otherPlatform;

    throw ExternalPlaylistException(
      '无法解析这个${link.platform.label}短链接，'
      '请打开歌单页面后复制地址栏里的完整链接。',
    );
  }

  Future<Response<dynamic>> _get(
    String url, {
    required ExternalPlatform platform,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    ResponseType responseType = ResponseType.json,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        queryParameters: query,
        options: Options(
          headers: headers,
          responseType: responseType,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw ExternalPlaylistException(_statusMessage(platform, status));
      }
      return response;
    } on DioException catch (error) {
      throw _networkMessage(error);
    }
  }

  String _statusMessage(ExternalPlatform platform, int status) {
    if (status == 404) {
      return '${platform.label}没有找到这个歌单（HTTP 404），请确认链接有效。';
    }
    if (status == 403) {
      return '${platform.label}拒绝了读取请求（HTTP 403），歌单可能是私密的。';
    }
    if (status == 429) {
      return '${platform.label}请求过于频繁，请稍后再试。';
    }
    if (status >= 500) {
      return '${platform.label}服务暂时不可用（HTTP $status），请稍后再试。';
    }
    return '读取${platform.label}歌单失败（HTTP $status）。';
  }

  ExternalPlaylistException _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const ExternalPlaylistException(
        '连接歌单平台超时，请检查网络后重试。',
      ),
      DioExceptionType.badCertificate => const ExternalPlaylistException(
        '歌单平台的证书校验失败，已停止连接。',
      ),
      DioExceptionType.connectionError => const ExternalPlaylistException(
        '无法连接歌单平台，请检查网络设置。',
      ),
      DioExceptionType.cancel => const ExternalPlaylistException('读取歌单已取消。'),
      _ => const ExternalPlaylistException('读取歌单失败，请稍后重试。'),
    };
  }

  /// 页面里的跳转既可能是完整 URL，也可能是协议相对地址或转义过的路径。
  List<String> _urlsInPage(String body) {
    if (body.isEmpty) return const [];
    final text = body.length > 200000 ? body.substring(0, 200000) : body;
    final normalized = text
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u002f', '/')
        .replaceAll('&amp;', '&');
    final regex = RegExp(r'''(?:https?:)?//[^\s"'<>\\]+''', caseSensitive: false);
    final urls = <String>[];
    for (final match in regex.allMatches(normalized)) {
      var value = match.group(0) ?? '';
      value = value.replaceAll(RegExp(r'[)\]},.;]+$'), '');
      if (value.isEmpty) continue;
      if (value.startsWith('//')) value = 'https:$value';
      if (value.length > 2000) continue;
      if (!urls.contains(value)) urls.add(value);
    }
    return urls;
  }
}
