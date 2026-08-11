import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_locator.dart';
import '../../../core/platform/file_store.dart';
import '../models/library_playlist.dart';
import '../models/music_file.dart';

const _libraryIndexStorageKey = 'music_library_index';
const _playlistStorageKey = 'music_library_playlists';
const _selectedPlaylistStorageKey = 'music_library_selected_playlist';

const allSongsPlaylistId = 'all';
const favoritesPlaylistId = 'favorites';

enum MusicImportFailureKind {
  unreadableFile,
  formatDetectionFailed,
  invalidFormat,
  emptyScore,
  storageError,
}

class MusicImportFailure {
  const MusicImportFailure({
    required this.fileName,
    required this.kind,
    required this.message,
  });

  final String fileName;
  final MusicImportFailureKind kind;
  final String message;
}

class MusicImportReport {
  const MusicImportReport({
    required this.importedCount,
    required this.failures,
  });

  final int importedCount;
  final List<MusicImportFailure> failures;
}

final musicLibraryProvider =
    AsyncNotifierProvider<MusicLibraryNotifier, MusicLibraryState>(
      MusicLibraryNotifier.new,
    );

final searchQueryProvider = NotifierProvider<_StringNotifier, String>(
  _StringNotifier.new,
);

class _StringNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final availablePlaylistsProvider = Provider<List<LibraryPlaylistView>>((ref) {
  final library = ref.watch(musicLibraryProvider).value;
  if (library == null) {
    return const <LibraryPlaylistView>[
      LibraryPlaylistView(
        id: allSongsPlaylistId,
        name: '全部歌曲',
        isVirtual: true,
      ),
    ];
  }

  return <LibraryPlaylistView>[
    const LibraryPlaylistView(
      id: allSongsPlaylistId,
      name: '全部歌曲',
      isVirtual: true,
    ),
    ...library.playlists.map(
      (playlist) => LibraryPlaylistView(
        id: playlist.id,
        name: playlist.name,
        isVirtual: false,
        isBuiltinFavorite: playlist.isBuiltinFavorite,
      ),
    ),
  ];
});

final currentPlaylistViewProvider = Provider<LibraryPlaylistView>((ref) {
  final playlists = ref.watch(availablePlaylistsProvider);
  final currentId =
      ref.watch(musicLibraryProvider).value?.currentPlaylistId ??
      allSongsPlaylistId;
  return playlists.firstWhere(
    (playlist) => playlist.id == currentId,
    orElse: () => const LibraryPlaylistView(
      id: allSongsPlaylistId,
      name: '全部歌曲',
      isVirtual: true,
    ),
  );
});

final filteredMusicFilesProvider = Provider<AsyncValue<List<MusicFile>>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  return ref.watch(musicLibraryProvider).whenData((library) {
    final currentPlaylist = library.currentPlaylist;
    var result = library.files;
    if (currentPlaylist != null) {
      final names = currentPlaylist.musicFileNames.toSet();
      result = result.where((file) => names.contains(file.fileName)).toList();
    }
    if (query.isNotEmpty) {
      result = result
          .where((file) => file.fileName.toLowerCase().contains(query))
          .toList();
    }
    final sorted = result.toList()
      ..sort((a, b) => _compareMusicFiles(library, a, b));
    return sorted;
  });
});

int _compareMusicFiles(MusicLibraryState library, MusicFile a, MusicFile b) {
  final favoriteOrder = (library.isFavorite(b.fileName) ? 1 : 0).compareTo(
    library.isFavorite(a.fileName) ? 1 : 0,
  );
  if (favoriteOrder != 0) {
    return favoriteOrder;
  }
  return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
}

class MusicLibraryNotifier extends AsyncNotifier<MusicLibraryState> {
  @override
  Future<MusicLibraryState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final files = _loadIndex(prefs);
    var playlists = _loadPlaylists(prefs);
    final legacyFavorites = files
        .where((file) => file.isFavorite)
        .map((file) => file.fileName)
        .toSet();
    var dirty = false;

    final dedupedPlaylists = _dedupePlaylists(playlists);
    if (dedupedPlaylists.length != playlists.length) {
      dirty = true;
    }
    playlists = dedupedPlaylists;
    final knownFileNames = files.map((file) => file.fileName).toSet();
    final sanitizedPlaylists = <LibraryPlaylist>[];
    for (final playlist in playlists) {
      final filteredNames =
          playlist.musicFileNames
              .where(knownFileNames.contains)
              .toSet()
              .toList()
            ..sort();
      if (filteredNames.length != playlist.musicFileNames.length) {
        dirty = true;
      }
      sanitizedPlaylists.add(playlist.copyWith(musicFileNames: filteredNames));
    }
    playlists = sanitizedPlaylists;

