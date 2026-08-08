import 'dart:math' as math;

const muscriptorEosToken = 1;
const muscriptorInitialToken = 1395;
const muscriptorFirstReservedToken = 1393;

class MuscriptorDecodedNote {
  const MuscriptorDecodedNote({
    required this.program,
    required this.pitch,
    required this.onsetSeconds,
    required this.offsetSeconds,
    this.isDrum = false,
  });

  final int program;
  final int pitch;
  final double onsetSeconds;
  final double offsetSeconds;
  final bool isDrum;

  MuscriptorDecodedNote copyWith({double? offsetSeconds}) {
    return MuscriptorDecodedNote(
      program: program,
      pitch: pitch,
      onsetSeconds: onsetSeconds,
      offsetSeconds: offsetSeconds ?? this.offsetSeconds,
      isDrum: isDrum,
    );
  }
}

typedef _NoteKey = ({int program, int pitch});

/// Stateful decoder for MuScriptor's MT3-like token vocabulary.
///
/// A single instance must be reused across all five-second chunks so tie
/// prologues can keep sustained notes open across chunk boundaries.
class MuscriptorTokenDecoder {
  static const _frameRate = 100;
  static const _minimumNoteDuration = 0.01;

  final Map<_NoteKey, double> _openNotes = <_NoteKey, double>{};
  final List<MuscriptorDecodedNote> _notes = <MuscriptorDecodedNote>[];
  final Set<_NoteKey> _tieSet = <_NoteKey>{};

  double _seekTime = 0;
  double? _nextSeekTime;
  int _startTick = 0;
  int _tick = 0;
  int? _program;
  int? _velocity;
  bool _inPrologue = true;
  bool _skipRest = false;
  bool _chunkStarted = false;
  bool _finished = false;

  List<MuscriptorDecodedNote> get notes => List.unmodifiable(_notes);

  /// Encodes the currently sounding notes as the same teacher-forced tie
  /// prelude used by MuScriptor's PyTorch `prelude_forcing` path.
  ///
  /// Call this after [beginChunk], which first settles a malformed previous
  /// chunk. An empty open-note set still produces the tie terminator.
  List<int> get forcedTiePreludeTokens {
    final keys = _openNotes.keys.toList(growable: false)
      ..sort((a, b) {
        final program = a.program.compareTo(b.program);
        return program != 0 ? program : a.pitch.compareTo(b.pitch);
      });
    final tokens = <int>[];
    int? programState;
    for (final key in keys) {
      if (key.program != programState) {
        tokens.add(_programTokenBase + key.program);
        programState = key.program;
      }
      tokens.add(_pitchTokenBase + key.pitch);
    }
    tokens.add(muscriptorTieToken);
    return tokens;
  }

  void beginChunk({required double seekTime, double? nextSeekTime}) {
    if (_finished) {
      throw StateError('Token decoder has already been finished');
    }
    if (_chunkStarted && _inPrologue) {
      _endAll(_seekTime);
    }
    _seekTime = seekTime;
    _nextSeekTime = nextSeekTime;
    _startTick = (seekTime * _frameRate).round();
    _tick = _startTick;
    _program = null;
    _velocity = null;
    _inPrologue = true;
    _skipRest = false;
    _tieSet.clear();
    _chunkStarted = true;
  }

