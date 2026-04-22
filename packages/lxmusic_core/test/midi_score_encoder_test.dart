import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('encodes score to midi and can be parsed back', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          instrumentId: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0, durationMs: 500, velocity: 100),
            NoteEvent(pitch: 64, startMs: 500, durationMs: 250, velocity: 90),
          ],
        ),
      ],
    );

    final bytes = const MidiScoreEncoder().encode(score);
    final parsed = const MidiScoreParser().parse(bytes);

    expect(parsed.tracks, hasLength(1));
    expect(parsed.tracks.single.name, 'Lead');
    expect(parsed.tracks.single.channel, 0);
    expect(parsed.tracks.single.instrumentId, 0);
    expect(parsed.tracks.single.notes, hasLength(2));
    expect(parsed.tracks.single.notes[0].pitch, 60);
    expect(parsed.tracks.single.notes[0].startMs, 0);
    expect(parsed.tracks.single.notes[0].durationMs, 500);
    expect(parsed.tracks.single.notes[1].pitch, 64);
    expect(parsed.tracks.single.notes[1].startMs, 500);
    expect(parsed.tracks.single.notes[1].durationMs, 250);
  });
}
