enum MusicImportFailureKind {
  unreadableFile,
  formatDetectionFailed,
  invalidFormat,
  emptyScore,
  storageError,
  invalidArchive,
  unsafeArchive,
  encryptedArchive,
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

enum MusicImportConflictAction { overwrite, skip, rename, stop }

class MusicImportConflict {
  const MusicImportConflict({
    required this.fileName,
    required this.sourceLabel,
    required this.fromArchive,
  });

  final String fileName;
  final String sourceLabel;
  final bool fromArchive;
}

class MusicImportConflictDecision {
  const MusicImportConflictDecision({
    required this.action,
    this.applyToRemaining = false,
  });

  final MusicImportConflictAction action;
  final bool applyToRemaining;
}

enum MusicImportStage { scanning, importing, saving, completed }

class MusicImportProgress {
  const MusicImportProgress({
    required this.stage,
    required this.sourceLabel,
    this.currentFileName,
    this.processedCount = 0,
    this.totalCount = 0,
    this.importedCount = 0,
    this.reusedCount = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
    this.ignoredCount = 0,
  });

  final MusicImportStage stage;
  final String sourceLabel;
  final String? currentFileName;
  final int processedCount;
  final int totalCount;
  final int importedCount;
  final int reusedCount;
  final int skippedCount;
  final int failedCount;
  final int ignoredCount;

  double? get fraction => totalCount <= 0
      ? null
      : (processedCount / totalCount).clamp(0, 1).toDouble();
}

class MusicImportArchiveReport {
  const MusicImportArchiveReport({
    required this.archiveFileName,
    required this.playlistName,
    required this.memberCount,
  });

  final String archiveFileName;
  final String playlistName;
  final int memberCount;
}

class MusicImportReport {
  const MusicImportReport({
    required this.importedCount,
    required this.failures,
    this.overwrittenCount = 0,
    this.renamedCount = 0,
    this.reusedCount = 0,
    this.skippedCount = 0,
    this.ignoredCount = 0,
    this.stopped = false,
    this.archives = const <MusicImportArchiveReport>[],
  });

  final int importedCount;
  final int overwrittenCount;
  final int renamedCount;
  final int reusedCount;
  final int skippedCount;
  final int ignoredCount;
  final bool stopped;
  final List<MusicImportFailure> failures;
  final List<MusicImportArchiveReport> archives;
}

class MusicImportCancellationToken {
  bool _isStopped = false;
  void Function()? _onStop;

  bool get isStopped => _isStopped;

  void stop() {
    if (_isStopped) {
      return;
    }
    _isStopped = true;
    _onStop?.call();
  }

  void bind(void Function() callback) {
    _onStop = callback;
    if (_isStopped) {
      callback();
    }
  }

  void unbind() {
    _onStop = null;
  }
}

typedef MusicImportConflictResolver =
    Future<MusicImportConflictDecision> Function(MusicImportConflict conflict);

typedef MusicImportProgressCallback = void Function(MusicImportProgress value);

String nextAvailableMusicFileName(String fileName, Set<String> reservedNames) {
  final suffix = _recognizedMusicSuffix(fileName);
  final base = fileName.substring(0, fileName.length - suffix.length);
  var index = 2;
  var candidate = '$base ($index)$suffix';
  while (reservedNames.contains(candidate)) {
    index++;
    candidate = '$base ($index)$suffix';
  }
  return candidate;
}

String _recognizedMusicSuffix(String fileName) {
  final lower = fileName.toLowerCase();
  const suffixes = <String>[
    '.skystudio.json',
    '.skystudio.txt',
    '.score.json',
    '.dms.txt',
    '.midi',
    '.json',
    '.dms',
    '.mid',
    '.txt',
  ];
  for (final suffix in suffixes) {
    if (lower.endsWith(suffix)) {
      return fileName.substring(fileName.length - suffix.length);
    }
  }
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot);
}
