import 'dart:convert';
import 'dart:typed_data';

import '../../domain/score.dart';
import '../../parsing/music_text_decoder.dart';
import '../../parsing/score_parser.dart';

class DoMiSoScoreParser implements ScoreParser {
  @override
  String get formatId => 'domiso';

  static const int _defaultBpm = 80;
  static const List<int> _scaleOffsets = <int>[0, 2, 4, 5, 7, 9, 11];

  @override
  Score parse(Uint8List bytes) {
    final document = _splitDocument(decodeMusicText(bytes));
    final tokens = _tokenize(document.body);
    var bpm = _defaultBpm;
    var basePitch = _noteNameToMidiPitch('C');
    var currentMs = 0.0;
    var inChord = false;
    var chordPitches = <int>[];
    var chordLengthTicks = 0.0;
    final notes = <NoteEvent>[];

    for (final token in tokens) {
      if (token == '(') {
        inChord = true;
        chordPitches = <int>[];
        chordLengthTicks = 0.0;
        continue;
      }
      if (token == ')') {
        for (final pitch in chordPitches) {
          notes.add(NoteEvent(pitch: pitch, startMs: currentMs.round()));
        }
        currentMs += _ticksToMs(chordLengthTicks, bpm);
        chordPitches = <int>[];
        chordLengthTicks = 0;
        inChord = false;
        continue;
      }

      if (token.contains('=')) {
        final separatorIndex = token.indexOf('=');
        final command = token.substring(0, separatorIndex);
        final argument = token.substring(separatorIndex + 1);
        if (command.isEmpty) {
          throw FormatException('Invalid command token: $token');
        }
        switch (command) {
          case 'bpm':
            bpm = _normalizeBpm(int.parse(argument));
          case '1':
            basePitch = _noteNameToMidiPitch(argument);
          case 'rollback':
            // Kept as a compatibility no-op. The legacy parser only warned
            // because rollback was never implemented there either.
            break;
          default:
            throw FormatException('Unsupported command: $token');
        }
        continue;
      }

      // Legacy DoMiSo files may contain free-form text outside the optional
      // header. The old parser ignored tokens that did not look like notes.
      if (!RegExp(r'[0-7]').hasMatch(token)) {
        continue;
      }

      final parsed = _parseNote(token, basePitch);
      if (inChord) {
        if (parsed.pitch >= 0) {
          chordPitches.add(parsed.pitch);
        }
        if (parsed.lengthTicks > chordLengthTicks) {
          chordLengthTicks = parsed.lengthTicks;
        }
      } else {
        if (parsed.pitch >= 0) {
          notes.add(NoteEvent(pitch: parsed.pitch, startMs: currentMs.round()));
        }
        currentMs += _ticksToMs(parsed.lengthTicks, bpm);
      }
    }

    return Score(
      tracks: <Track>[Track(name: 'DoMiSo', channel: 0, notes: notes)],
      format: SourceFormat.domiso,
      metadata: <String, Object?>{
        'source': formatId,
        'bpm': bpm,
        if (document.comment.isNotEmpty) 'comment': document.comment,
      },
    );
  }

  ({String comment, String body}) _splitDocument(String raw) {
    final normalized = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    final lines = LineSplitter.split(normalized).toList();
    final separatorIndex = lines.indexWhere((line) => line.contains('=='));
    if (separatorIndex < 0) {
      return (comment: '', body: normalized);
    }
    return (
      comment: lines.take(separatorIndex).join('\n').trim(),
      body: lines.skip(separatorIndex + 1).join('\n'),
    );
  }

  List<String> _tokenize(String raw) {
    final result = <String>[];
    for (final line in LineSplitter.split(raw)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//')) {
        continue;
      }
      result.addAll(
        trimmed.split(RegExp(r'\s+')).where((token) => token.isNotEmpty),
      );
    }
    return result;
  }

  ({int pitch, double lengthTicks}) _parseNote(String token, int basePitch) {
    final match = RegExp(r'^([+-]*)([0-7])([#b]?)([./-]*)$').firstMatch(token);
    if (match == null) {
      throw FormatException('Invalid note token: $token');
    }

    final octaveShift = match.group(1)!;
    final degree = int.parse(match.group(2)!);
    final accidental = match.group(3)!;
    final timing = match.group(4)!;

    if (degree == 0) {
      return (pitch: -1, lengthTicks: _parseLengthTicks(timing));
    }

    var pitch = basePitch + _scaleOffsets[degree - 1];
    if (octaveShift.isNotEmpty) {
      final direction = octaveShift[0] == '+' ? 1 : -1;
      pitch += direction * octaveShift.length * 12;
    }
    if (accidental == '#') {
      pitch += 1;
    } else if (accidental == 'b') {
      pitch -= 1;
    }

    return (pitch: pitch, lengthTicks: _parseLengthTicks(timing));
  }

  double _parseLengthTicks(String token) {
    final segments = <double>[1];
    for (final rune in token.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '.') {
        segments.add(segments.last / 2);
      } else if (ch == '-') {
        segments.add(1);
      } else if (ch == '/') {
        segments[segments.length - 1] /= 2;
      } else {
        throw FormatException('Invalid timing token: $token');
      }
    }
    return segments.fold<double>(0, (sum, segment) => sum + segment);
  }

  int _normalizeBpm(int bpm) => bpm >= 1 && bpm <= 480 ? bpm : _defaultBpm;

  double _ticksToMs(double ticks, int bpm) => ticks * 60000 / bpm;

  int _noteNameToMidiPitch(String name) {
    final normalized = name.trim();
    final match = RegExp(
      r'^([A-Ga-g])(?:(\d)([#b]?)|([#b])(\d)?)?$',
    ).firstMatch(normalized);
    if (match == null) {
      throw FormatException('Invalid note name: $name');
    }
    const pitchMap = <String, int>{
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    final letter = match.group(1)!.toUpperCase();
    final octaveText = match.group(2) ?? match.group(5);
    final octave = octaveText == null ? 4 : int.parse(octaveText);
    final suffixAccidental = match.group(3) ?? '';
    final accidentalText = suffixAccidental.isNotEmpty
        ? suffixAccidental
        : (match.group(4) ?? '');
    final accidental = accidentalText == '#'
        ? 1
        : accidentalText == 'b'
        ? -1
        : 0;
    return pitchMap[letter]! + accidental + (octave + 1) * 12;
  }
}
