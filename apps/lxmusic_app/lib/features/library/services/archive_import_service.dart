import 'dart:typed_data';

import '../models/music_import.dart';

class ArchiveImportLimits {
  const ArchiveImportLimits({
    this.maxEntryCount = 50000,
    this.maxScoreBytes = 64 * 1024 * 1024,
    this.maxTotalScoreBytes = 8 * 1024 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
  });

  final int maxEntryCount;
  final int maxScoreBytes;
  final int maxTotalScoreBytes;
  final int maxCompressionRatio;

  String? validateArchive({
    required int entryCount,
    required int declaredScoreBytes,
  }) {
    if (entryCount < 0 || declaredScoreBytes < 0) {
      return 'ZIP 中央目录包含无效的长度信息';
    }
    if (entryCount > maxEntryCount) {
      return 'ZIP 条目数超过 $maxEntryCount 个安全上限';
    }
    if (declaredScoreBytes > maxTotalScoreBytes) {
      return 'ZIP 候选曲目总解压量超过 ${_byteLimitLabel(maxTotalScoreBytes)} 安全上限';
    }
    return null;
  }

  String? validateEntry({
    required int compressedBytes,
    required int uncompressedBytes,
  }) {
    if (compressedBytes < 0 || uncompressedBytes < 0) {
      return 'ZIP 条目包含无效的长度信息';
    }
    if (compressedBytes > maxScoreBytes) {
      return '单曲压缩数据超过 ${_byteLimitLabel(maxScoreBytes)} 安全上限';
    }
    if (uncompressedBytes > maxScoreBytes) {
      return '单曲解压后超过 ${_byteLimitLabel(maxScoreBytes)} 安全上限';
    }
    if (uncompressedBytes > 0 &&
        (compressedBytes == 0 ||
            uncompressedBytes > compressedBytes * maxCompressionRatio)) {
      return '单曲压缩比超过 $maxCompressionRatio 安全上限';
    }
    return null;
  }

  String _byteLimitLabel(int value) {
    if (value % (1024 * 1024 * 1024) == 0) {
      return '${value ~/ (1024 * 1024 * 1024)} GiB';
    }
    return '${value ~/ (1024 * 1024)} MiB';
  }
}

class PreparedImportedMusicFile {
  const PreparedImportedMusicFile({
    required this.path,
    required this.fileName,
    required this.formatId,
    required this.trackCount,
    required this.durationMs,
    required this.noteCount,
    required this.wasOverwrite,
    required this.wasRenamed,
  });

  final String path;
  final String fileName;
  final String formatId;
  final int trackCount;
  final int durationMs;
  final int noteCount;
  final bool wasOverwrite;
  final bool wasRenamed;
}

class ArchiveImportResult {
  const ArchiveImportResult({
    required this.archiveFileName,
    required this.files,
    required this.playlistFileNames,
    required this.failures,
    required this.storageRoot,
    required this.reusedCount,
    required this.skippedCount,
    required this.ignoredCount,
    required this.stopped,
  });

  final String archiveFileName;
  final List<PreparedImportedMusicFile> files;
  final List<String> playlistFileNames;
  final List<MusicImportFailure> failures;
  final String? storageRoot;
  final int reusedCount;
  final int skippedCount;
  final int ignoredCount;
  final bool stopped;
}

abstract class ArchiveImportService {
  const ArchiveImportService();

  bool get isSupported;

  Future<ArchiveImportResult> importArchive({
    required String archiveFileName,
    required String? sourcePath,
    required Uint8List? bytes,
    required Set<String> knownFileNames,
    required MusicImportConflictResolver resolveConflict,
    required MusicImportProgressCallback onProgress,
    required MusicImportCancellationToken cancellationToken,
  });

  Future<void> discardStorage(String? storageRoot);

  Future<void> cleanupUnreferencedStorage(Set<String> referencedPaths);
}
