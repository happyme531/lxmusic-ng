import 'dart:io';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses tonejs json example', () {
    final parser = ToneJsJsonScoreParser();
    final bytes = File(
      '../../examples/tonejs_json/simple_tone.json',
    ).readAsBytesSync();
    final score = parser.parse(bytes);

    expect(score.tracks, hasLength(1));
    expect(score.tracks.first.notes, hasLength(3));
    expect(score.tracks.first.notes.first.pitch, 60);
    expect(score.tracks.first.notes.first.durationMs, 250);
    expect(score.tracks.first.notes.last.startMs, 500);
  });
}
