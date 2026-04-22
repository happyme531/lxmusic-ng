import 'dart:convert';
import 'dart:typed_data';

import '../../domain/score.dart';
import '../../parsing/score_parser.dart';

class DoMiSoScoreParser implements ScoreParser {
  @override
  String get formatId => 'domiso';

  static const List<int> _scaleOffsets = <int>[0, 2, 4, 5, 7, 9, 11];

  @override
  Score parse(Uint8List bytes) {
    final raw = utf8.decode(bytes);
    final tokens = _tokenize(raw);
    var bpm = 80;
    var tickMs = _tickMsFromBpm(bpm);
    var basePitch = _noteNameToMidiPitch('C4');
    var currentMs = 0;
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
          notes.add(NoteEvent(pitch: pitch, startMs: currentMs));
        }
        currentMs += (chordLengthTicks * tickMs).round();
        inChord = false;
        continue;
      }

      if (token.contains('=')) {
        final parts = token.split('=');
        if (parts.length != 2) {
          throw FormatException('Invalid command token: $token');
        }
        if (parts[0] == 'bpm') {
          bpm = int.parse(parts[1]);
          tickMs = _tickMsFromBpm(bpm);
        } else if (parts[0] == '1') {
          basePitch = _noteNameToMidiPitch(parts[1]);
        } else {
          throw FormatException('Unsupported command: $token');
        }
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
          notes.add(NoteEvent(pitch: parsed.pitch, startMs: currentMs));
        }
        currentMs += (parsed.lengthTicks * tickMs).round();
      }
    }

    return Score(
      tracks: <Track>[Track(name: 'DoMiSo', channel: 0, notes: notes)],
      format: SourceFormat.domiso,
      metadata: <String, Object?>{'bpm': bpm},
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
    if (token.isEmpty) {
      return 1;
    }
    var length = 1.0;
    for (final rune in token.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '.') {
        length += length / 2;
      } else if (ch == '-') {
        length += 1;
      } else if (ch == '/') {
        length /= 2;
      } else {
        throw FormatException('Invalid timing token: $token');
      }
    }
    return length;
  }

  int _tickMsFromBpm(int bpm) {
    if (bpm <= 0 || bpm > 480) {
      return 750;
    }
    return (60000 / bpm).round();
  }

  int _noteNameToMidiPitch(String name) {
    final normalized = name.trim().toUpperCase();
    final match = RegExp(r'^([A-G])([0-9])([#]?)$').firstMatch(normalized);
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
    final letter = match.group(1)!;
    final octave = int.parse(match.group(2)!);
    final accidental = match.group(3)! == '#' ? 1 : 0;
    return pitchMap[letter]! + accidental + (octave + 1) * 12;
  }
}
