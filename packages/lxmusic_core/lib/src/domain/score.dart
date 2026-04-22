enum SourceFormat { domiso, jsonScore }

class NoteEvent {
  const NoteEvent({
    required this.pitch,
    required this.startMs,
    this.durationMs,
    this.velocity = 100,
    this.attrs = const {},
  });

  final int pitch;
  final int startMs;
  final int? durationMs;
  final int velocity;
  final Map<String, Object?> attrs;

  NoteEvent copyWith({
    int? pitch,
    int? startMs,
    int? durationMs,
    int? velocity,
    Map<String, Object?>? attrs,
  }) {
    return NoteEvent(
      pitch: pitch ?? this.pitch,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      velocity: velocity ?? this.velocity,
      attrs: attrs ?? this.attrs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pitch': pitch,
      'startMs': startMs,
      'durationMs': durationMs,
      'velocity': velocity,
      'attrs': attrs,
    };
  }

  static NoteEvent fromJson(Map<String, Object?> json) {
    return NoteEvent(
      pitch: json['pitch'] as int,
      startMs: json['startMs'] as int,
      durationMs: json['durationMs'] as int?,
      velocity: (json['velocity'] as int?) ?? 100,
      attrs: Map<String, Object?>.from(
        json['attrs'] as Map? ?? const <String, Object?>{},
      ),
    );
  }
}

class Track {
  const Track({
    required this.name,
    required this.channel,
    required this.notes,
    this.instrumentId,
  });

  final String name;
  final int channel;
  final int? instrumentId;
  final List<NoteEvent> notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'channel': channel,
      'instrumentId': instrumentId,
      'notes': notes.map((note) => note.toJson()).toList(),
    };
  }

  static Track fromJson(Map<String, Object?> json) {
    return Track(
      name: json['name'] as String? ?? 'Track 1',
      channel: json['channel'] as int? ?? 0,
      instrumentId: json['instrumentId'] as int?,
      notes: (json['notes'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((note) => NoteEvent.fromJson(Map<String, Object?>.from(note)))
          .toList(),
    );
  }
}

class LyricEvent {
  const LyricEvent({required this.atMs, required this.text});

  final int atMs;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{'atMs': atMs, 'text': text};
  }
}

class Score {
  const Score({
    required this.tracks,
    required this.format,
    this.lyrics = const [],
    this.metadata = const {},
  });

  final List<Track> tracks;
  final List<LyricEvent> lyrics;
  final SourceFormat format;
  final Map<String, Object?> metadata;

  /// 所有音轨上的音符事件总数（用于转换前后对比）。
  int get totalNoteCount =>
      tracks.fold<int>(0, (sum, track) => sum + track.notes.length);

  int get totalDurationMs {
    var maxEndMs = 0;
    for (final track in tracks) {
      for (final note in track.notes) {
        final endMs = note.startMs + (note.durationMs ?? 0);
        if (endMs > maxEndMs) {
          maxEndMs = endMs;
        }
      }
    }
    return maxEndMs;
  }

  Score copyWith({
    List<Track>? tracks,
    List<LyricEvent>? lyrics,
    SourceFormat? format,
    Map<String, Object?>? metadata,
  }) {
    return Score(
      tracks: tracks ?? this.tracks,
      lyrics: lyrics ?? this.lyrics,
      format: format ?? this.format,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'format': format.name,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'lyrics': lyrics.map((lyric) => lyric.toJson()).toList(),
      'metadata': metadata,
      'totalDurationMs': totalDurationMs,
    };
  }

  static Score fromJson(Map<String, Object?> json) {
    final formatName = json['format'] as String? ?? SourceFormat.jsonScore.name;
    return Score(
      format: SourceFormat.values.byName(formatName),
      tracks: (json['tracks'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((track) => Track.fromJson(Map<String, Object?>.from(track)))
          .toList(),
      lyrics: (json['lyrics'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (lyric) => LyricEvent(
              atMs: lyric['atMs'] as int,
              text: lyric['text'] as String,
            ),
          )
          .toList(),
      metadata: Map<String, Object?>.from(
        json['metadata'] as Map? ?? const <String, Object?>{},
      ),
    );
  }
}
