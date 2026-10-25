import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/core/utils/external_playlist_urls.dart';
import 'package:migu_lele/models/imported_playlist.dart';
import 'package:migu_lele/models/song.dart';
import 'package:migu_lele/pages/playlist_hub_page.dart';
import 'package:migu_lele/providers/imported_playlist_provider.dart';
import 'package:migu_lele/services/api/migu_music_api.dart';
import 'package:migu_lele/services/external/external_playlist_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 导入面板的操作接线：面板本身要能停下来，失败原因关掉面板后也还在。
class _FakeExternalService extends ExternalPlaylistService {
  _FakeExternalService({this.playlist, this.error});

  final ExternalPlaylist? playlist;
  final Object? error;

  @override
  Future<ExternalPlaylist> fetchPlaylist(
    ExternalPlaylistLink link, {
    int maxTracks = 0,
  }) async {
    if (error != null) throw error!;
    return playlist!;
  }
}

/// 每次搜索都先停在闸门上的假接口，用来制造「正在导入、还没跑完」的状态。
class _GatedMusicApi extends MiguMusicApi {
  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    int pageNo = 1,
    int pageSize = 30,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return const [];
  }

  @override
  Future<String?> fetchLyrics(Song song) async => null;
}

ExternalPlaylist _playlist() {
  return const ExternalPlaylist(
    platform: ExternalPlatform.netease,
    sourceUrl: 'https://music.163.com/playlist?id=1',
    name: '测试歌单',
    tracks: [
      ExternalTrack(title: '晴天', artist: '周杰伦'),
      ExternalTrack(title: '稻香', artist: '周杰伦'),
    ],
    totalCount: 2,
  );
}

Widget _harness(ImportedPlaylistProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ImportedPlaylistProvider>.value(value: provider),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openPlaylistImportDialog(context),
              child: const Text('打开导入面板'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('导入中途可以取消，取消后回到可重新操作的状态', (tester) async {
    final api = _GatedMusicApi();
    final provider = ImportedPlaylistProvider(
      _FakeExternalService(playlist: _playlist()),
      api,
    );
    await provider.load();
    await tester.pumpWidget(_harness(provider));

    await tester.tap(find.text('打开导入面板'));
    await tester.pumpAndSettle();
    expect(find.text('从剪贴板粘贴'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://music.163.com/playlist?id=1',
    );
    await tester.tap(find.text('开始导入'));
    await tester.pump();
    expect(provider.importing, isTrue);

    await api.entered.future;
    await tester.pump();
    expect(find.text('取消导入'), findsOneWidget, reason: '正在导入时要给出停止的按钮');

    await tester.tap(find.text('取消导入'));
    await tester.pump();
    expect(provider.importing, isFalse, reason: '点取消要真的停下这批匹配');

    api.gate.complete();
    await tester.pumpAndSettle();
    expect(provider.playlists, isEmpty, reason: '取消后在途结果不能写进本机歌单');
    expect(find.text('开始导入'), findsOneWidget, reason: '取消后面板还能再导一次');
  });

  testWidgets('关掉面板后失败原因仍然显示在页面上', (tester) async {
    final provider = ImportedPlaylistProvider(
      _FakeExternalService(error: const ExternalPlaylistException('网易云拒绝读取这个歌单。')),
      _GatedMusicApi(),
    );
    await provider.load();
    await tester.pumpWidget(_harness(provider));

    await tester.tap(find.text('打开导入面板'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://music.163.com/playlist?id=1',
    );
    await tester.tap(find.text('开始导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('网易云拒绝读取这个歌单'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SnackBar, '网易云拒绝读取这个歌单。'),
      findsOneWidget,
      reason: '卡片关掉后，失败原因不该跟着一起消失',
    );
  });
}