    final favoriteIndex = playlists.indexWhere(
      (playlist) =>
          playlist.id == favoritesPlaylistId || playlist.isBuiltinFavorite,
    );
    if (favoriteIndex >= 0) {
      final favorite = playlists[favoriteIndex];
      final mergedNames = <String>{
        ...favorite.musicFileNames,
        ...legacyFavorites,
      }.toList()..sort();
      if (mergedNames.length != favorite.musicFileNames.length ||
          favorite.id != favoritesPlaylistId ||
          favorite.name != '收藏' ||
          !favorite.isBuiltinFavorite) {
        playlists[favoriteIndex] = favorite.copyWith(
          id: favoritesPlaylistId,
          name: '收藏',
          isBuiltinFavorite: true,
          musicFileNames: mergedNames,
        );
        dirty = true;
      }
    } else {
      playlists = <LibraryPlaylist>[
        LibraryPlaylist(
          id: favoritesPlaylistId,
          name: '收藏',
          isBuiltinFavorite: true,
          musicFileNames: legacyFavorites.toList()..sort(),
        ),
        ...playlists,
      ];
      dirty = true;
    }

    var currentPlaylistId =
        prefs.getString(_selectedPlaylistStorageKey) ?? allSongsPlaylistId;
    if (currentPlaylistId != allSongsPlaylistId &&
        !playlists.any((playlist) => playlist.id == currentPlaylistId)) {
      currentPlaylistId = allSongsPlaylistId;
      dirty = true;
    }

