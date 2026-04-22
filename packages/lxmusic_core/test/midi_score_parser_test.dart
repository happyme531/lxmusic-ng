import 'dart:typed_data';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  group('MidiScoreParser', () {
    const parser = MidiScoreParser();

    test('parses a simple type-0 midi file', () {
      final score = parser.parse(_buildSimpleMidiFile());

      expect(score.tracks, hasLength(1));
      expect(score.tracks.single.name, 'New Instrument');
      expect(score.tracks.single.channel, 0);
      expect(score.tracks.single.instrumentId, 0);
      expect(score.tracks.single.notes, hasLength(2));
      expect(score.tracks.single.notes[0].pitch, 60);
      expect(score.tracks.single.notes[0].startMs, 0);
      expect(score.tracks.single.notes[0].durationMs, 500);
      expect(score.tracks.single.notes[1].pitch, 64);
      expect(score.tracks.single.notes[1].startMs, 500);
      expect(score.tracks.single.notes[1].durationMs, 500);
      expect(score.metadata['source'], 'midi');
      expect(score.metadata['ticksPerQuarter'], 480);
    });

    test('rejects invalid midi header', () {
      expect(
        () => parser.parse(Uint8List.fromList(<int>[0x00, 0x01, 0x02])),
        throwsFormatException,
      );
    });
  });
}

Uint8List _buildSimpleMidiFile() {
  final trackData = <int>[
    ..._vlq(0),
    0xff,
    0x03,
    0x0e,
    ...'New Instrument'.codeUnits,
    ..._vlq(0),
    0xff,
    0x51,
    0x03,
    0x07,
    0xa1,
    0x20,
    ..._vlq(0),
    0xc0,
    0x00,
    ..._vlq(0),
    0x90,
    0x3c,
    0x64,
    ..._vlq(480),
    0x80,
    0x3c,
    0x40,
    ..._vlq(0),
    0x90,
    0x40,
    0x64,
    ..._vlq(480),
    0x80,
    0x40,
    0x40,
    ..._vlq(0),
    0xff,
    0x2f,
    0x00,
  ];

  return Uint8List.fromList(<int>[
    ...'MThd'.codeUnits,
    0x00,
    0x00,
    0x00,
    0x06,
    0x00,
    0x00,
    0x00,
    0x01,
    0x01,
    0xe0,
    ...'MTrk'.codeUnits,
    0x00,
    0x00,
    0x00,
    trackData.length,
    ...trackData,
  ]);
}

List<int> _vlq(int value) {
  final buffer = <int>[value & 0x7f];
  value >>= 7;
  while (value > 0) {
    buffer.insert(0, 0x80 | (value & 0x7f));
    value >>= 7;
  }
  return buffer;
}
