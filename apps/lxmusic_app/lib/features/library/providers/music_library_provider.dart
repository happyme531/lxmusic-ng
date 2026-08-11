import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_locator.dart';
import '../../../core/platform/file_store.dart';
import '../models/library_playlist.dart';
import '../models/music_import.dart';
import '../models/music_file.dart';
import '../services/archive_import_service.dart';

export '../models/music_import.dart';

const _libraryIndexStorageKey = 'music_library_index';
const _playlistStorageKey = 'music_library_playlists';
const _selectedPlaylistStorageKey = 'music_library_selected_playlist';

const allSongsPlaylistId = 'all';
const favoritesPlaylistId = 'favorites';

Map<String, Object?> _decodeLibraryPersistence(List<String?> raw) {
  return <String, Object?>{
    'files': raw[0] == null ? <Object?>[] : jsonDecode(raw[0]!) as List,
    'playlists': raw[1] == null ? <Object?>[] : jsonDecode(raw[1]!) as List,
  };
}

Map<String, String> _encodeLibraryPersistence(Map<String, Object?> raw) {
  return <String, String>{
    if (raw.containsKey('files')) 'files': jsonEncode(raw['files']),
    if (raw.containsKey('playlists')) 'playlists': jsonEncode(raw['playlists']),
  };
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
    final playlistFiles = library.filesForPlaylist(library.currentPlaylistId);
    if (query.isEmpty) return playlistFiles;
    return playlistFiles
        .where((file) => file.normalizedFileName.contains(query))
        .toList(growable: false);
  });
});

