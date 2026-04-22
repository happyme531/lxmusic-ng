import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('runs multiple transform steps in order', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 60, startMs: 100),
            NoteEvent(pitch: 64, startMs: 100),
            NoteEvent(pitch: 60, startMs: 200),
          ],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'estimateNoteDuration',
        config: <String, Object?>{'multiplier': 0.75},
      ),
      TransformStep(
        type: 'mergeNearbyNotes',
        config: <String, Object?>{'maxIntervalMs': 100},
      ),
    ]);

    final result = pipeline.run(score);
    expect(result.report.stats, hasLength(2));
    expect(result.score.tracks.first.notes[0].durationMs, 75);
    expect(result.score.tracks.first.notes[1].startMs, 100);
    expect(result.score.tracks.first.notes[2].startMs, 100);
  });

  test('runs legalizeTargetNoteRange from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 61, startMs: 0)],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'legalizeTargetNoteRange',
        config: <String, Object?>{
          'supportedPitches': <int>[60, 62, 64],
          'semiToneRoundingMode': 'both',
        },
      ),
    ]);

    final result = pipeline.run(score);
    expect(
      result.score.tracks.first.notes.map((note) => note.pitch).toList(),
      <int>[60, 62],
    );
    expect(result.report.stats.single.name, 'LegalizeTargetNoteRangePass');
    final summary = result.report.noteSummary!;
    expect(summary.inputNoteCount, 1);
    expect(summary.outputNoteCount, 2);
    expect(summary.pipelineNotesAdded, 1);
    expect(summary.pipelineNotesRemoved, 0);
  });

  test('runs noteToKey from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'noteToKey',
        config: <String, Object?>{
          'pitchToKeyId': <String, String>{'60': 'C4'},
        },
      ),
    ]);

    final result = pipeline.run(score);
    expect(result.score.tracks.first.notes.first.attrs['keyId'], 'C4');
    expect(result.report.stats.single.name, 'NoteToKeyPass');
  });

  test('runs bindLyrics from pipeline config using score lyrics', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      lyrics: <LyricEvent>[LyricEvent(atMs: 10, text: 'Hello')],
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(type: 'bindLyrics'),
    ]);

    final result = pipeline.run(score);
    expect(result.score.tracks.first.notes.first.attrs['lyric'], 'Hello');
    expect(result.report.stats.single.name, 'BindLyricsPass');
  });

  test('runs bindLyrics with stored original time from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      lyrics: <LyricEvent>[LyricEvent(atMs: 10, text: 'Hello')],
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(
              pitch: 60,
              startMs: 100,
              attrs: <String, Object?>{'originalTime': 0},
            ),
            NoteEvent(
              pitch: 62,
              startMs: 0,
              attrs: <String, Object?>{'originalTime': 100},
            ),
          ],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'bindLyrics',
        config: <String, Object?>{'useStoredOriginalTime': true},
      ),
    ]);

    final result = pipeline.run(score);
    expect(result.score.tracks.first.notes.first.attrs['lyric'], 'Hello');
    expect(result.score.tracks.first.notes.last.attrs['lyric'], isNull);
  });

  test('runs storeCurrentNoteTime from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 42)],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(type: 'storeCurrentNoteTime'),
    ]);

    final result = pipeline.run(score);
    expect(result.score.tracks.first.notes.first.attrs['originalTime'], 42);
    expect(result.report.stats.single.name, 'StoreCurrentNoteTimePass');
  });

  test('runs soft frequency and chord count limits from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 64, startMs: 0),
            NoteEvent(pitch: 67, startMs: 20),
            NoteEvent(pitch: 69, startMs: 20),
            NoteEvent(pitch: 71, startMs: 20),
          ],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'noteFrequencySoftLimit',
        config: <String, Object?>{'minIntervalMs': 100},
      ),
      TransformStep(
        type: 'chordNoteCountLimit',
        config: <String, Object?>{'maxNoteCount': 2, 'keepHigherPitches': true},
      ),
    ]);

    final result = pipeline.run(score);

    expect(
      result.score.tracks.first.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(60, 0), (64, 0), (69, 100), (71, 100)],
    );
    expect(result.report.stats.map((stat) => stat.name).toList(), <String>[
      'NoteFrequencySoftLimitPass',
      'ChordNoteCountLimitPass',
    ]);
  });

  test('runs chord split mode from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 64, startMs: 0),
            NoteEvent(pitch: 67, startMs: 0),
            NoteEvent(pitch: 71, startMs: 0),
          ],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'chordNoteCountLimit',
        config: <String, Object?>{
          'maxNoteCount': 2,
          'limitMode': 'split',
          'splitDelay': 75,
          'selectMode': 'high',
        },
      ),
    ]);

    final result = pipeline.run(score);

    expect(
      result.score.tracks.first.notes
          .map((note) => (note.pitch, note.startMs))
          .toList(),
      <(int, int)>[(67, 0), (71, 0), (64, 75), (60, 150)],
    );
    expect(result.report.stats.single.values['splitNoteCount'], 2);
  });

  test('runs humanify from pipeline config', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'A',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 64, startMs: 100),
          ],
        ),
      ],
    );

    const pipeline = TransformPipeline(<TransformStep>[
      TransformStep(
        type: 'humanify',
        config: <String, Object?>{'noteAbsTimeStdDev': 20, 'randomSeed': 7},
      ),
    ]);

    final result = pipeline.run(score);

    expect(result.report.stats.single.name, 'HumanifyPass');
    expect(result.score.tracks.first.notes, hasLength(2));
  });
}
