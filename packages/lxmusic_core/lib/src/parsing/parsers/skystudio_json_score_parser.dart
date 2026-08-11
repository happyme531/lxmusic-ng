import 'dart:convert';
import 'dart:typed_data';

import '../../domain/score.dart';
import '../music_text_decoder.dart';
import '../score_parser.dart';

class SkyStudioJsonScoreParser implements ScoreParser {
  const SkyStudioJsonScoreParser();

  @override
  String get formatId => 'skystudio-json';

  static const List<int> _skyKeyToMidi = <int>[
    48,
    50,
    52,
    53,
    55,
    57,
    59,
    60,
    62,
    64,
    65,
    67,
    69,
    71,
    72,
  ];

  @override
  Score parse(Uint8List bytes) {
    final raw = decodeMusicText(bytes);
    final decoded = jsonDecode(raw) as List<Object?>;
    if (decoded.isEmpty) {
      throw const FormatException('SkyStudio JSON is empty.');
    }

    final song = Map<String, Object?>.from(decoded.first! as Map);
    if ((song['isEncrypted'] as bool?) ?? false) {
      throw const FormatException('SkyStudio JSON is encrypted.');
    }

    final noteList = (song['songNotes'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<Object?, Object?>>();
    final notes = noteList.map(_parseNote).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    return Score(
      tracks: <Track>[
        Track(
          name: song['name'] as String? ?? 'SkyStudio',
          channel: 0,
          instrumentId: 0,
          notes: notes,
        ),
      ],
      format: SourceFormat.jsonScore,
      metadata: <String, Object?>{
        'source': formatId,
        'name': song['name'],
        'author': song['author'],
        'transcribedBy': song['transcribedBy'],
        'isComposed': song['isComposed'],
        'bpm': song['bpm'],
        'pitchLevel': song['pitchLevel'],
        'bitsPerPage': song['bitsPerPage'],
      },
    );
  }

  NoteEvent _parseNote(Map<Object?, Object?> json) {
    final note = Map<String, Object?>.from(json);
    final keyToken = note['key'] as String? ?? '';
    final keyIndex = _parseSkyKeyIndex(keyToken);
    if (keyIndex < 0 || keyIndex >= _skyKeyToMidi.length) {
      throw FormatException('Unsupported SkyStudio key index: $keyToken');
    }

    return NoteEvent(
      pitch: _skyKeyToMidi[keyIndex],
      startMs: (note['time'] as num?)?.round() ?? 0,
      attrs: <String, Object?>{'skyKey': keyToken},
    );
  }

  int _parseSkyKeyIndex(String keyToken) {
    final match = RegExp(
      r'key(\d+)$',
      caseSensitive: false,
    ).firstMatch(keyToken.trim());
    if (match == null) {
      throw FormatException('Invalid SkyStudio key: $keyToken');
    }
    return int.parse(match.group(1)!);
  }
}