    final next = MusicLibraryState(
      files: files,
      playlists: playlists,
      currentPlaylistId: currentPlaylistId,
    );
    if (dirty) {
      await _saveState(next);
    }
    return next;
  }

  List<MusicFile> _loadIndex(SharedPreferences prefs) {
    final raw = prefs.getString(_libraryIndexStorageKey);
    if (raw == null) {
      return <MusicFile>[];
    }
    final list = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item.cast<String, Object?>()))
        .toList();
    return list.map(MusicFile.fromJson).toList()
      ..sort((a, b) => a.fileName.compareTo(b.fileName));
  }

  List<LibraryPlaylist> _loadPlaylists(SharedPreferences prefs) {
    final raw = prefs.getString(_playlistStorageKey);
    if (raw == null) {
      return <LibraryPlaylist>[];
    }
    final list = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item.cast<String, Object?>()))
        .toList();
    return list.map(LibraryPlaylist.fromJson).toList();
  }

  List<LibraryPlaylist> _dedupePlaylists(List<LibraryPlaylist> playlists) {
    final seenIds = <String>{};
    final deduped = <LibraryPlaylist>[];
    for (final playlist in playlists) {
      if (seenIds.add(playlist.id)) {
        deduped.add(playlist);
      }
    }
    return deduped;
  }

  Future<void> _saveState(MusicLibraryState next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _libraryIndexStorageKey,
      jsonEncode(next.files.map((file) => file.toJson()).toList()),
    );
    await prefs.setString(
      _playlistStorageKey,
      jsonEncode(next.playlists.map((playlist) => playlist.toJson()).toList()),
    );
    await prefs.setString(_selectedPlaylistStorageKey, next.currentPlaylistId);
  }

  Future<void> _replaceState(MusicLibraryState next) async {
    await _saveState(next);
    state = AsyncData(next);
  }

  Future<MusicImportReport> importFiles(
    List<PickedFileData> pickedFiles,
  ) async {
    final registry = ref.read(parserRegistryProvider);
    final detector = ref.read(scoreFormatDetectorProvider);
    final fileStore = ref.read(fileStoreProvider);
    final current = state.value ?? const MusicLibraryState.empty();
    final files = List<MusicFile>.of(current.files);
    final failures = <MusicImportFailure>[];
    var imported = 0;

    for (final pickedFile in pickedFiles) {
      if (!pickedFile.hasReadableContent) {
        failures.add(
          MusicImportFailure(
            fileName: pickedFile.fileName,
            kind: MusicImportFailureKind.unreadableFile,
            message: '无法读取文件内容',
          ),
        );
        continue;
      }
      final fileName = pickedFile.fileName;
      late final Uint8List bytes;
      try {
        bytes =
            pickedFile.bytes ??
            await fileStore.readBytes(pickedFile.sourcePath!);
      } catch (_) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.unreadableFile,
            message: '无法读取文件内容',
          ),
        );
        continue;
      }

      final detection = detector.detect(fileName: fileName, bytes: bytes);
      if (detection case RejectedScoreFormat()) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.formatDetectionFailed,
            message: detection.message,
          ),
        );
        continue;
      }
      final format = (detection as DetectedScoreFormat).formatId;

      late final Score score;
      try {
        score = registry.parse(bytes: bytes, formatId: format);
      } catch (error) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.invalidFormat,
            message: _parserFailureMessage(format, error),
          ),
        );
        continue;
      }
      if (score.totalNoteCount == 0) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.emptyScore,
            message: '乐谱中没有可播放音符',
          ),
        );
        continue;
      }

      late final String destPath;
      try {
        destPath = await fileStore.importBytes(
          fileName: fileName,
          bytes: bytes,
        );
      } catch (_) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.storageError,
            message: '保存到曲库失败',
          ),
        );
        continue;
      }

      final previous = files
          .where((file) => file.fileName == fileName)
          .toList();
      for (final existing in previous) {
        if (existing.path == destPath) {
          continue;
        }
        try {
          await fileStore.deleteFile(existing.path);
        } catch (_) {}
      }
      final musicFile = MusicFile(
        path: destPath,
        fileName: fileName,
        formatId: format,
        trackCount: score.tracks.length,
        durationMs: score.totalDurationMs,
        noteCount: score.totalNoteCount,
        importedAt: DateTime.now(),
      );

      files.removeWhere((file) => file.fileName == fileName);
      files.add(musicFile);
      imported++;
    }

    if (imported > 0) {
      files.sort((a, b) => a.fileName.compareTo(b.fileName));
      await _replaceState(current.copyWith(files: files));
    }
    return MusicImportReport(importedCount: imported, failures: failures);
  }

  String _parserFailureMessage(String format, Object error) {
    final detail = switch (error) {
      FormatException(:final message) => message,
      _ => '文件结构不符合要求',
    };
    return '$format 文件内容无效：$detail';
  }

  Future<void> setCurrentPlaylist(String playlistId) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (playlistId != allSongsPlaylistId &&
        !current.playlists.any((playlist) => playlist.id == playlistId)) {
      return;
    }
    await _replaceState(current.copyWith(currentPlaylistId: playlistId));
  }

  Future<bool> createPlaylist(String name) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        current.playlists.any((playlist) => playlist.name == trimmed)) {
      return false;
    }
    final next = current.copyWith(
      playlists: <LibraryPlaylist>[
        ...current.playlists,
        LibraryPlaylist(
          id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
          name: trimmed,
          musicFileNames: const <String>[],
          createdAt: DateTime.now(),
        ),
      ],
    );
    await _replaceState(next);
    return true;
  }

  Future<bool> renamePlaylist(String playlistId, String name) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final trimmed = name.trim();
    final index = current.playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );
    if (index < 0 ||
        current.playlists[index].isBuiltinFavorite ||
        trimmed.isEmpty ||
        current.playlists.any(
          (playlist) => playlist.id != playlistId && playlist.name == trimmed,
        )) {
      return false;
    }
    final playlists = List<LibraryPlaylist>.of(current.playlists);
    playlists[index] = playlists[index].copyWith(name: trimmed);
    await _replaceState(current.copyWith(playlists: playlists));
    return true;
  }

  Future<bool> deletePlaylist(String playlistId) async {
    final current = state.value;
    if (current == null) {
      return false;
    }
    final index = current.playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) {
      return false;
    }
    final playlist = current.playlists[index];
    if (playlist.isBuiltinFavorite) {
      return false;
    }
    final playlists = current.playlists
        .where((item) => item.id != playlistId)
        .toList();
    await _replaceState(
      current.copyWith(
        playlists: playlists,
        currentPlaylistId: current.currentPlaylistId == playlistId
            ? allSongsPlaylistId
            : current.currentPlaylistId,
      ),
    );
    return true;
  }

  Future<int> addFilesToPlaylist(
    String playlistId,
    Iterable<String> fileNames,
  ) async {
    final current = state.value;
    if (current == null || playlistId == allSongsPlaylistId) {
      return 0;
    }
    final index = current.playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );
    if (index < 0) {
      return 0;
    }
    final knownFiles = current.files.map((file) => file.fileName).toSet();
    final nextNames = <String>{
      ...current.playlists[index].musicFileNames,
      ...fileNames.where(knownFiles.contains),
    }.toList()..sort();
    final added =
        nextNames.length - current.playlists[index].musicFileNames.length;
    if (added <= 0) {
      return 0;
    }
    final playlists = List<LibraryPlaylist>.of(current.playlists);
    playlists[index] = playlists[index].copyWith(musicFileNames: nextNames);
    await _replaceState(current.copyWith(playlists: playlists));
    return added;
  }

  Future<int> removeFilesFromPlaylist(
    String playlistId,
    Iterable<String> fileNames,
  ) async {
    final current = state.value;
    if (current == null || playlistId == allSongsPlaylistId) {
      return 0;
    }
    final index = current.playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );
    if (index < 0) {
      return 0;
    }
    final toRemove = fileNames.toSet();
    final nextNames = current.playlists[index].musicFileNames
        .where((name) => !toRemove.contains(name))
        .toList();
    final removed =
        current.playlists[index].musicFileNames.length - nextNames.length;
    if (removed <= 0) {
      return 0;
    }
    final playlists = List<LibraryPlaylist>.of(current.playlists);
    playlists[index] = playlists[index].copyWith(musicFileNames: nextNames);
    await _replaceState(current.copyWith(playlists: playlists));
    return removed;
  }

  Future<void> toggleFavorite(String fileName) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final favorite = current.favoritePlaylist;
    final isFavorite = favorite.contains(fileName);
    if (isFavorite) {
      await removeFilesFromPlaylist(favorite.id, <String>[fileName]);
    } else {
      await addFilesToPlaylist(favorite.id, <String>[fileName]);
    }
  }

  Future<int> deleteFiles(Iterable<String> fileNames) async {
    final current = state.value;
    if (current == null) {
      return 0;
    }
    final toDelete = fileNames.toSet();
    var deleted = 0;
    final fileStore = ref.read(fileStoreProvider);
    for (final file in current.files.where(
      (item) => toDelete.contains(item.fileName),
    )) {
      await fileStore.deleteFile(file.path);
      deleted++;
    }

    final files = current.files
        .where((file) => !toDelete.contains(file.fileName))
        .toList();
    final playlists = current.playlists
        .map(
          (playlist) => playlist.copyWith(
            musicFileNames: playlist.musicFileNames
                .where((fileName) => !toDelete.contains(fileName))
                .toList(),
          ),
        )
        .toList();
    await _replaceState(current.copyWith(files: files, playlists: playlists));
    return deleted;
  }
}

