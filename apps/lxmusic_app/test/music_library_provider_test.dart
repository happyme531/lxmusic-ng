import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/features/library/models/library_playlist.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/library/providers/music_library_provider.dart';
import 'package:lxmusic_app/features/library/services/archive_import_service.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('migrates legacy favorites into 收藏 playlist', () async {
    final legacyFile = MusicFile(
      path: '/tmp/demo.mid',
      fileName: 'demo.mid',
      formatId: 'midi',
      isFavorite: true,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'music_library_index': jsonEncode(<Object?>[legacyFile.toJson()]),
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = await container.read(musicLibraryProvider.future);

    expect(state.files, hasLength(1));
    expect(state.favoritePlaylist.musicFileNames, contains('demo.mid'));
    expect(state.currentPlaylistId, allSongsPlaylistId);
  });

  test('deleting current custom playlist falls back to 全部歌曲', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(musicLibraryProvider.future);
    final notifier = container.read(musicLibraryProvider.notifier);
    final created = await notifier.createPlaylist('练习');
    expect(created, isTrue);

    final createdState = container.read(musicLibraryProvider).value!;
    final playlistId = createdState.playlists
        .firstWhere((playlist) => playlist.name == '练习')
        .id;
    await notifier.setCurrentPlaylist(playlistId);
    await notifier.deletePlaylist(playlistId);

    final finalState = container.read(musicLibraryProvider).value!;
    expect(finalState.currentPlaylistId, allSongsPlaylistId);
    expect(
      finalState.playlists.any((playlist) => playlist.id == playlistId),
      isFalse,
    );
  });

  test(
    're-importing same filename overwrites library copy and refreshes metadata',
    () async {
      final container = ProviderContainer(
        overrides: [
          fileStoreProvider.overrideWithValue(_TestPlatformFileStore()),
          parserRegistryProvider.overrideWithValue(
            ParserRegistry(<String, ScoreParser>{'midi': _FakeMidiParser()}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(musicLibraryProvider.notifier);
      await container.read(musicLibraryProvider.future);

      final firstReport = await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'demo.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
      ]);
      expect(firstReport.importedCount, 1);
      expect(firstReport.failures, isEmpty);

      final firstState = container.read(musicLibraryProvider).value!;
      expect(firstState.files.single.noteCount, 1);
      expect(
        await container
            .read(fileStoreProvider)
            .readBytes(firstState.files.single.path),
        orderedEquals(const <int>[1]),
      );

      final secondReport = await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'demo.mid',
          bytes: Uint8List.fromList(const <int>[3]),
        ),
      ]);
      expect(secondReport.importedCount, 1);
      expect(secondReport.failures, isEmpty);

      final secondState = container.read(musicLibraryProvider).value!;
      expect(secondState.files.single.noteCount, 3);
      expect(
        await container
            .read(fileStoreProvider)
            .readBytes(secondState.files.single.path),
        orderedEquals(const <int>[3]),
      );
    },
  );

  test(
    'plain txt is detected and unknown text is reported without storage',
    () async {
      final fileStore = _TestPlatformFileStore();
      final container = ProviderContainer(
        overrides: [fileStoreProvider.overrideWithValue(fileStore)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(musicLibraryProvider.notifier);
      await container.read(musicLibraryProvider.future);
      final report = await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'scale.txt',
          bytes: Uint8List.fromList(utf8.encode('1 2 3')),
        ),
        PickedFileData(
          fileName: 'notes.txt',
          bytes: Uint8List.fromList(utf8.encode('普通说明文字')),
        ),
      ]);

      expect(report.importedCount, 1);
      expect(report.failures, hasLength(1));
      expect(report.failures.single.fileName, 'notes.txt');
      expect(
        report.failures.single.kind,
        MusicImportFailureKind.formatDetectionFailed,
      );
      final state = container.read(musicLibraryProvider).value!;
      expect(state.files.single.fileName, 'scale.txt');
      expect(state.files.single.formatId, 'domiso');
      expect(state.files.single.noteCount, 3);
      expect(await fileStore.exists('memory://notes.txt'), isFalse);
    },
  );

  test(
    'empty same-name replacement is rejected and preserves old file',
    () async {
      final fileStore = _TestPlatformFileStore();
      final container = ProviderContainer(
        overrides: [
          fileStoreProvider.overrideWithValue(fileStore),
          parserRegistryProvider.overrideWithValue(
            ParserRegistry(<String, ScoreParser>{'midi': _FakeMidiParser()}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(musicLibraryProvider.notifier);
      await container.read(musicLibraryProvider.future);
      await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'demo.mid',
          bytes: Uint8List.fromList(const <int>[2]),
        ),
      ]);
      final report = await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'demo.mid',
          bytes: Uint8List.fromList(const <int>[0]),
        ),
      ]);

      expect(report.importedCount, 0);
      expect(report.failures.single.kind, MusicImportFailureKind.emptyScore);
      final state = container.read(musicLibraryProvider).value!;
      expect(state.files.single.noteCount, 2);
      expect(
        await fileStore.readBytes(state.files.single.path),
        orderedEquals(const <int>[2]),
      );
    },
  );

  test(
    'rename conflict keeps both ordinary files and preserves compound suffix',
    () async {
      final container = ProviderContainer(
        overrides: [
          fileStoreProvider.overrideWithValue(_TestPlatformFileStore()),
          parserRegistryProvider.overrideWithValue(
            ParserRegistry(<String, ScoreParser>{'midi': _FakeMidiParser()}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(musicLibraryProvider.notifier);
      await container.read(musicLibraryProvider.future);
      await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'demo.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
      ]);

      final report = await notifier.importFiles(
        <PickedFileData>[
          PickedFileData(
            fileName: 'demo.mid',
            bytes: Uint8List.fromList(const <int>[2]),
          ),
        ],
        resolveConflict: (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.rename,
        ),
      );

      expect(report.importedCount, 1);
      expect(report.renamedCount, 1);
      expect(
        container
            .read(musicLibraryProvider)
            .value!
            .files
            .map((file) => file.fileName)
            .toSet(),
        <String>{'demo.mid', 'demo (2).mid'},
      );
    },
  );

  test(
    'apply-to-remaining resolves later conflicts without asking again',
    () async {
      final container = ProviderContainer(
        overrides: [
          fileStoreProvider.overrideWithValue(_TestPlatformFileStore()),
          parserRegistryProvider.overrideWithValue(
            ParserRegistry(<String, ScoreParser>{'midi': _FakeMidiParser()}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(musicLibraryProvider.notifier);
      await container.read(musicLibraryProvider.future);
      await notifier.importFiles(<PickedFileData>[
        PickedFileData(
          fileName: 'a.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
        PickedFileData(
          fileName: 'b.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
      ]);
      var resolverCalls = 0;

      final report = await notifier.importFiles(
        <PickedFileData>[
          PickedFileData(
            fileName: 'a.mid',
            bytes: Uint8List.fromList(const <int>[2]),
          ),
          PickedFileData(
            fileName: 'b.mid',
            bytes: Uint8List.fromList(const <int>[2]),
          ),
        ],
        resolveConflict: (_) async {
          resolverCalls++;
          return const MusicImportConflictDecision(
            action: MusicImportConflictAction.rename,
            applyToRemaining: true,
          );
        },
      );

      expect(resolverCalls, 1);
      expect(report.importedCount, 2);
      expect(report.renamedCount, 2);
      expect(
        container
            .read(musicLibraryProvider)
            .value!
            .files
            .map((file) => file.fileName)
            .toSet(),
        <String>{'a.mid', 'a (2).mid', 'b.mid', 'b (2).mid'},
      );
    },
  );

  test('stop keeps ordinary files completed before the conflict', () async {
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(_TestPlatformFileStore()),
        parserRegistryProvider.overrideWithValue(
          ParserRegistry(<String, ScoreParser>{'midi': _FakeMidiParser()}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(musicLibraryProvider.notifier);
    await container.read(musicLibraryProvider.future);
    await notifier.importFiles(<PickedFileData>[
      PickedFileData(
        fileName: 'existing.mid',
        bytes: Uint8List.fromList(const <int>[1]),
      ),
    ]);

    final report = await notifier.importFiles(
      <PickedFileData>[
        PickedFileData(
          fileName: 'first.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
        PickedFileData(
          fileName: 'existing.mid',
          bytes: Uint8List.fromList(const <int>[2]),
        ),
        PickedFileData(
          fileName: 'last.mid',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
      ],
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.stop,
      ),
    );

    expect(report.stopped, isTrue);
    expect(report.importedCount, 1);
    expect(
      container
          .read(musicLibraryProvider)
          .value!
          .files
          .map((file) => file.fileName)
          .toSet(),
      <String>{'existing.mid', 'first.mid'},
    );
  });

  test('ZIP import creates, numbers, and selects a playlist', () async {
    final archiveService = _FakeArchiveImportService(
      ArchiveImportResult(
        archiveFileName: '练习.zip',
        files: const <PreparedImportedMusicFile>[
          PreparedImportedMusicFile(
            path: 'archive://scale.txt',
            fileName: 'scale.txt',
            formatId: 'domiso',
            trackCount: 1,
            durationMs: 1000,
            noteCount: 3,
            wasOverwrite: false,
            wasRenamed: false,
          ),
        ],
        playlistFileNames: const <String>['scale.txt'],
        failures: const <MusicImportFailure>[],
        storageRoot: 'archive://root',
        reusedCount: 0,
        skippedCount: 0,
        ignoredCount: 2,
        stopped: false,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(_TestPlatformFileStore()),
        archiveImportServiceProvider.overrideWithValue(archiveService),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicLibraryProvider.future);
    final notifier = container.read(musicLibraryProvider.notifier);
    expect(await notifier.createPlaylist('练习'), isTrue);

    final report = await notifier.importFiles(const <PickedFileData>[
      PickedFileData(fileName: '练习.zip', sourcePath: '/tmp/练习.zip'),
    ]);

    final library = container.read(musicLibraryProvider).value!;
    final importedPlaylist = library.playlists.firstWhere(
      (playlist) => playlist.name == '练习 (2)',
    );
    expect(importedPlaylist.musicFileNames, <String>['scale.txt']);
    expect(library.currentPlaylistId, importedPlaylist.id);
    expect(report.archives.single.playlistName, '练习 (2)');
    expect(report.ignoredCount, 2);
  });

  test('filtered music files keeps favorites above non-favorites', () async {
    final container = ProviderContainer(
      overrides: [
        musicLibraryProvider.overrideWith(
          () => _StaticMusicLibraryNotifier(
            MusicLibraryState(
              files: <MusicFile>[
                MusicFile(
                  path: '/tmp/c.mid',
                  fileName: 'c.mid',
                  formatId: 'midi',
                ),
                MusicFile(
                  path: '/tmp/a.mid',
                  fileName: 'a.mid',
                  formatId: 'midi',
                ),
                MusicFile(
                  path: '/tmp/b.mid',
                  fileName: 'b.mid',
                  formatId: 'midi',
                ),
              ],
              playlists: const <LibraryPlaylist>[
                LibraryPlaylist(
                  id: favoritesPlaylistId,
                  name: '收藏',
                  musicFileNames: <String>['c.mid'],
                  isBuiltinFavorite: true,
                ),
                LibraryPlaylist(
                  id: 'playlist_custom',
                  name: '练习',
                  musicFileNames: <String>['a.mid', 'c.mid'],
                ),
              ],
              currentPlaylistId: allSongsPlaylistId,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(musicLibraryProvider.future);

    expect(
      container
          .read(filteredMusicFilesProvider)
          .value!
          .map((file) => file.fileName)
          .toList(),
      <String>['c.mid', 'a.mid', 'b.mid'],
    );

    await container
        .read(musicLibraryProvider.notifier)
        .setCurrentPlaylist('playlist_custom');

    expect(
      container
          .read(filteredMusicFilesProvider)
          .value!
          .map((file) => file.fileName)
          .toList(),
      <String>['c.mid', 'a.mid'],
    );
  });
}

class _FakeMidiParser implements ScoreParser {
  @override
  String get formatId => 'midi';

  @override
  Score parse(Uint8List bytes) {
    final count = bytes.isEmpty ? 0 : bytes.first;
    return Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Fake',
          channel: 0,
          notes: List<NoteEvent>.generate(
            count,
            (index) =>
                NoteEvent(pitch: 60, startMs: index * 100, durationMs: 100),
          ),
        ),
      ],
    );
  }
}

class _StaticMusicLibraryNotifier extends MusicLibraryNotifier {
  _StaticMusicLibraryNotifier(this._state);

  final MusicLibraryState _state;

  @override
  Future<MusicLibraryState> build() async => _state;
}

class _TestPlatformFileStore implements PlatformFileStore {
  _TestPlatformFileStore();

  final Map<String, Uint8List> _files = <String, Uint8List>{};

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(path);
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(path);

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) => throw UnimplementedError();

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final destinationPath = 'memory://$fileName';
    _files[destinationPath] = Uint8List.fromList(bytes);
    return destinationPath;
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    return Uint8List.fromList(_files[path]!);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _files[path] = Uint8List.fromList(bytes);
  }
}

class _FakeArchiveImportService extends ArchiveImportService {
  _FakeArchiveImportService(this.result);

  final ArchiveImportResult result;

  @override
  bool get isSupported => true;

  @override
  Future<void> cleanupUnreferencedStorage(Set<String> referencedPaths) async {}

  @override
  Future<void> discardStorage(String? storageRoot) async {}

  @override
  Future<ArchiveImportResult> importArchive({
    required String archiveFileName,
    required String? sourcePath,
    required Uint8List? bytes,
    required Set<String> knownFileNames,
    required MusicImportConflictResolver resolveConflict,
    required MusicImportProgressCallback onProgress,
    required MusicImportCancellationToken cancellationToken,
  }) async => result;
}
