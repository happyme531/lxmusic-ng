import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('orders recommended steps according to the legacy playback flow', () {
    final result = canonicalizeRecommendedTransformSteps(const <TransformStep>[
      TransformStep(type: 'noteToKey'),
      TransformStep(type: 'bindLyrics'),
      TransformStep(type: 'chordNoteCountLimit'),
      TransformStep(type: 'limitBlankDuration'),
      TransformStep(type: 'skipIntro'),
      TransformStep(type: 'singleKeyFrequencyLimit'),
      TransformStep(type: 'legalizeTargetNoteRange'),
      TransformStep(type: 'pitchOffset'),
      TransformStep(type: 'humanify'),
      TransformStep(type: 'mergeNearbyNotes'),
      TransformStep(type: 'speedChange'),
      TransformStep(type: 'storeCurrentNoteTime'),
      TransformStep(type: 'mergeTracks'),
      TransformStep(type: 'removeEmptyTracks'),
    ]);

    expect(result.map((step) => step.type).toList(), <String>[
      'removeEmptyTracks',
      'mergeTracks',
      'storeCurrentNoteTime',
      'speedChange',
      'mergeNearbyNotes',
      'humanify',
      'pitchOffset',
      'legalizeTargetNoteRange',
      'singleKeyFrequencyLimit',
      'skipIntro',
      'limitBlankDuration',
      'chordNoteCountLimit',
      'bindLyrics',
      'noteToKey',
    ]);
  });

  test('keeps unknown steps anchored and preserves step configs', () {
    const merge = TransformStep(
      type: 'mergeTracks',
      config: <String, Object?>{'futureOption': 'keep-me'},
    );
    const custom = TransformStep(
      type: 'customFutureStep',
      config: <String, Object?>{'enabled': true},
    );
    const noteToKey = TransformStep(type: 'noteToKey');

    final result = canonicalizeRecommendedTransformSteps(const <TransformStep>[
      noteToKey,
      custom,
      merge,
    ]);

    expect(result, <TransformStep>[merge, noteToKey, custom]);
    expect(result.first.config['futureOption'], 'keep-me');
    expect(result.last.config['enabled'], isTrue);
  });

  test('upsert preserves advanced config and canonicalizes the result', () {
    final result = upsertRecommendedTransformStep(
      const <TransformStep>[
        TransformStep(type: 'noteToKey'),
        TransformStep(
          type: 'humanify',
          config: <String, Object?>{
            'noteAbsTimeStdDev': 5,
            'randomSeed': 123,
            'futureOption': true,
          },
        ),
        TransformStep(type: 'mergeTracks'),
      ],
      const TransformStep(
        type: 'humanify',
        config: <String, Object?>{'noteAbsTimeStdDev': 20},
      ),
    );

    expect(result.map((step) => step.type), <String>[
      'mergeTracks',
      'humanify',
      'noteToKey',
    ]);
    expect(result[1].config, <String, Object?>{
      'noteAbsTimeStdDev': 20,
      'randomSeed': 123,
      'futureOption': true,
    });
  });

  test('canonicalization is idempotent', () {
    final once = canonicalizeRecommendedTransformSteps(const <TransformStep>[
      TransformStep(type: 'noteToKey'),
      TransformStep(type: 'speedChange'),
      TransformStep(type: 'mergeTracks'),
    ]);
    final twice = canonicalizeRecommendedTransformSteps(once);

    expect(twice.map((step) => step.type), <String>[
      'mergeTracks',
      'speedChange',
      'noteToKey',
    ]);
    for (var index = 0; index < once.length; index++) {
      expect(twice[index], same(once[index]));
    }
  });
}