class MusicLibraryState {
  const MusicLibraryState({
    required this.files,
    required this.playlists,
    required this.currentPlaylistId,
  });

  const MusicLibraryState.empty()
    : files = const <MusicFile>[],
      playlists = const <LibraryPlaylist>[
        LibraryPlaylist(
          id: favoritesPlaylistId,
          name: '收藏',
          musicFileNames: <String>[],
          isBuiltinFavorite: true,
        ),
      ],
      currentPlaylistId = allSongsPlaylistId;

  final List<MusicFile> files;
  final List<LibraryPlaylist> playlists;
  final String currentPlaylistId;

  LibraryPlaylist get favoritePlaylist =>
      playlists.firstWhere((playlist) => playlist.id == favoritesPlaylistId);

  LibraryPlaylist? get currentPlaylist =>
      currentPlaylistId == allSongsPlaylistId
      ? null
      : playlists.firstWhere(
          (playlist) => playlist.id == currentPlaylistId,
          orElse: () => favoritePlaylist,
        );

  bool isFavorite(String fileName) => favoritePlaylist.contains(fileName);

  MusicLibraryState copyWith({
    List<MusicFile>? files,
    List<LibraryPlaylist>? playlists,
    String? currentPlaylistId,
  }) {
    return MusicLibraryState(
      files: files ?? this.files,
      playlists: playlists ?? this.playlists,
      currentPlaylistId: currentPlaylistId ?? this.currentPlaylistId,
    );
  }
}

class LibraryPlaylistView {
  const LibraryPlaylistView({
    required this.id,
    required this.name,
    required this.isVirtual,
    this.isBuiltinFavorite = false,
  });

  final String id;
  final String name;
  final bool isVirtual;
  final bool isBuiltinFavorite;

  bool get isEditable => !isVirtual && !isBuiltinFavorite;
}
