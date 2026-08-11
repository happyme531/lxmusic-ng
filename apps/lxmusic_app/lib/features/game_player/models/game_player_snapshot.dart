import 'package:path/path.dart' as p;

enum GamePlayerDurationMode { shortPress, repeatedTap, longPress }

class GamePlayerTrack {
  const GamePlayerTrack({
    required this.fileName,
    required this.path,
    required this.formatId,
    required this.durationMs,
  });

  final String fileName;
  final String path;
  final String formatId;
  final int durationMs;

  String get displayName {
    final name = p.basenameWithoutExtension(fileName).trim();
    return name.isEmpty ? fileName : name;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'fileName': fileName,
    'path': path,
    'formatId': formatId,
    'durationMs': durationMs,
  };

  factory GamePlayerTrack.fromMap(Map<Object?, Object?> map) {
    return GamePlayerTrack(
      fileName: map['fileName'] as String? ?? '',
      path: map['path'] as String? ?? '',
      formatId: map['formatId'] as String? ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class GamePlayerPlaylistSnapshot {
  const GamePlayerPlaylistSnapshot({
    required this.id,
    required this.name,
    required this.fileNames,
  });

  final String id;
  final String name;
  final List<String> fileNames;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'fileNames': fileNames,
  };

  factory GamePlayerPlaylistSnapshot.fromMap(Map<Object?, Object?> map) {
    return GamePlayerPlaylistSnapshot(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      fileNames: (map['fileNames'] as List? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class GamePlayerSnapshot {
  const GamePlayerSnapshot({
    required this.tracks,
    required this.playlists,
    required this.queuePlaylistId,
    required this.queueFileNames,
    required this.favoriteFileNames,
    required this.historyFileNames,
    required this.currentFileName,
    required this.positionMs,
    required this.isPlaying,
    required this.speed,
    required this.playbackModeIndex,
    this.profileLabel,
    this.playbackDurationMs,
    this.playbackStatus = 'idle',
    this.playbackError,
    this.revision = 0,
    this.transpose = 0,
    this.timingOffsetMs = 0,
    this.touchDurationPercent = 100,
    this.durationMode = GamePlayerDurationMode.shortPress,
  });

  const GamePlayerSnapshot.empty()
    : tracks = const <GamePlayerTrack>[],
      playlists = const <GamePlayerPlaylistSnapshot>[],
      queuePlaylistId = 'all',
      queueFileNames = const <String>[],
      favoriteFileNames = const <String>[],
      historyFileNames = const <String>[],
      currentFileName = null,
      positionMs = 0,
      isPlaying = false,
      speed = 1,
      playbackModeIndex = 1,
      profileLabel = null,
      playbackDurationMs = null,
      playbackStatus = 'idle',
      playbackError = null,
      revision = 0,
      transpose = 0,
      timingOffsetMs = 0,
      touchDurationPercent = 100,
      durationMode = GamePlayerDurationMode.shortPress;

  final List<GamePlayerTrack> tracks;
  final List<GamePlayerPlaylistSnapshot> playlists;
  final String queuePlaylistId;
  final List<String> queueFileNames;
  final List<String> favoriteFileNames;
  final List<String> historyFileNames;
  final String? currentFileName;
  final int positionMs;
  final bool isPlaying;
  final double speed;
  final int playbackModeIndex;
  final String? profileLabel;
  final int? playbackDurationMs;
  final String playbackStatus;
  final String? playbackError;
  final int revision;
  final int transpose;
  final int timingOffsetMs;
  final int touchDurationPercent;
  final GamePlayerDurationMode durationMode;

  GamePlayerTrack? get currentTrack => trackByFileName(currentFileName);

  int get durationMs => playbackDurationMs ?? currentTrack?.durationMs ?? 0;

  GamePlayerTrack? trackByFileName(String? fileName) {
    if (fileName == null) return null;
    for (final track in tracks) {
      if (track.fileName == fileName) return track;
    }
    return null;
  }

  GamePlayerPlaylistSnapshot? get queuePlaylist {
    for (final playlist in playlists) {
      if (playlist.id == queuePlaylistId) return playlist;
    }
    return null;
  }

  Map<String, Object?> toMap() {
    final track = currentTrack;
    return <String, Object?>{
      'version': 1,
      'tracks': tracks.map((item) => item.toMap()).toList(growable: false),
      'playlists': playlists
          .map((item) => item.toMap())
          .toList(growable: false),
      'queuePlaylistId': queuePlaylistId,
      'queueFileNames': queueFileNames,
      'favoriteFileNames': favoriteFileNames,
      'historyFileNames': historyFileNames,
      'currentFileName': currentFileName,
      'title': track?.displayName ?? '暂无曲目',
      'durationMs': durationMs > 0 ? durationMs : 1,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'speed': speed,
      'playbackModeIndex': playbackModeIndex,
      'playbackStatus': playbackStatus,
      'revision': revision,
      'transpose': transpose,
      'timingOffsetMs': timingOffsetMs,
      'touchDurationPercent': touchDurationPercent,
      'durationMode': durationMode.name,
      if (profileLabel != null) 'profileLabel': profileLabel,
      if (playbackDurationMs != null) 'playbackDurationMs': playbackDurationMs,
      if (playbackError != null) 'playbackError': playbackError,
    };
  }

  factory GamePlayerSnapshot.fromMap(Map<String, Object?> map) {
    List<T> decodeList<T>(
      Object? value,
      T Function(Map<Object?, Object?>) decode,
    ) {
      return (value as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => decode(Map<Object?, Object?>.from(item)))
          .toList(growable: false);
    }

    return GamePlayerSnapshot(
      tracks: decodeList(map['tracks'], GamePlayerTrack.fromMap),
      playlists: decodeList(
        map['playlists'],
        GamePlayerPlaylistSnapshot.fromMap,
      ),
      queuePlaylistId: map['queuePlaylistId'] as String? ?? 'all',
      queueFileNames: (map['queueFileNames'] as List? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      favoriteFileNames:
          (map['favoriteFileNames'] as List? ?? const <Object?>[])
              .whereType<String>()
              .toList(growable: false),
      historyFileNames: (map['historyFileNames'] as List? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      currentFileName: map['currentFileName'] as String?,
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      isPlaying: map['isPlaying'] == true,
      speed: ((map['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 2),
      playbackModeIndex: ((map['playbackModeIndex'] as num?)?.toInt() ?? 1) % 4,
      profileLabel: map['profileLabel'] as String?,
      playbackDurationMs:
          (map['playbackDurationMs'] as num?)?.toInt() ??
          (map['durationMs'] as num?)?.toInt(),
      playbackStatus:
          map['playbackStatus'] as String? ??
          (map['isPlaying'] == true ? 'playing' : 'idle'),
      playbackError: map['playbackError'] as String?,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      transpose: ((map['transpose'] as num?)?.toInt() ?? 0).clamp(-24, 24),
      timingOffsetMs: ((map['timingOffsetMs'] as num?)?.toInt() ?? 0).clamp(
        -200,
        200,
      ),
      touchDurationPercent:
          ((map['touchDurationPercent'] as num?)?.toInt() ?? 100).clamp(
            40,
            120,
          ),
      durationMode: GamePlayerDurationMode.values.firstWhere(
        (mode) => mode.name == map['durationMode'],
        orElse: () => GamePlayerDurationMode.shortPress,
      ),
    );
  }

  GamePlayerSnapshot copyWith({
    List<GamePlayerTrack>? tracks,
    List<GamePlayerPlaylistSnapshot>? playlists,
    String? queuePlaylistId,
    List<String>? queueFileNames,
    List<String>? favoriteFileNames,
    List<String>? historyFileNames,
    String? currentFileName,
    int? positionMs,
    bool? isPlaying,
    double? speed,
    int? playbackModeIndex,
    String? profileLabel,
    int? playbackDurationMs,
    String? playbackStatus,
    String? playbackError,
    int? revision,
    int? transpose,
    int? timingOffsetMs,
    int? touchDurationPercent,
    GamePlayerDurationMode? durationMode,
  }) {
    return GamePlayerSnapshot(
      tracks: tracks ?? this.tracks,
      playlists: playlists ?? this.playlists,
      queuePlaylistId: queuePlaylistId ?? this.queuePlaylistId,
      queueFileNames: queueFileNames ?? this.queueFileNames,
      favoriteFileNames: favoriteFileNames ?? this.favoriteFileNames,
      historyFileNames: historyFileNames ?? this.historyFileNames,
      currentFileName: currentFileName ?? this.currentFileName,
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      playbackModeIndex: playbackModeIndex ?? this.playbackModeIndex,
      profileLabel: profileLabel ?? this.profileLabel,
      playbackDurationMs: playbackDurationMs ?? this.playbackDurationMs,
      playbackStatus: playbackStatus ?? this.playbackStatus,
      playbackError: playbackError ?? this.playbackError,
      revision: revision ?? this.revision,
      transpose: transpose ?? this.transpose,
      timingOffsetMs: timingOffsetMs ?? this.timingOffsetMs,
      touchDurationPercent: touchDurationPercent ?? this.touchDurationPercent,
      durationMode: durationMode ?? this.durationMode,
    );
  }
}