  void feed(int token) {
    if (!_chunkStarted) {
      throw StateError('beginChunk must be called before feeding tokens');
    }
    final event = _decodeToken(token);
    if (event == null) return;

    if (_inPrologue) {
      switch (event.type) {
        case _TokenType.tie:
          _inPrologue = false;
          _velocity = null;
          final ended = _openNotes.keys
              .where((key) => !_tieSet.contains(key))
              .toList(growable: false);
          for (final key in ended) {
            _endNote(key, _seekTime);
          }
        case _TokenType.shift:
          _inPrologue = false;
          _skipRest = true;
          _endAll(_seekTime);
        case _TokenType.program:
          _program = event.value;
        case _TokenType.pitch:
          final program = _program;
          if (program != null) {
            _tieSet.add((program: program, pitch: event.value));
          }
        case _TokenType.special || _TokenType.velocity || _TokenType.drum:
          break;
      }
      return;
    }

    if (_skipRest) return;
    switch (event.type) {
      case _TokenType.shift:
        if (event.value > 0) {
          _tick = _startTick + event.value;
        }
      case _TokenType.program:
        _program = event.value;
      case _TokenType.velocity:
        _velocity = event.value;
      case _TokenType.drum:
        final time = _tick / _frameRate;
        if (_nextSeekTime == null || time < _nextSeekTime!) {
          _notes.add(
            MuscriptorDecodedNote(
              program: 128,
              pitch: event.value,
              onsetSeconds: time,
              offsetSeconds: time + _minimumNoteDuration,
              isDrum: true,
            ),
          );
        }
      case _TokenType.pitch:
        final program = _program;
        final velocity = _velocity;
        if (program == null || velocity == null) return;
        final time = _tick / _frameRate;
        if (_nextSeekTime != null && time >= _nextSeekTime!) return;
        final key = (program: program, pitch: event.value);
        if (_openNotes.containsKey(key)) {
          _endNote(key, time);
        }
        if (velocity > 0) {
          _openNotes[key] = time;
        }
      case _TokenType.tie || _TokenType.special:
        break;
    }
  }

  List<MuscriptorDecodedNote> finish() {
    if (_finished) return notes;
    _finished = true;
    if (_chunkStarted && _inPrologue) {
      _endAll(_seekTime);
    } else {
      final open = Map<_NoteKey, double>.of(_openNotes);
      _openNotes.clear();
      for (final entry in open.entries) {
        _notes.add(
          MuscriptorDecodedNote(
            program: entry.key.program,
            pitch: entry.key.pitch,
            onsetSeconds: entry.value,
            offsetSeconds: entry.value + _minimumNoteDuration,
          ),
        );
      }
    }
    _notes.sort((a, b) {
      final onset = a.onsetSeconds.compareTo(b.onsetSeconds);
      if (onset != 0) return onset;
      final program = a.program.compareTo(b.program);
      if (program != 0) return program;
      return a.pitch.compareTo(b.pitch);
    });
    return notes;
  }

  void _endAll(double time) {
    final keys = _openNotes.keys.toList(growable: false);
    for (final key in keys) {
      _endNote(key, time);
    }
  }

  void _endNote(_NoteKey key, double time) {
    final onset = _openNotes.remove(key);
    if (onset == null) return;
    _notes.add(
      MuscriptorDecodedNote(
        program: key.program,
        pitch: key.pitch,
        onsetSeconds: onset,
        offsetSeconds: math.max(time, onset + _minimumNoteDuration),
      ),
    );
  }
}

enum _TokenType { special, shift, pitch, velocity, tie, program, drum }

const _pitchTokenBase = 1004;
const _programTokenBase = 1135;
const muscriptorTieToken = 1134;

class _TokenEvent {
  const _TokenEvent(this.type, this.value);

  final _TokenType type;
  final int value;
}

_TokenEvent? _decodeToken(int token) {
  if (token < 0 || token >= muscriptorFirstReservedToken) return null;
  if (token <= 2) return _TokenEvent(_TokenType.special, token);
  if (token <= 1003) return _TokenEvent(_TokenType.shift, token - 3);
  if (token <= 1131) {
    return _TokenEvent(_TokenType.pitch, token - _pitchTokenBase);
  }
  if (token <= 1133) return _TokenEvent(_TokenType.velocity, token - 1132);
  if (token == muscriptorTieToken) {
    return const _TokenEvent(_TokenType.tie, 0);
  }
  if (token <= 1264) {
    return _TokenEvent(_TokenType.program, token - _programTokenBase);
  }
  return _TokenEvent(_TokenType.drum, token - 1265);
}
