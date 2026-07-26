import 'transform_pipeline.dart';

/// Canonical order for pipelines generated or edited by the recommended
/// configuration flow.
///
/// Custom CLI pipelines remain free to use an explicit order. This policy is
/// intentionally opt-in and mirrors the legacy playback flow where an
/// equivalent transform exists.
const List<String> recommendedTransformStepOrder = <String>[
  'removeEmptyTracks',
  'mergeTracks',
  'storeCurrentNoteTime',
  'speedChange',
  'mergeNearbyNotes',
  'humanify',
  'pitchOffset',
  'legalizeTargetNoteRange',
  'estimateNoteDuration',
  'foldFrequentSameNote',
  'splitLongNote',
  'singleKeyFrequencyLimit',
  'skipIntro',
  'limitBlankDuration',
  'noteFrequencySoftLimit',
  'chordNoteCountLimit',
  'bindLyrics',
  'noteToKey',
];

/// Orders known recommended-flow steps without dropping configuration data.
///
/// Unknown steps stay attached to the nearest preceding known step and retain
/// their relative order. This keeps a persisted future/custom step intact
/// while still making every known step's relative order deterministic.
List<TransformStep> canonicalizeRecommendedTransformSteps(
  Iterable<TransformStep> steps,
) {
  final source = steps.toList();
  final orderByType = <String, int>{
    for (var index = 0; index < recommendedTransformStepOrder.length; index++)
      recommendedTransformStepOrder[index]: index,
  };
  final known =
      <
        ({
          int sourceIndex,
          TransformStep step,
          List<TransformStep> trailingUnknown,
        })
      >[];
  final leadingUnknown = <TransformStep>[];
  ({int sourceIndex, TransformStep step, List<TransformStep> trailingUnknown})?
  currentKnown;
  for (var index = 0; index < source.length; index++) {
    final step = source[index];
    if (orderByType.containsKey(step.type)) {
      currentKnown = (
        sourceIndex: index,
        step: step,
        trailingUnknown: <TransformStep>[],
      );
      known.add(currentKnown);
    } else if (currentKnown == null) {
      leadingUnknown.add(step);
    } else {
      currentKnown.trailingUnknown.add(step);
    }
  }
  known.sort((a, b) {
    final typeOrder = orderByType[a.step.type]!.compareTo(
      orderByType[b.step.type]!,
    );
    return typeOrder != 0 ? typeOrder : a.sourceIndex.compareTo(b.sourceIndex);
  });

  return <TransformStep>[
    ...leadingUnknown,
    for (final entry in known) ...<TransformStep>[
      entry.step,
      ...entry.trailingUnknown,
    ],
  ];
}

/// Inserts or updates one recommended-flow step and then canonicalizes it.
///
/// Existing config is merged by default so a simple UI control cannot erase
/// advanced or future fields it does not understand.
List<TransformStep> upsertRecommendedTransformStep(
  Iterable<TransformStep> steps,
  TransformStep step, {
  bool mergeConfig = true,
}) {
  final result = steps.toList();
  final index = result.indexWhere((candidate) => candidate.type == step.type);
  if (index < 0) {
    result.add(step);
  } else {
    final existing = result[index];
    result[index] = TransformStep(
      type: step.type,
      config: mergeConfig
          ? <String, Object?>{...existing.config, ...step.config}
          : step.config,
    );
  }
  return canonicalizeRecommendedTransformSteps(result);
}

/// Removes all recommended-flow steps whose type is in [types].
List<TransformStep> removeRecommendedTransformSteps(
  Iterable<TransformStep> steps,
  Iterable<String> types,
) {
  final removedTypes = types.toSet();
  return canonicalizeRecommendedTransformSteps(
    steps.where((step) => !removedTypes.contains(step.type)),
  );
}
