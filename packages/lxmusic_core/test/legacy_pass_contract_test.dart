import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const analysisProfile = GameProfile(
    id: 'demo',
    displayName: 'Demo',
    packageNameHints: <String>[],
    defaultLayoutId: 'layout',
    layouts: <LayoutBinding>[
      LayoutBinding(layoutId: 'layout', isDefault: true),
    ],
    variants: <InstrumentVariant>[
      InstrumentVariant(
        id: 'default',
        displayName: '默认',
        noteDurationMode: NoteDurationMode.none,
      ),
    ],
    sameKeyMinIntervalMs: 20,
  );

  const analysisLayout = KeyLayout(
    id: 'layout',
    algorithm: LayoutAlgorithm.explicit,
    keys: <KeyDefinition>[
      KeyDefinition(id: 'C4', pitch: 60, normX: 0.1, normY: 0.8),
      KeyDefinition(id: 'D4', pitch: 62, normX: 0.2, normY: 0.8),
      KeyDefinition(id: 'E4', pitch: 64, normX: 0.3, normY: 0.8),
      KeyDefinition(id: 'F4', pitch: 65, normX: 0.4, normY: 0.8),
    ],
    pitchToKeyId: <int, String>{60: 'C4', 62: 'D4', 64: 'E4', 65: 'F4'},
  );

  group('Legacy pass contracts', () {
    test('MergeNearbyNotesPass does not merge notes beyond maxInterval', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 62, startMs: 101),
              NoteEvent(pitch: 64, startMs: 202),
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
        <(int, int)>[(60, 0), (62, 101), (64, 202)],
      );
    });

    test('FoldFrequentSameNotePass folds interleaved notes by pitch', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 61, startMs: 70),
              NoteEvent(pitch: 60, startMs: 100),
              NoteEvent(pitch: 62, startMs: 110),
              NoteEvent(pitch: 61, startMs: 140),
              NoteEvent(pitch: 60, startMs: 200),
            ],
          ),
        ],
      );

      final result = const FoldFrequentSameNotePass(
        FoldFrequentSameNoteOptions(),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .map((note) => (note.pitch, note.startMs, note.durationMs))
            .toList(),
        <(int, int, int?)>[(60, 0, 200), (61, 70, 70), (62, 110, null)],
      );
      expect(result.tracks.first.notes[0].attrs['duration'], 200);
      expect(result.tracks.first.notes[1].attrs['duration'], 70);
    });

    test('EstimateNoteDurationPass keeps existing durations intact', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 100),
              NoteEvent(pitch: 61, startMs: 100),
              NoteEvent(
                pitch: 60,
                startMs: 300,
                durationMs: 100,
                attrs: <String, Object?>{'duration': 100},
              ),
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
        result.tracks.first.notes.map((note) => note.durationMs).toList(),
        <int?>[75, 150, 150, 100, 75, null],
      );
      expect(
        result.tracks.first.notes
            .map((note) => note.attrs['duration'])
            .toList(),
        <Object?>[75, 150, 150, 100, 75, null],
      );
    });

    test('SplitLongNotePass keeps interleaved short notes in time order', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 60,
                startMs: 0,
                durationMs: 600,
                attrs: <String, Object?>{'duration': 600},
              ),
              NoteEvent(
                pitch: 61,
                startMs: 180,
                durationMs: 300,
                attrs: <String, Object?>{'duration': 300},
              ),
            ],
          ),
        ],
      );

      final result = const SplitLongNotePass(
        SplitLongNoteOptions(),
      ).run(score).score;

      expect(
        result.tracks.first.notes
            .map((note) => (note.pitch, note.startMs, note.durationMs))
            .toList(),
        <(int, int, int?)>[
          (60, 0, 100),
          (60, 100, 100),
          (61, 180, 300),
          (60, 200, 100),
          (60, 300, 100),
          (60, 400, 100),
          (60, 500, 100),
        ],
      );
    });

    test('LimitBlankDurationPass preserves gaps after a compressed blank', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 62, startMs: 10000),
              NoteEvent(pitch: 64, startMs: 10100),
            ],
          ),
        ],
      );

      final result = const LimitBlankDurationPass(
        LimitBlankDurationOptions(maxBlankDurationMs: 5000),
      ).run(score);

      expect(
        result.score.tracks.first.notes.map((note) => note.startMs).toList(),
        <int>[0, 5000, 5100],
      );
    });

    test(
      'NoteFrequencySoftLimitPass uses soft saturation instead of hard clamp',
      () {
        const score = Score(
          format: SourceFormat.jsonScore,
          tracks: <Track>[
            Track(
              name: 'Lead',
              channel: 0,
              notes: <NoteEvent>[
                NoteEvent(pitch: 60, startMs: 0),
                NoteEvent(pitch: 62, startMs: 80),
                NoteEvent(pitch: 64, startMs: 160),
              ],
            ),
          ],
        );

        final result = const NoteFrequencySoftLimitPass(
          NoteFrequencySoftLimitOptions(minIntervalMs: 100),
        ).run(score);

        expect(
          result.score.tracks.first.notes.map((note) => note.startMs).toList(),
          <int>[0, 118, 236],
        );
        expect(result.report.stats.single.values['delayedChordCount'], 2);
        expect(result.report.stats.single.values['totalDelayMs'], 114);
        expect(result.report.stats.single.values['maxDelayMs'], 76);
      },
    );

    test('ChordNoteCountLimitPass supports legacy split mode semantics', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
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
      expect(result.report.stats.single.values['splitNoteCount'], 2);
      expect(result.report.stats.single.values['droppedNoteCount'], 0);
    });

    test('pitch offset inference preserves legacy tie-breaking', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 54, startMs: 0)],
          ),
        ],
      );

      final analysis = analyzeScoreForTarget(
        score,
        target: AnalysisTarget(
          profile: analysisProfile,
          variant: analysisProfile.variants.first,
          layout: analysisLayout,
        ),
      );

      expect(analysis.pitchOffset.bestOffset, 0);
      expect(analysis.pitchOffset.bestCandidate.underFlowedNoteCount, 1);
    });
  });
}
