import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  group('MergeTracksPass', () {
    test('merges tracks', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 48, startMs: 0, durationMs: 500),
              NoteEvent(pitch: 50, startMs: 100, durationMs: 500),
            ],
          ),
          Track(
            name: 'B',
            channel: 1,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 50, durationMs: 500),
            ],
          ),
        ],
      );

      final result = const MergeTracksPass(
        MergeTracksOptions(),
      ).run(score).score;
      expect(result.tracks, hasLength(1));
      expect(
        result.tracks.first.notes.map((note) => note.pitch).toList(),
        <int>[48, 60, 50],
      );
    });

    test('skips percussion channel', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Perc',
            channel: 9,
            notes: <NoteEvent>[
              NoteEvent(pitch: 48, startMs: 0, durationMs: 500),
            ],
          ),
          Track(
            name: 'Lead',
            channel: 1,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 50, durationMs: 500),
            ],
          ),
        ],
      );

      final result = const MergeTracksPass(
        MergeTracksOptions(skipPercussion: true),
      ).run(score).score;

      expect(
        result.tracks.first.notes.map((note) => note.pitch).toList(),
        <int>[60],
      );
    });
  });

  group('RemoveEmptyTracksPass', () {
    test('removes empty tracks', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 48, startMs: 0, durationMs: 500),
            ],
          ),
          Track(name: 'B', channel: 1, notes: <NoteEvent>[]),
          Track(
            name: 'C',
            channel: 2,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 50, durationMs: 500),
            ],
          ),
        ],
      );

      final result = const RemoveEmptyTracksPass().run(score).score;
      expect(result.tracks, hasLength(2));
      expect(result.tracks.map((track) => track.name).toList(), <String>[
        'A',
        'C',
      ]);
    });
  });

  group('PitchOffsetPass', () {
    test('offsets pitch', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 48, startMs: 0, durationMs: 500),
              NoteEvent(pitch: 60, startMs: 50, durationMs: 500),
            ],
          ),
        ],
      );

      final result = const PitchOffsetPass(
        PitchOffsetOptions(offset: 2),
      ).run(score).score;

      expect(
        result.tracks.first.notes.map((note) => note.pitch).toList(),
        <int>[50, 62],
      );
    });
  });

  group('LegalizeTargetNoteRangePass', () {
    test('wraps and rounds unsupported notes into playable range', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 59, startMs: 0),
              NoteEvent(pitch: 61, startMs: 100),
              NoteEvent(pitch: 74, startMs: 200),
              NoteEvent(pitch: 84, startMs: 300),
            ],
          ),
        ],
      );

      final result = const LegalizeTargetNoteRangePass(
        LegalizeTargetNoteRangeOptions(
          supportedPitches: <int>[60, 62, 64, 65, 67, 69, 71, 72],
          semiToneRoundingMode: SemiToneRoundingMode.floor,
          wrapHigherOctave: 1,
          wrapLowerOctave: 1,
        ),
      ).run(score);

      expect(
        result.score.tracks.first.notes.map((note) => note.pitch).toList(),
        <int>[71, 60, 62, 72],
      );
      expect(result.report.stats.single.values['roundedNoteCount'], 1);
      expect(result.report.stats.single.values['wrappedHigherNoteCount'], 2);
      expect(result.report.stats.single.values['wrappedLowerNoteCount'], 1);
    });

    test('duplicates semitones in both mode and drops impossible notes', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 61, startMs: 0),
              NoteEvent(pitch: 63, startMs: 100),
            ],
          ),
        ],
      );

      final result = const LegalizeTargetNoteRangePass(
        LegalizeTargetNoteRangeOptions(
          supportedPitches: <int>[60, 62, 64],
          semiToneRoundingMode: SemiToneRoundingMode.both,
        ),
      ).run(score);

      expect(
        result.score.tracks.first.notes.map((note) => note.pitch).toList(),
        <int>[60, 62, 62, 64],
      );
      expect(result.report.stats.single.values['roundedNoteCount'], 2);
    });

    test('alternating mode does not fall back to the other side', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
        ],
      );

      final result = const LegalizeTargetNoteRangePass(
        LegalizeTargetNoteRangeOptions(
          supportedPitches: <int>[60, 62, 65],
          semiToneRoundingMode: SemiToneRoundingMode.alternating,
        ),
      ).run(score);

      expect(result.score.tracks.first.notes, isEmpty);
      expect(result.report.stats.single.values['roundedNoteCount'], 0);
    });
  });

  group('NoteToKeyPass', () {
    test('annotates notes with key ids', () {
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

      final result = const NoteToKeyPass(
        NoteToKeyOptions(pitchToKeyId: <int, String>{60: 'C4', 64: 'E4'}),
      ).run(score);

      expect(result.score.tracks.first.notes.first.attrs['keyId'], 'C4');
      expect(result.score.tracks.first.notes.last.attrs['keyId'], 'E4');
      expect(result.report.stats.single.values['mappedNoteCount'], 2);
    });
  });

  group('BindLyricsPass', () {
    test('binds lyrics to nearest chord start and merges same target', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        lyrics: <LyricEvent>[
          LyricEvent(atMs: 10, text: 'A'),
          LyricEvent(atMs: 12, text: 'B'),
          LyricEvent(atMs: 210, text: 'C'),
        ],
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 64, startMs: 0),
              NoteEvent(pitch: 67, startMs: 200),
            ],
          ),
        ],
      );

      final result = const BindLyricsPass(BindLyricsOptions()).run(score);
      final notes = result.score.tracks.first.notes;

      expect(notes[0].attrs['lyric'], 'A\nB');
      expect(notes[1].attrs['lyric'], isNull);
      expect(notes[2].attrs['lyric'], 'C');
      expect(result.report.stats.single.values['totalErrorMs'], 32);
    });
  });

  group('StoreCurrentNoteTimePass', () {
    test('stores originalTime in note attrs', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 123)],
          ),
        ],
      );

      final result = const StoreCurrentNoteTimePass().run(score);
      expect(result.score.tracks.first.notes.first.attrs['originalTime'], 123);
    });
  });

  group('MergeNearbyNotesPass', () {
    test('merges nearby notes correctly', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 62, startMs: 50),
              NoteEvent(pitch: 64, startMs: 75),
              NoteEvent(pitch: 65, startMs: 125),
              NoteEvent(pitch: 67, startMs: 200),
              NoteEvent(pitch: 60, startMs: 210),
            ],
          ),
        ],
      );

      final result = const MergeNearbyNotesPass(
        MergeNearbyNotesOptions(maxIntervalMs: 100),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[
          (60, 0),
          (62, 0),
          (64, 0),
          (65, 125),
          (67, 125),
          (60, 125),
        ],
      );
    });

    test('drops same notes inside the same batch', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 50),
              NoteEvent(pitch: 64, startMs: 150),
              NoteEvent(pitch: 67, startMs: 175),
              NoteEvent(pitch: 64, startMs: 200),
            ],
          ),
        ],
      );

      final result = const MergeNearbyNotesPass(
        MergeNearbyNotesOptions(maxIntervalMs: 100),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(60, 0), (64, 150), (67, 150)],
      );
    });
  });

  group('FoldFrequentSameNotePass', () {
    test('folds frequent same notes', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 90),
              NoteEvent(pitch: 60, startMs: 180),
            ],
          ),
        ],
      );

      final result = const FoldFrequentSameNotePass(
        FoldFrequentSameNoteOptions(),
      ).run(score).score;

      expect(result.tracks.first.notes, hasLength(1));
      expect(result.tracks.first.notes.first.durationMs, 180);
    });
  });

  group('EstimateNoteDurationPass', () {
    test('estimates note duration', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 100),
              NoteEvent(pitch: 60, startMs: 200),
              NoteEvent(pitch: 60, startMs: 300),
              NoteEvent(pitch: 60, startMs: 400),
              NoteEvent(pitch: 60, startMs: 500),
            ],
          ),
        ],
      );

      final result = const EstimateNoteDurationPass(
        EstimateNoteDurationOptions(),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .take(5)
            .map((note) => note.durationMs)
            .toList(),
        <int>[75, 75, 75, 75, 75],
      );
      expect(result.tracks.first.notes.last.durationMs, isNull);
    });
  });

  group('SplitLongNotePass', () {
    test('splits long notes', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 60,
                startMs: 0,
                durationMs: 600,
                attrs: <String, Object?>{'duration': 600},
              ),
            ],
          ),
        ],
      );

      final result = const SplitLongNotePass(
        SplitLongNoteOptions(),
      ).run(score).score;

      expect(result.tracks.first.notes, hasLength(6));
      expect(result.tracks.first.notes[1].startMs, 100);
      expect(result.tracks.first.notes.last.durationMs, 100);
    });
  });

  group('SpeedChangePass', () {
    test('changes speed for time and duration', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 60,
                startMs: 200,
                durationMs: 100,
                attrs: <String, Object?>{'duration': 100},
              ),
            ],
          ),
        ],
      );

      final result = const SpeedChangePass(
        SpeedChangeOptions(speed: 2),
      ).run(score).score;

      expect(result.tracks.first.notes.first.startMs, 100);
      expect(result.tracks.first.notes.first.durationMs, 50);
    });
  });

  group('LimitBlankDurationPass', () {
    test('limits long blanks', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 61, startMs: 10000),
            ],
          ),
        ],
      );

      final result = const LimitBlankDurationPass(
        LimitBlankDurationOptions(maxBlankDurationMs: 5000),
      ).run(score).score;

      expect(result.tracks.first.notes.last.startMs, 5000);
    });
  });

  group('SkipIntroPass', () {
    test('skips overly long intro', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 5000),
              NoteEvent(pitch: 62, startMs: 5200),
            ],
          ),
        ],
      );

      final result = const SkipIntroPass(
        SkipIntroOptions(maxIntroMs: 2000),
      ).run(score).score;

      expect(result.tracks.first.notes.first.startMs, 2000);
      expect(result.tracks.first.notes.last.startMs, 2200);
    });
  });

  group('SingleKeyFrequencyLimitPass', () {
    test('drops notes that repeat too quickly', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 50),
              NoteEvent(pitch: 60, startMs: 150),
              NoteEvent(pitch: 61, startMs: 170),
            ],
          ),
        ],
      );

      final result = const SingleKeyFrequencyLimitPass(
        SingleKeyFrequencyLimitOptions(minIntervalMs: 100),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(60, 0), (60, 150), (61, 170)],
      );
    });
  });

  group('NoteFrequencySoftLimitPass', () {
    test('delays close chords instead of dropping them', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 64, startMs: 0),
              NoteEvent(pitch: 67, startMs: 30),
              NoteEvent(pitch: 71, startMs: 30),
              NoteEvent(pitch: 72, startMs: 120),
            ],
          ),
        ],
      );

      final result = const NoteFrequencySoftLimitPass(
        NoteFrequencySoftLimitOptions(minIntervalMs: 100),
      ).run(score);

      expect(
        result.score.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(60, 0), (64, 0), (67, 100), (71, 100), (72, 224)],
      );
      expect(result.report.stats.single.values['delayedChordCount'], 2);
      expect(result.report.stats.single.values['delayedNoteCount'], 3);
    });
  });

  group('ChordNoteCountLimitPass', () {
    test('limits chord size and keeps higher pitches by default', () {
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
              NoteEvent(pitch: 72, startMs: 100),
            ],
          ),
        ],
      );

      final result = const ChordNoteCountLimitPass(
        ChordNoteCountLimitOptions(maxNoteCount: 2),
      ).run(score);

      expect(
        result.score.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(67, 0), (71, 0), (72, 100)],
      );
      expect(result.report.stats.single.values['limitedChordCount'], 1);
      expect(result.report.stats.single.values['droppedNoteCount'], 2);
    });

    test('supports keeping lower pitches in delete mode', () {
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

      final result = const ChordNoteCountLimitPass(
        ChordNoteCountLimitOptions(
          maxNoteCount: 2,
          keepHigherPitches: false,
          selectMode: 'low',
        ),
      ).run(score);

      expect(
        result.score.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(60, 0), (64, 0)],
      );
      expect(result.report.stats.single.values['droppedNoteCount'], 2);
      expect(result.report.stats.single.values['selectMode'], 'low');
    });

    test('supports split mode with delayed overflow notes', () {
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

      final result = const ChordNoteCountLimitPass(
        ChordNoteCountLimitOptions(
          maxNoteCount: 2,
          limitMode: 'split',
          splitDelayMs: 75,
          selectMode: 'high',
        ),
      ).run(score);

      expect(
        result.score.tracks.first.notes
            .map((note) => (note.pitch, note.startMs))
            .toList(),
        <(int, int)>[(67, 0), (71, 0), (64, 75), (60, 150)],
      );
      expect(result.report.stats.single.values['droppedNoteCount'], 0);
      expect(result.report.stats.single.values['splitNoteCount'], 2);
      expect(result.report.stats.single.values['limitMode'], 'split');
    });
  });

  group('HumanifyPass', () {
    test('adds timing jitter and keeps times non-negative and sorted', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'A',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 62, startMs: 100),
              NoteEvent(pitch: 64, startMs: 200),
            ],
          ),
        ],
      );

      final result = const HumanifyPass(
        HumanifyOptions(noteAbsTimeStdDev: 30, randomSeed: 42),
      ).run(score);
      final starts = result.score.tracks.first.notes
          .map((note) => note.startMs)
          .toList();

      expect(starts, orderedEquals(starts.toList()..sort()));
      expect(starts.first, greaterThanOrEqualTo(0));
      expect(result.report.stats.single.name, 'HumanifyPass');
    });
  });
}