class MusicLibraryNotifier extends AsyncNotifier<MusicLibraryState> {
  @override
  Future<MusicLibraryState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = await compute(_decodeLibraryPersistence, <String?>[
      prefs.getString(_libraryIndexStorageKey),
      prefs.getString(_playlistStorageKey),
    ]);
    final files =
        (decoded['files']! as List)
            .whereType<Map>()
            .map(
              (item) => Map<String, Object?>.from(item.cast<String, Object?>()),
            )
            .map(MusicFile.fromJson)
            .toList()
          ..sort((a, b) => a.fileName.compareTo(b.fileName));
    var playlists = (decoded['playlists']! as List)
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item.cast<String, Object?>()))
        .map(LibraryPlaylist.fromJson)
        .toList();
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
    try {
      await ref
          .read(archiveImportServiceProvider)
          .cleanupUnreferencedStorage(files.map((file) => file.path).toSet());
    } catch (_) {}
    return next;
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

  Future<void> _saveState(
    MusicLibraryState next, {
    bool saveFiles = true,
    bool savePlaylists = true,
    bool saveSelection = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (saveFiles || savePlaylists) {
      final encoded =
          await compute(_encodeLibraryPersistence, <String, Object?>{
            if (saveFiles)
              'files': next.files
                  .map((file) => file.toJson())
                  .toList(growable: false),
            if (savePlaylists)
              'playlists': next.playlists
                  .map((playlist) => playlist.toJson())
                  .toList(growable: false),
          });
      if (encoded['files'] case final files?) {
        await prefs.setString(_libraryIndexStorageKey, files);
      }
      if (encoded['playlists'] case final playlists?) {
        await prefs.setString(_playlistStorageKey, playlists);
      }
    }
    if (saveSelection) {
      await prefs.setString(
        _selectedPlaylistStorageKey,
        next.currentPlaylistId,
      );
    }
  }

  Future<void> _replaceState(
    MusicLibraryState next, {
    bool saveFiles = true,
    bool savePlaylists = true,
    bool saveSelection = true,
  }) async {
    await _saveState(
      next,
      saveFiles: saveFiles,
      savePlaylists: savePlaylists,
      saveSelection: saveSelection,
    );
    state = AsyncData(next);
  }

  Future<MusicImportReport> importFiles(
    List<PickedFileData> pickedFiles, {
    MusicImportConflictResolver? resolveConflict,
    MusicImportProgressCallback? onProgress,
    MusicImportCancellationToken? cancellationToken,
  }) async {
    final registry = ref.read(parserRegistryProvider);
    final detector = ref.read(scoreFormatDetectorProvider);
    final fileStore = ref.read(fileStoreProvider);
    final archiveImporter = ref.read(archiveImportServiceProvider);
    final current = state.value ?? MusicLibraryState.empty();
    final filesByName = <String, MusicFile>{
      for (final file in current.files) file.fileName: file,
    };
    final failures = <MusicImportFailure>[];
    final createdPaths = <String>{};
    final supersededPaths = <String>{};
    final archiveStorageRoots = <String>{};
    final pendingArchivePlaylists =
        <({String archiveFileName, List<String> members})>[];
    final token = cancellationToken ?? MusicImportCancellationToken();
    final progress = onProgress ?? (_) {};
    final conflictResolver =
        resolveConflict ??
        (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.overwrite,
          applyToRemaining: true,
        );
    MusicImportConflictAction? remainingConflictAction;
    var imported = 0;
    var overwritten = 0;
    var renamed = 0;
    var reused = 0;
    var skipped = 0;
    var ignored = 0;
    var stopped = false;
    var processedSources = 0;

    Future<MusicImportConflictDecision> decideConflict(
      MusicImportConflict conflict,
    ) async {
      final remembered = remainingConflictAction;
      if (remembered != null) {
        return MusicImportConflictDecision(action: remembered);
      }
      final decision = await conflictResolver(conflict);
      if (decision.applyToRemaining &&
          decision.action != MusicImportConflictAction.stop) {
        remainingConflictAction = decision.action;
      }
      return decision;
    }

    for (final pickedFile in pickedFiles) {
      if (token.isStopped) {
        stopped = true;
        break;
      }
      final fileName = pickedFile.fileName;
      if (fileName.toLowerCase().endsWith('.zip')) {
        late final ArchiveImportResult result;
        try {
          result = await archiveImporter.importArchive(
            archiveFileName: fileName,
            sourcePath: pickedFile.sourcePath,
            bytes: pickedFile.bytes,
            knownFileNames: filesByName.keys.toSet(),
            resolveConflict: decideConflict,
            onProgress: progress,
            cancellationToken: token,
          );
        } catch (error) {
          failures.add(
            MusicImportFailure(
              fileName: fileName,
              kind: MusicImportFailureKind.invalidArchive,
              message: 'ZIP 导入失败：$error',
            ),
          );
          processedSources++;
          continue;
        }
        failures.addAll(result.failures);
        reused += result.reusedCount;
        skipped += result.skippedCount;
        ignored += result.ignoredCount;
        if (result.storageRoot case final root?) {
          archiveStorageRoots.add(root);
        }
        for (final prepared in result.files) {
          final previous = filesByName[prepared.fileName];
          if (previous != null && previous.path != prepared.path) {
            supersededPaths.add(previous.path);
          }
          filesByName[prepared.fileName] = MusicFile(
            path: prepared.path,
            fileName: prepared.fileName,
            formatId: prepared.formatId,
            trackCount: prepared.trackCount,
            durationMs: prepared.durationMs,
            noteCount: prepared.noteCount,
            importedAt: DateTime.now(),
          );
          createdPaths.add(prepared.path);
          imported++;
          if (prepared.wasOverwrite) {
            overwritten++;
          }
          if (prepared.wasRenamed) {
            renamed++;
          }
        }
        final members =
            result.playlistFileNames
                .where(filesByName.containsKey)
                .toSet()
                .toList()
              ..sort();
        if (members.isNotEmpty) {
          pendingArchivePlaylists.add((
            archiveFileName: fileName,
            members: members,
          ));
        }
        processedSources++;
        if (result.stopped || token.isStopped) {
          stopped = true;
          break;
        }
        continue;
      }

      if (!pickedFile.hasReadableContent) {
        failures.add(
          MusicImportFailure(
            fileName: pickedFile.fileName,
            kind: MusicImportFailureKind.unreadableFile,
            message: '无法读取文件内容',
          ),
        );
        processedSources++;
        continue;
      }
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
        processedSources++;
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
        processedSources++;
        continue;
      }
      final format = (detection as DetectedScoreFormat).formatId;

      late final Score score;
      final parseWatch = Stopwatch();
      if (format == 'midi') {
        parseWatch.start();
        _logMidiImport(
          'source=picker item=${processedSources + 1}/${pickedFiles.length} '
          'file="$fileName" bytes=${bytes.length} phase=parse_start',
        );
      }
      try {
        score = registry.parse(bytes: bytes, formatId: format);
      } catch (error, stackTrace) {
        if (format == 'midi') {
          _logMidiImport(
            'source=picker item=${processedSources + 1}/${pickedFiles.length} '
            'file="$fileName" bytes=${bytes.length} phase=parse_error '
            'elapsed_ms=${parseWatch.elapsedMilliseconds} error=$error',
            error: error,
            stackTrace: stackTrace,
          );
        }
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.invalidFormat,
            message: _parserFailureMessage(format, error),
          ),
        );
        processedSources++;
        continue;
      }
      if (format == 'midi') {
        _logMidiImport(
          'source=picker item=${processedSources + 1}/${pickedFiles.length} '
          'file="$fileName" bytes=${bytes.length} phase=parse_done '
          'elapsed_ms=${parseWatch.elapsedMilliseconds} '
          'tracks=${score.tracks.length} notes=${score.totalNoteCount} '
          'duration_ms=${score.totalDurationMs}',
        );
      }
      if (score.totalNoteCount == 0) {
        failures.add(
          MusicImportFailure(
            fileName: fileName,
            kind: MusicImportFailureKind.emptyScore,
            message: '乐谱中没有可播放音符',
          ),
        );
        processedSources++;
        continue;
      }

      var targetName = fileName;
      var wasOverwrite = false;
      var wasRenamed = false;
      if (filesByName.containsKey(targetName)) {
        final decision = await decideConflict(
          MusicImportConflict(
            fileName: targetName,
            sourceLabel: fileName,
            fromArchive: false,
          ),
        );
        switch (decision.action) {
          case MusicImportConflictAction.overwrite:
            wasOverwrite = true;
            break;
          case MusicImportConflictAction.skip:
            skipped++;
            processedSources++;
            continue;
          case MusicImportConflictAction.rename:
            targetName = nextAvailableMusicFileName(
              targetName,
              filesByName.keys.toSet(),
            );
            wasRenamed = true;
            break;
          case MusicImportConflictAction.stop:
            stopped = true;
            break;
        }
        if (stopped) {
          break;
        }
      }

      late final String destPath;
      try {
        destPath = await fileStore.importBytes(
          fileName: targetName,
          bytes: bytes,
        );
      } catch (_) {
        failures.add(
          MusicImportFailure(
            fileName: targetName,
            kind: MusicImportFailureKind.storageError,
            message: '保存到曲库失败',
          ),
        );
        processedSources++;
        continue;
      }

      final previous = filesByName[targetName];
      if (previous != null && previous.path != destPath) {
        supersededPaths.add(previous.path);
      }
      final musicFile = MusicFile(
        path: destPath,
        fileName: targetName,
        formatId: format,
        trackCount: score.tracks.length,
        durationMs: score.totalDurationMs,
        noteCount: score.totalNoteCount,
        importedAt: DateTime.now(),
      );

      filesByName[targetName] = musicFile;
      createdPaths.add(destPath);
      imported++;
      if (wasOverwrite) {
        overwritten++;
      }
      if (wasRenamed) {
        renamed++;
      }
      processedSources++;
      progress(
        MusicImportProgress(
          stage: MusicImportStage.importing,
          sourceLabel: fileName,
          currentFileName: fileName,
          processedCount: processedSources,
          totalCount: pickedFiles.length,
          importedCount: imported,
          reusedCount: reused,
          skippedCount: skipped,
          failedCount: failures.length,
          ignoredCount: ignored,
        ),
      );
    }

    final playlists = List<LibraryPlaylist>.of(current.playlists);
    final archiveReports = <MusicImportArchiveReport>[];
    var selectedPlaylistId = current.currentPlaylistId;
    for (var index = 0; index < pendingArchivePlaylists.length; index++) {
      final pending = pendingArchivePlaylists[index];
      final baseName = _archivePlaylistBaseName(pending.archiveFileName);
      final playlistName = _nextPlaylistName(
        baseName,
        playlists.map((playlist) => playlist.name).toSet(),
      );
      final playlistId =
          'playlist_${DateTime.now().microsecondsSinceEpoch}_$index';
      playlists.add(
        LibraryPlaylist(
          id: playlistId,
          name: playlistName,
          musicFileNames: pending.members,
          createdAt: DateTime.now(),
        ),
      );
      selectedPlaylistId = playlistId;
      archiveReports.add(
        MusicImportArchiveReport(
          archiveFileName: pending.archiveFileName,
          playlistName: playlistName,
          memberCount: pending.members.length,
        ),
      );
    }

    if (imported > 0 || archiveReports.isNotEmpty) {
      final files = filesByName.values.toList()
        ..sort((a, b) => a.fileName.compareTo(b.fileName));
      progress(
        const MusicImportProgress(
          stage: MusicImportStage.saving,
          sourceLabel: '正在保存曲库索引',
        ),
      );
      try {
        await _replaceState(
          current.copyWith(
            files: files,
            playlists: playlists,
            currentPlaylistId: selectedPlaylistId,
          ),
        );
      } catch (_) {
        for (final path in createdPaths) {
          try {
            await fileStore.deleteFile(path);
          } catch (_) {}
        }
        for (final root in archiveStorageRoots) {
          try {
            await archiveImporter.discardStorage(root);
          } catch (_) {}
        }
        failures.add(
          const MusicImportFailure(
            fileName: '曲库索引',
            kind: MusicImportFailureKind.storageError,
            message: '保存曲库索引失败，已回滚本次导入',
          ),
        );
        imported = 0;
        overwritten = 0;
        renamed = 0;
        reused = 0;
        archiveReports.clear();
        try {
          await _saveState(current);
        } catch (_) {}
      }
      if (imported > 0 || archiveReports.isNotEmpty) {
        final retainedPaths = files.map((file) => file.path).toSet();
        for (final path in supersededPaths) {
          if (retainedPaths.contains(path)) {
            continue;
          }
          try {
            await fileStore.deleteFile(path);
          } catch (_) {}
        }
      }
    }
    progress(
      MusicImportProgress(
        stage: MusicImportStage.completed,
        sourceLabel: '导入完成',
        processedCount: processedSources,
        totalCount: pickedFiles.length,
        importedCount: imported,
        reusedCount: reused,
        skippedCount: skipped,
        failedCount: failures.length,
        ignoredCount: ignored,
      ),
    );
    return MusicImportReport(
      importedCount: imported,
      overwrittenCount: overwritten,
      renamedCount: renamed,
      reusedCount: reused,
      skippedCount: skipped,
      ignoredCount: ignored,
      stopped: stopped,
      failures: failures,
      archives: archiveReports,
    );
  }

  void _logMidiImport(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      '[MIDI_IMPORT] $message',
      name: 'lxmusic.import',
      error: error,
      stackTrace: stackTrace,
    );
  }

  String _parserFailureMessage(String format, Object error) {
    final detail = switch (error) {
      FormatException(:final message) => message,
      _ => '文件结构不符合要求',
    };
    return '$format 文件内容无效：$detail';
  }

  String _archivePlaylistBaseName(String archiveFileName) {
    final normalized = archiveFileName.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final base = name.toLowerCase().endsWith('.zip')
        ? name.substring(0, name.length - 4)
        : name;
    return base.trim().isEmpty ? 'ZIP 歌单' : base.trim();
  }

  String _nextPlaylistName(String baseName, Set<String> reservedNames) {
    if (!reservedNames.contains(baseName)) {
      return baseName;
    }
    var index = 2;
    var candidate = '$baseName ($index)';
    while (reservedNames.contains(candidate)) {
      index++;
      candidate = '$baseName ($index)';
    }
    return candidate;
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
    await _replaceState(
      current.copyWith(currentPlaylistId: playlistId),
      saveFiles: false,
      savePlaylists: false,
    );
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
    await _replaceState(next, saveFiles: false, saveSelection: false);
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
    await _replaceState(
      current.copyWith(playlists: playlists),
      saveFiles: false,
      saveSelection: false,
    );
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
      saveFiles: false,
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
    await _replaceState(
      current.copyWith(playlists: playlists),
      saveFiles: false,
      saveSelection: false,
    );
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
    await _replaceState(
      current.copyWith(playlists: playlists),
      saveFiles: false,
      saveSelection: false,
    );
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
  MusicLibraryState({
    required this.files,
    required this.playlists,
    required this.currentPlaylistId,
  }) : _index = _MusicLibraryIndex(files, playlists);

  factory MusicLibraryState.empty() => MusicLibraryState(
    files: const <MusicFile>[],
    playlists: const <LibraryPlaylist>[
      LibraryPlaylist(
        id: favoritesPlaylistId,
        name: '收藏',
        musicFileNames: <String>[],
        isBuiltinFavorite: true,
      ),
    ],
    currentPlaylistId: allSongsPlaylistId,
  );

  MusicLibraryState._({
    required this.files,
    required this.playlists,
    required this.currentPlaylistId,
    required _MusicLibraryIndex index,
  }) : _index = index;

  final List<MusicFile> files;
  final List<LibraryPlaylist> playlists;
  final String currentPlaylistId;
  final _MusicLibraryIndex _index;

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

  List<MusicFile> filesForPlaylist(String playlistId) =>
      _index.filesForPlaylist(playlistId);

  MusicLibraryState copyWith({
    List<MusicFile>? files,
    List<LibraryPlaylist>? playlists,
    String? currentPlaylistId,
  }) {
    final nextFiles = files ?? this.files;
    final nextPlaylists = playlists ?? this.playlists;
    return MusicLibraryState._(
      files: nextFiles,
      playlists: nextPlaylists,
      currentPlaylistId: currentPlaylistId ?? this.currentPlaylistId,
      index:
          identical(nextFiles, this.files) &&
              identical(nextPlaylists, this.playlists)
          ? _index
          : _MusicLibraryIndex(nextFiles, nextPlaylists),
    );
  }
}

