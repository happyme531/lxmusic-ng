import 'dart:io';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses domiso scale example', () {
    final parser = DoMiSoScoreParser();
    final bytes = File('../../examples/domiso/scale.dms.txt').readAsBytesSync();
    final score = parser.parse(bytes);

    expect(score.tracks, hasLength(1));
    expect(score.tracks.first.notes, hasLength(8));
    expect(score.tracks.first.notes.first.pitch, 60);
    expect(score.tracks.first.notes.last.pitch, 72);
    expect(score.tracks.first.notes[1].startMs, 500);
  });
}
