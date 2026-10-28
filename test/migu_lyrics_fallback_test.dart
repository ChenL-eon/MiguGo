import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

const _songWithoutLyric = Song(
  contentId: 'content-lyrics',
  copyrightId: 'copyright-lyrics',
  name: '歌词测试歌曲',
  artistNames: ['测试歌手'],
  album: '测试专辑',
  duration: Duration(seconds: 180),
  isVipOnly: false,
);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String text, {int status = 200}) {
  return ResponseBody.fromString(
    text,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody _lyric(String text, {int status = 200}) {
  return ResponseBody.fromString(
    text,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
    },
  );
}

Future<(MiguMusicApi, MiguApiClient)> _createApi(
  _FakeAdapter adapter, {
  void Function()? onSessionRevoked,
}) async {
  final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
  await store.init();
  final client = MiguApiClient(
    dio: Dio()..httpClientAdapter = adapter,
    cookieStore: store,
    onSessionRevoked: onSessionRevoked,
  );
  return (MiguMusicApi(client: client), client);
}

bool _isResourceInfo(RequestOptions options) =>
    options.uri.path.endsWith('/content/resourceinfo.do');

bool _isSearch(RequestOptions options) =>
    options.uri.path.endsWith('/pc/resource/song/item/search/v1.0');

bool _isLyricHost(RequestOptions options) => options.uri.host == 'lyrics.example.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('没有歌曲歌词地址时按 contentId 从 resourceinfo 取歌词', () async {
    final adapter = _FakeAdapter((options) {
      if (_isResourceInfo(options)) {
        return _json(
          '{"code":"000000","resource":[{"lrcUrl":'
          '"https://lyrics.example.com/from-resource.lrc"}]}',
        );
      }
      if (_isSearch(options)) {
        return _json('{"code":"000000","songList":[]}');
      }
      if (_isLyricHost(options)) {
        return _lyric('[00:01.00]资源接口歌词');
      }
      return _json('{}', status: 404);
    });
    final (api, _) = await _createApi(adapter);

    final raw = await api.fetchLyrics(_songWithoutLyric);

    expect(raw, '[00:01.00]资源接口歌词');
    expect(adapter.requests.any(_isResourceInfo), isTrue);
    expect(adapter.requests.any(_isSearch), isFalse);
  });

  test('歌曲歌词地址没有时间戳时回退 resourceinfo', () async {
    const song = Song(
      contentId: 'content-unsynced',
      copyrightId: 'copyright-unsynced',
      name: '无时间戳歌词',
      artistNames: ['测试歌手'],
      album: '测试专辑',
      duration: Duration(seconds: 180),
      isVipOnly: false,
      lyricUrl: 'https://lyrics.example.com/unsynced.lrc',
    );
    final adapter = _FakeAdapter((options) {
      if (_isResourceInfo(options)) {
        return _json(
          '{"code":"000000","resource":[{"lrcUrl":'
          '"https://lyrics.example.com/synced.lrc"}]}',
        );
      }
      if (_isSearch(options)) {
        return _json('{"code":"000000","songList":[]}');
      }
      if (_isLyricHost(options) && options.uri.path == '/unsynced.lrc') {
        return _lyric('只有文本，没有时间标签');
      }
      if (_isLyricHost(options) && options.uri.path == '/synced.lrc') {
        return _lyric('[00:02.00]回退后的同步歌词');
      }
      return _json('{}', status: 404);
    });
    final (api, _) = await _createApi(adapter);

    final raw = await api.fetchLyrics(song);

    expect(raw, '[00:02.00]回退后的同步歌词');
    expect(adapter.requests.any(_isResourceInfo), isTrue);
  });

  test('resourceinfo 失败时仍回退到搜索歌词地址', () async {
    final adapter = _FakeAdapter((options) {
      if (_isResourceInfo(options)) {
        return _json('{}', status: 500);
      }
      if (_isSearch(options)) {
        return _json(
          '{"code":"000000","songList":[{"contentId":"content-lyrics",'
          '"songName":"歌词测试歌曲","lrcUrl":'
          '"https://lyrics.example.com/from-search.lrc"}]}',
        );
      }
      if (_isLyricHost(options)) {
        return _lyric('[00:03.00]搜索补全歌词');
      }
      return _json('{}', status: 404);
    });
    final (api, _) = await _createApi(adapter);

    final raw = await api.fetchLyrics(_songWithoutLyric);

    expect(raw, '[00:03.00]搜索补全歌词');
    expect(adapter.requests.any(_isResourceInfo), isTrue);
    expect(adapter.requests.any(_isSearch), isTrue);
  });

  test('歌词资源接口 401 不触发会话回绝', () async {
    final adapter = _FakeAdapter((options) {
      if (_isResourceInfo(options)) {
        return _json('{}', status: 401);
      }
      if (_isSearch(options)) {
        return _json('{"code":"000000","songList":[]}');
      }
      return _json('{}', status: 404);
    });
    var revoked = 0;
    final (api, _) = await _createApi(adapter, onSessionRevoked: () => revoked++);

    final raw = await api.fetchLyrics(_songWithoutLyric);

    expect(raw, isNull);
    expect(revoked, 0);
  });

  test('直连歌词有效时不再请求 resourceinfo 或搜索', () async {
    const song = Song(
      contentId: 'content-direct',
      copyrightId: 'copyright-direct',
      name: '直连歌词',
      artistNames: ['测试歌手'],
      album: '测试专辑',
      duration: Duration(seconds: 180),
      isVipOnly: false,
      lyricUrl: 'https://lyrics.example.com/direct.lrc',
    );
    final adapter = _FakeAdapter((options) {
      if (_isLyricHost(options)) {
        return _lyric('[00:04.00]直连歌词');
      }
      return _json('{}', status: 404);
    });
    final (api, _) = await _createApi(adapter);

    final raw = await api.fetchLyrics(song);

    expect(raw, '[00:04.00]直连歌词');
    expect(adapter.requests.any(_isResourceInfo), isFalse);
    expect(adapter.requests.any(_isSearch), isFalse);
  });

  test('resourceinfo 返回的 HTTP 歌词地址会升级为 HTTPS', () async {
    final adapter = _FakeAdapter((options) {
      if (_isResourceInfo(options)) {
        return _json(
          '{"code":"000000","resource":[{"lrcUrl":'
          '"http://lyrics.example.com/plain-http.lrc"}]}',
        );
      }
      if (_isSearch(options)) {
        return _json('{"code":"000000","songList":[]}');
      }
      if (_isLyricHost(options)) {
        return _lyric('[00:05.00]HTTPS 歌词');
      }
      return _json('{}', status: 404);
    });
    final (api, _) = await _createApi(adapter);

    final raw = await api.fetchLyrics(_songWithoutLyric);

    expect(raw, '[00:05.00]HTTPS 歌词');
    final lyricRequest = adapter.requests.firstWhere(_isLyricHost);
    expect(lyricRequest.uri.scheme, 'https');
    expect(lyricRequest.uri.path, '/plain-http.lrc');
  });
}
