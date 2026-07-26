import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  final parser = DoMiSoScoreParser();

  test('parses domiso scale example', () {
    final score = parser.parse(
      File('../../examples/domiso/scale.dms.txt').readAsBytesSync(),
    );

    expect(score.tracks, hasLength(1));
    expect(score.tracks.first.notes, hasLength(8));
    expect(score.tracks.first.notes.first.pitch, 60);
    expect(score.tracks.first.notes.last.pitch, 72);
    expect(score.tracks.first.notes[1].startMs, 500);
  });

  test('matches the legacy header and scale fixture', () {
    final score = parser.parse(
      File('test/fixtures/legacy_domiso.dms.txt').readAsBytesSync(),
    );
    final notes = score.tracks.single.notes;

    expect(score.metadata, <String, Object?>{
      'source': 'domiso',
      'bpm': 120,
      'comment': 'testtesttest hallo1',
    });
    expect(score.format, SourceFormat.domiso);
    expect(score.tracks.single.name, 'DoMiSo');
    expect(score.tracks.single.channel, 0);
    expect(notes, hasLength(21));
    expect(notes.map((note) => note.pitch).toList(), <int>[
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
      74,
      76,
      77,
      79,
      81,
      83,
    ]);
    expect(
      notes.map((note) => note.startMs).toList(),
      List<int>.generate(21, (index) => (index + 1) * 500),
    );
    expect(notes.every((note) => note.durationMs == null), isTrue);
    expect(notes.every((note) => note.velocity == 100), isTrue);
    expect(notes.every((note) => note.attrs.isEmpty), isTrue);
    expect(score.totalDurationMs, 10500);
  });

  test('matches legacy mixed note timing, rests and accidentals', () {
    final score = _parseText(parser, 'bpm=120\n1 5.. ++3b// -1#-/- 0/ 2');

    expect(
      score.tracks.single.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (67, 500), (87, 1375), (49, 1500), (62, 3000)],
    );
  });

  test('uses legacy timing segments for dots, dashes and slashes', () {
    final score = _parseText(parser, 'bpm=120\n1.. 1// 1-/- 2');

    expect(
      score.tracks.single.notes.map((note) => note.startMs).toList(),
      <int>[0, 875, 1000, 2250],
    );
  });

  test('accepts legacy shorthand and explicit key names', () {
    final score = _parseText(parser, '1=F#\n1\n1=F5#\n1\n1=C\n1');

    expect(score.tracks.single.notes.map((note) => note.pitch).toList(), <int>[
      66,
      78,
      60,
    ]);
  });

  test('keeps parser state isolated between parses', () {
    _parseText(parser, '1=F# bpm=120 1');
    final score = _parseText(parser, '1 2');

    expect(
      score.tracks.single.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (62, 750)],
    );
  });

  test('keeps rollback as a no-op and resets invalid bpm to 80', () {
    final score = _parseText(parser, 'bpm=999 rollback=250\n1 2');

    expect(score.metadata['bpm'], 80);
    expect(
      score.tracks.single.notes.map((note) => note.startMs).toList(),
      <int>[0, 750],
    );
  });

  test('accumulates non-integral beat lengths before rounding', () {
    final score = _parseText(parser, 'bpm=90\n1 2 3 4 5 6 7 +1');

    expect(
      score.tracks.single.notes.map((note) => note.startMs).toList(),
      <int>[0, 667, 1333, 2000, 2667, 3333, 4000, 4667],
    );
  });

  test('keeps exact time across tempo changes and chords', () {
    final score = _parseText(parser, 'bpm=120\n1. bpm=60 ( 2 3.. 5/ ) 6');

    expect(
      score.tracks.single.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (62, 750), (64, 750), (67, 750), (69, 2500)],
    );
  });

  test('clears chord state after a closing parenthesis', () {
    final score = _parseText(parser, 'bpm=120\n( 1 3 ) ) 2');

    expect(
      score.tracks.single.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (64, 0), (62, 500)],
    );
  });

  test('ignores standalone timing marks like the legacy parser', () {
    final score = _parseText(parser, 'bpm=60\n1 - / -/- . 2');

    expect(
      score.tracks.single.notes.map((note) => note.startMs).toList(),
      <int>[0, 1000],
    );
  });

  test('ignores arbitrary legacy header text before the separator', () {
    final score = _parseText(
      parser,
      'Song version 2, transcribed in 2026\nmore free-form text\n==\n1',
    );

    expect(score.metadata['comment'], contains('version 2'));
    expect(score.tracks.single.notes.single.pitch, 60);
  });

  test('accepts a UTF-8 BOM before the first command', () {
    final score = _parseText(parser, '\uFEFF1=C4\r\nbpm=120\r\n1\t2');

    expect(
      score.tracks.single.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (62, 500)],
    );
  });
}

Score _parseText(DoMiSoScoreParser parser, String source) {
  return parser.parse(Uint8List.fromList(utf8.encode(source)));
}
