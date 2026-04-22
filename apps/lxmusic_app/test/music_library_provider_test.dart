import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/features/library/models/library_playlist.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/library/providers/music_library_provider.dart';
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

  test('re-importing same filename overwrites library copy and refreshes metadata', () async {
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(
          _TestPlatformFileStore(),
        ),
        parserRegistryProvider.overrideWithValue(
          ParserRegistry(<String, ScoreParser>{
            'midi': _FakeMidiParser(),
          }),
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

    final firstState = container.read(musicLibraryProvider).value!;
    expect(firstState.files.single.noteCount, 1);
    expect(
      await container.read(fileStoreProvider).readBytes(firstState.files.single.path),
      orderedEquals(const <int>[1]),
    );

    await notifier.importFiles(<PickedFileData>[
      PickedFileData(
        fileName: 'demo.mid',
        bytes: Uint8List.fromList(const <int>[3]),
      ),
    ]);

    final secondState = container.read(musicLibraryProvider).value!;
    expect(secondState.files.single.noteCount, 3);
    expect(
      await container.read(fileStoreProvider).readBytes(secondState.files.single.path),
      orderedEquals(const <int>[3]),
    );
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
            (index) => NoteEvent(
              pitch: 60,
              startMs: index * 100,
              durationMs: 100,
            ),
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
