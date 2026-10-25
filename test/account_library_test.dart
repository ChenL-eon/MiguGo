import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/account_library.dart';
import 'package:migu_lele/providers/account_provider.dart';
import 'package:migu_lele/services/api/auth_session_store.dart';
import 'package:migu_lele/services/api/migu_api_client.dart';
import 'package:migu_lele/services/api/migu_cookie_store.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

Map<String, dynamic> _homePagePayload() => {
  'code': '000000',
  'data': {
    'userPrivateItems': [
      {
        'title': '听歌排行',
        'subTitle': '',
        'picUrl': '',
        'actionUrl': 'mgmusic://music/mine/listenbank?index=0',
      },
      {
        'title': '喜欢的音乐',
        'subTitle': '12首',
        'picUrl': 'https://d.musicapp.migu.cn/fav.png',
        'actionUrl': 'mgmusic://music/mine/favorite?type=0&musicListId=187400680',
      },
    ],
    'myCreatedMusicLists': {
      'count': 2,
      'createdMusicLists': [
        {
          'title': '日志',
          'musicListId': '236705635',
          'musicNum': 203,
          'ownerName': 'ChenL',
          'imgItem': {'img': 'https://d.musicapp.migu.cn/created.webp', 'webpImg': ''},
          'opNumItem': {'playNumDesc': '241'},
          'tags': <dynamic>[],
        },
        {'title': '重复出现', 'musicListId': '236705635', 'musicNum': 1},
        {'title': '缺少 ID'},
      ],
    },
    'myCollectedMusicLists': {
      'count': 1,
      'collectMusicLists': [
        {
          'title': '周杰伦丨嘘，青春正在加载中…',
          'musicListId': '209060917',
          'musicNum': 32,
          'summary': '他陪我们度过了年少轻狂。',
          'ownerName': '武汉热干面的早晨',
          'imgItem': {'img': 'https://d.musicapp.migu.cn/collect.webp'},
          'opNumItem': {'playNumDesc': '533.3万'},
          'tags': [
            {'tagId': '1', 'tagName': '经典老歌'},
            {'tagId': '2', 'tagName': '流行'},
          ],
        },
      ],
    },
  },
};

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.payload);

  final Map<String, dynamic> payload;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('账号歌单解析', () {
    test('解析我喜欢、自建与收藏歌单', () {
      final library = AccountLibrary.fromHomePageJson(_homePagePayload()['data']);

      final favorite = library.favoritePlaylist;
      expect(favorite, isNotNull);
      expect(favorite!.id, '187400680');
      expect(favorite.name, '喜欢的音乐');
      expect(favorite.songCount, 12);
      expect(favorite.coverUrl, 'https://d.musicapp.migu.cn/fav.png');

      expect(library.createdPlaylists, hasLength(1));
      final created = library.createdPlaylists.single;
      expect(created.id, '236705635');
      expect(created.name, '日志');
      expect(created.songCount, 203);
      expect(created.ownerName, 'ChenL');
      expect(created.coverUrl, 'https://d.musicapp.migu.cn/created.webp');

      expect(library.collectedPlaylists, hasLength(1));
      final collected = library.collectedPlaylists.single;
      expect(collected.id, '209060917');
      expect(collected.name, '周杰伦丨嘘，青春正在加载中…');
      expect(collected.songCount, 32);
      expect(collected.playCountLabel, '533.3万');
      expect(collected.tags, ['经典老歌', '流行']);
      expect(library.isEmpty, isFalse);
    });

    test('优先识别 favorite 入口，忽略没有歌单 ID 的入口', () {
      final library = AccountLibrary.fromHomePageJson({
        'userPrivateItems': [
          {
            'title': '最近在听',
            'actionUrl': 'mgmusic://music/song/recent-playlist?musicListId=11',
          },
          {
            'title': '我的喜欢',
            'subTitle': '3首',
            'actionUrl': 'mgmusic://music/mine/favorite?musicListId=22',
          },
          {'title': '彩铃库', 'actionUrl': 'mgmusic://ringlive/mine-home'},
        ],
      });

      expect(library.favoritePlaylist!.id, '22');
      expect(library.favoritePlaylist!.name, '我的喜欢');
      expect(library.favoritePlaylist!.songCount, 3);
    });

    test('空数据得到空账号库', () {
      final library = AccountLibrary.fromHomePageJson({'code': '000000'});
      expect(library.isEmpty, isTrue);
      expect(library.favoritePlaylist, isNull);
      expect(library.createdPlaylists, isEmpty);
      expect(library.collectedPlaylists, isEmpty);
    });
  });

  group('账号歌单接口与状态', () {
    Future<MiguCookieStore> createCookieStore() async {
      final store = MiguCookieStore(secureStorage: FakeSecureCookieStorage());
      await store.init();
      return store;
    }

    test('请求账号主页并解析歌单', () async {
      final cookieStore = await createCookieStore();
      final adapter = _StubAdapter(_homePagePayload());
      final api = MiguMusicApi(
        client: MiguApiClient(
          dio: Dio()..httpClientAdapter = adapter,
          cookieStore: cookieStore,
        ),
      );

      final library = await api.fetchAccountLibrary();
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/pc/user/home-page/v2.0');
      expect(library.favoritePlaylist!.id, '187400680');
      expect(library.collectedPlaylists.single.tags, ['经典老歌', '流行']);
    });

    test('读取成功后缓存，退出登录清空', () async {
      final cookieStore = await createCookieStore();
      final providerStorage = FakeSecureCookieStorage();
      final account = AccountProvider(
        cookieStore: cookieStore,
        authSessionStore: AuthSessionStore(storage: providerStorage),
      );
      await account.initialize();
      await account.importLoginCookie('pacmtoken=p1; uid=u1');

      final adapter = _StubAdapter(_homePagePayload());
      account.attachApi(
        MiguMusicApi(
          client: MiguApiClient(
            dio: Dio()..httpClientAdapter = adapter,
            cookieStore: cookieStore,
          ),
        ),
      );

      await account.refreshLibrary();
      expect(account.library, isNotNull);
      expect(account.library!.favoritePlaylist!.id, '187400680');
      expect(account.libraryLoading, isFalse);
      expect(account.libraryError, isNull);

      await account.refreshLibrary();
      expect(adapter.requests, hasLength(1));

      await account.signOut();
      expect(account.library, isNull);
      expect(account.libraryError, isNull);
      expect(account.hasLogin, isFalse);
    });
  });
}