class _MusicLibraryIndex {
  _MusicLibraryIndex(this.files, this.playlists);

  static const _maxCachedPlaylistViews = 8;

  final List<MusicFile> files;
  final List<LibraryPlaylist> playlists;
  final Map<String, List<MusicFile>> _playlistFiles =
      <String, List<MusicFile>>{};

  late final Set<String> _favoriteNames = playlists
      .where((playlist) => playlist.id == favoritesPlaylistId)
      .expand((playlist) => playlist.musicFileNames)
      .toSet();

  late final List<MusicFile> _sortedFiles = List<MusicFile>.unmodifiable(
    List<MusicFile>.of(files)..sort(_compareMusicFiles),
  );

  int _compareMusicFiles(MusicFile a, MusicFile b) {
    final favoriteOrder = (_favoriteNames.contains(b.fileName) ? 1 : 0)
        .compareTo(_favoriteNames.contains(a.fileName) ? 1 : 0);
    if (favoriteOrder != 0) return favoriteOrder;
    return a.normalizedFileName.compareTo(b.normalizedFileName);
  }

  List<MusicFile> filesForPlaylist(String playlistId) {
    if (playlistId == allSongsPlaylistId) return _sortedFiles;
    final cached = _playlistFiles.remove(playlistId);
    if (cached != null) {
      _playlistFiles[playlistId] = cached;
      return cached;
    }
    final playlist = playlists
        .where((playlist) => playlist.id == playlistId)
        .firstOrNull;
    final names = playlist?.musicFileNames.toSet();
    final result = names == null || names.isEmpty
        ? const <MusicFile>[]
        : List<MusicFile>.unmodifiable(
            _sortedFiles.where((file) => names.contains(file.fileName)),
          );
    if (_playlistFiles.length >= _maxCachedPlaylistViews) {
      _playlistFiles.remove(_playlistFiles.keys.first);
    }
    _playlistFiles[playlistId] = result;
    return result;
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
