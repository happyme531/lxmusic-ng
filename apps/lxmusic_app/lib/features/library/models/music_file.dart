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

/// Try to infer the parser format from a file extension.
String? inferFormat(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.mid') || lower.endsWith('.midi')) return 'midi';
  if (lower.endsWith('.dms.txt') || lower.endsWith('.dms')) return 'domiso';
  if (lower.endsWith('.skystudio.txt') ||
      lower.endsWith('.skystudio.json') ||
      lower.contains('skystudio')) {
    return 'skystudio-json';
  }
  if (lower.endsWith('.json')) {
    // Ambiguous — could be tonejs-json or json-score.
    // Default to tonejs-json as it's the most common JSON format.
    return 'tonejs-json';
  }
  return null;
}
