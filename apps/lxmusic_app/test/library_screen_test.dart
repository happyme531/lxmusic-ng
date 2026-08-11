import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/library/library_screen.dart';
import 'package:lxmusic_app/features/library/models/library_playlist.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/library/providers/music_library_provider.dart';

void main() {
  MusicLibraryState buildLibraryState() {
    return MusicLibraryState(
      files: <MusicFile>[
        MusicFile(
          path: '/tmp/demo.mid',
          fileName: 'demo.mid',
          formatId: 'midi',
          trackCount: 2,
          noteCount: 42,
          durationMs: 123000,
        ),
      ],
      playlists: const <LibraryPlaylist>[
        LibraryPlaylist(
          id: favoritesPlaylistId,
          name: '收藏',
          musicFileNames: <String>['demo.mid'],
          isBuiltinFavorite: true,
        ),
        LibraryPlaylist(
          id: 'playlist_custom',
          name: '练习',
          musicFileNames: <String>['demo.mid'],
        ),
      ],
      currentPlaylistId: allSongsPlaylistId,
    );
  }

  MusicLibraryNotifier buildNotifier() =>
      _FakeMusicLibraryNotifier(buildLibraryState());

  testWidgets('library screen renders playlist bar and export entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicLibraryProvider.overrideWith(buildNotifier)],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('current-target-action')), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('全部歌曲'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('练习'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.byTooltip('导出'), findsOneWidget);

    await tester.tap(find.byTooltip('导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出原文件'), findsOneWidget);
  });

  testWidgets('long press enters selection mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicLibraryProvider.overrideWith(buildNotifier)],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('demo.mid'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 首'), findsOneWidget);
    expect(find.byIcon(Icons.select_all), findsOneWidget);
  });

  testWidgets('search text stays after leaving selection mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicLibraryProvider.overrideWith(buildNotifier)],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(SearchBar), 'demo');
    await tester.pumpAndSettle();

    await tester.longPress(find.text('demo.mid'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final searchBar = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(searchBar.controller?.text, 'demo');
  });

  testWidgets('import result dialog lists every failed file and reason', (
    tester,
  ) async {
    const report = MusicImportReport(
      importedCount: 1,
      failures: <MusicImportFailure>[
        MusicImportFailure(
          fileName: 'readme.txt',
          kind: MusicImportFailureKind.formatDetectionFailed,
          message: '无法识别 TXT 乐谱格式',
        ),
        MusicImportFailure(
          fileName: 'empty.mid',
          kind: MusicImportFailureKind.emptyScore,
          message: '乐谱中没有可播放音符',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: MusicImportResultDialog(report: report)),
    );

    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('成功 1 个，失败 2 个'), findsOneWidget);
    expect(find.text('readme.txt'), findsOneWidget);
    expect(find.text('无法识别 TXT 乐谱格式'), findsOneWidget);
    expect(find.text('empty.mid'), findsOneWidget);
    expect(find.text('乐谱中没有可播放音符'), findsOneWidget);
  });
}

class _FakeMusicLibraryNotifier extends MusicLibraryNotifier {
  _FakeMusicLibraryNotifier(this._state);

  final MusicLibraryState _state;

  @override
  Future<MusicLibraryState> build() async => _state;
}
