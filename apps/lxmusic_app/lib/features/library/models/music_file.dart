/// Metadata record for a music file imported into the library.
class MusicFile {
  MusicFile({
    required this.path,
    required this.fileName,
    required this.formatId,
    this.trackCount = 0,
    this.durationMs = 0,
    this.noteCount = 0,
    this.isFavorite = false,
    this.importedAt,
  });

  final String path;
  final String fileName;
  final String formatId;
  final int trackCount;
  final int durationMs;
  final int noteCount;
  bool isFavorite;
  final DateTime? importedAt;

  /// Cached once because filtering and sorting may inspect this value many
  /// times for large libraries.
  late final String normalizedFileName = fileName.toLowerCase();

  String get durationLabel {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'fileName': fileName,
    'formatId': formatId,
    'trackCount': trackCount,
    'durationMs': durationMs,
    'noteCount': noteCount,
    'isFavorite': isFavorite,
    'importedAt': importedAt?.toIso8601String(),
  };

  factory MusicFile.fromJson(Map<String, Object?> json) {
    return MusicFile(
      path: json['path'] as String,
      fileName: json['fileName'] as String,
      formatId: json['formatId'] as String,
      trackCount: json['trackCount'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      noteCount: json['noteCount'] as int? ?? 0,
      isFavorite: json['isFavorite'] as bool? ?? false,
      importedAt: json['importedAt'] != null
          ? DateTime.tryParse(json['importedAt'] as String)
          : null,
    );
  }
}
