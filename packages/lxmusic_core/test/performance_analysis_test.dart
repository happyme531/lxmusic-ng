import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const profile = GameProfile(
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

  const layout = KeyLayout(
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

  test('infers a better pitch offset for out-of-range notes', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 48, startMs: 0),
            NoteEvent(pitch: 50, startMs: 100),
            NoteEvent(pitch: 52, startMs: 200),
          ],
        ),
      ],
    );

    final analysis = analyzeScoreForTarget(
      score,
      target: AnalysisTarget(
        profile: profile,
        variant: profile.variants.first,
        layout: layout,
      ),
    );

    expect(analysis.pitchOffset.bestOffset, 12);
    expect(analysis.pitchOffset.bestCandidate.outRangedWeight, 0);
    expect(analysis.toConfigJson()['pipeline'], isNotNull);
  });

  test('preserves legacy tie-breaking in pitch offset inference', () {
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
        profile: profile,
        variant: profile.variants.first,
        layout: layout,
      ),
    );

    expect(analysis.pitchOffset.bestOffset, 0);
    expect(analysis.pitchOffset.bestCandidate.underFlowedNoteCount, 1);
    expect(analysis.pitchOffset.bestCandidate.roundedNoteCount, 0);
  });

  test('builds a recommended pipeline that produces key ids', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      lyrics: <LyricEvent>[LyricEvent(atMs: 5, text: 'A')],
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
        ),
      ],
    );

    final analysis = analyzeScoreForTarget(
      score,
      target: AnalysisTarget(
        profile: profile,
        variant: profile.variants.first,
        layout: layout,
      ),
    );
    final result = analysis.buildRecommendedPipeline().run(score);

    expect(result.score.tracks.first.notes.first.attrs['keyId'], 'C4');
    expect(result.score.tracks.first.notes.first.attrs['lyric'], 'A');
    expect(
      result.report.stats.map((stat) => stat.name),
      containsAll(<String>[
        'LegalizeTargetNoteRangePass',
        'BindLyricsPass',
        'NoteToKeyPass',
      ]),
    );
  });

  test('recommended pipeline preserves legacy step order for lyrics', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
        ),
      ],
    );

    final analysis = analyzeScoreForTarget(
      score,
      target: AnalysisTarget(
        profile: profile,
        variant: profile.variants.first,
        layout: layout,
      ),
    );

    final steps = analysis.buildRecommendedPipeline().steps;
    expect(
      steps.map((step) => step.type).toList(),
      <String>[
        'mergeTracks',
        'legalizeTargetNoteRange',
        'storeCurrentNoteTime',
        'singleKeyFrequencyLimit',
        'bindLyrics',
        'noteToKey',
      ],
    );
    expect(
      steps.firstWhere((step) => step.type == 'bindLyrics').config,
      <String, Object?>{'useStoredOriginalTime': true},
    );
  });

  test('recommends playable tracks for multi-track scores', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 62, startMs: 100),
          ],
        ),
        Track(
          name: 'TooLow',
          channel: 1,
          notes: <NoteEvent>[
            NoteEvent(pitch: 54, startMs: 0),
            NoteEvent(pitch: 55, startMs: 100),
          ],
        ),
        Track(
          name: 'HalfPlayable',
          channel: 2,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0),
            NoteEvent(pitch: 54, startMs: 100),
          ],
        ),
      ],
    );

    final analysis = analyzeScoreForTarget(
      score,
      target: AnalysisTarget(
        profile: profile,
        variant: profile.variants.first,
        layout: layout,
      ),
    );

    expect(analysis.trackSelection, isNotNull);
    expect(analysis.trackSelection!.threshold, 0.5);
    expect(analysis.trackSelection!.recommendedTrackIndexes, <int>[0]);
    expect(
      analysis.trackSelection!.recommendations
          .map((entry) => (entry.trackIndex, entry.playableRatio, entry.recommended))
          .toList(),
      <(int, double, bool)>[
        (0, 1.0, true),
        (2, 0.5, false),
        (1, 0.0, false),
      ],
    );

    final config = analysis.toConfigJson();
    final steps = ((config['pipeline'] as Map<String, Object?>)['steps']
            as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final mergeTracks = steps.firstWhere((step) => step['type'] == 'mergeTracks');
    expect(
      Map<String, Object?>.from(mergeTracks['config']! as Map)['selectedTracks'],
      <int>[0],
    );
  });
}
