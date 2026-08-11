import 'dart:typed_data';

import '../models/music_import.dart';
import 'archive_import_service.dart';

ArchiveImportService createArchiveImportService() =>
    const UnsupportedArchiveImportService();

class UnsupportedArchiveImportService extends ArchiveImportService {
  const UnsupportedArchiveImportService();

  @override
  bool get isSupported => false;

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
  }) async {
    return ArchiveImportResult(
      archiveFileName: archiveFileName,
      files: const <PreparedImportedMusicFile>[],
      playlistFileNames: const <String>[],
      failures: <MusicImportFailure>[
        MusicImportFailure(
          fileName: archiveFileName,
          kind: MusicImportFailureKind.invalidArchive,
          message: '当前平台暂不支持 ZIP 导入',
        ),
      ],
      storageRoot: null,
      reusedCount: 0,
      skippedCount: 0,
      ignoredCount: 0,
      stopped: false,
    );
  }
}
