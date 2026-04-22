import 'dart:convert';
import 'dart:typed_data';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  group('SkyStudioJsonScoreParser', () {
    const parser = SkyStudioJsonScoreParser();

    test('parses utf8 SkyStudio json', () {
      final score = parser.parse(
        Uint8List.fromList(utf8.encode(_sampleSkyStudioJson)),
      );

      expect(score.tracks, hasLength(1));
      expect(score.tracks.single.name, 'testtest');
      expect(score.tracks.single.notes.map((note) => note.pitch), <int>[
        48,
        50,
        52,
        53,
      ]);
      expect(score.tracks.single.notes.map((note) => note.startMs), <int>[
        0,
        250,
        500,
        750,
      ]);
      expect(score.metadata['source'], parser.formatId);
      expect(score.metadata['bpm'], 240);
    });

    test('parses utf16le SkyStudio json', () {
      final bytes = _encodeUtf16Le(_sampleSkyStudioJson);
      final score = parser.parse(bytes);

      expect(score.tracks.single.notes.first.pitch, 48);
      expect(score.tracks.single.notes.last.pitch, 53);
    });

    test('rejects encrypted files', () {
      expect(
        () => parser.parse(
          Uint8List.fromList(
            utf8.encode('[{"name":"x","isEncrypted":true,"songNotes":[]}]'),
          ),
        ),
        throwsFormatException,
      );
    });
  });
}

const String _sampleSkyStudioJson = '''
[
  {
    "name": "testtest",
    "author": "hallo1",
    "transcribedBy": "Unknown",
    "isComposed": true,
    "bpm": 240,
    "bitsPerPage": 16,
    "pitchLevel": 0,
    "isEncrypted": false,
    "songNotes": [
      {"time": 0, "key": "1Key0"},
      {"time": 250, "key": "1Key1"},
      {"time": 500, "key": "1Key2"},
      {"time": 750, "key": "1Key3"}
    ]
  }
]
''';

Uint8List _encodeUtf16Le(String input) {
  final units = <int>[0xff, 0xfe];
  for (final codeUnit in input.codeUnits) {
    units.add(codeUnit & 0xff);
    units.add((codeUnit >> 8) & 0xff);
  }
  return Uint8List.fromList(units);
}
