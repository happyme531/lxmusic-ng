import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../workbench/providers/workbench_provider.dart';
import '../../workbench/services/song_config_service.dart';
import '../models/preview_models.dart';

const _previewPointThresholdMs = 80;
const _previewFallbackPointDurationMs = 80;

final previewSessionProvider = FutureProvider<PreviewSessionData?>((ref) async {
  final file = ref.watch(selectedFileProvider);
  final profile = ref.watch(selectedProfileProvider);
  final variant = ref.watch(selectedVariantProvider);
  final layout = ref.watch(selectedLayoutProvider);
  final config = await ref.watch(songConfigProvider.future);

  if (file == null ||
      profile == null ||
      variant == null ||
      layout == null ||
      config == null) {
    return null;
  }

  final songConfigService = ref.watch(songConfigServiceProvider);
  final rawScore = await songConfigService.parseFile(file);
  final transformed = TransformPipeline(config.steps).run(rawScore);
  final customPitchToKeyId = resolveCustomPitchToKeyId(config.steps);
  final semanticPlan = const PerformancePlanner().plan(
    transformed.score,
    PlanningContext(
      profile: profile,
      layout: layout,
      variant: variant,
      customPitchToKeyId: customPitchToKeyId,
    ),
  );

  return PreviewSessionData(
    file: file,
    profile: profile,
    variant: variant,
    layout: layout,
    config: config,
    rawScore: rawScore,
    transformedScore: transformed.score,
    semanticPlan: semanticPlan,
  );
});

final previewGeometryProvider =
    Provider.family<PreviewLayoutGeometry, KeyLayout>((ref, layout) {
      return PreviewLayoutGeometry.fromLayout(layout);
    });

final previewLaneNotesProvider =
    Provider.family<List<PreviewLaneNote>, PreviewSessionData>((ref, session) {
      return buildPreviewLaneNotes(
        score: session.transformedScore,
        semanticPlan: session.semanticPlan,
        variant: session.variant,
        layout: session.layout,
        customPitchToKeyId: resolveCustomPitchToKeyId(session.config.steps),
      );
    });

@visibleForTesting
List<PreviewLaneNote> buildPreviewLaneNotes({
  required Score score,
  required SemanticPlan semanticPlan,
  required InstrumentVariant variant,
  required KeyLayout layout,
  Map<int, String>? customPitchToKeyId,
}) {
  final playablePitchToKeyId = variant.playablePitchToKeyId(layout);
  final nominalPitchByKeyId = <String, int>{};
  final orderedLayoutPitches = layout.pitchToKeyId.keys.toList()..sort();
  for (final pitch in orderedLayoutPitches) {
    nominalPitchByKeyId.putIfAbsent(layout.pitchToKeyId[pitch]!, () => pitch);
  }
  for (final key in layout.keys) {
    if (key.pitch != null) {
      nominalPitchByKeyId[key.id] = key.pitch!;
    }
  }
  final playableKeyIds = playablePitchToKeyId.values.toSet();
  final candidatesByAction =
      <({int startMs, String keyId}), _PreviewCandidate>{};
  for (final track in score.tracks) {
    for (final note in track.notes) {
      final keyId = customPitchToKeyId == null
          ? playablePitchToKeyId[note.pitch]
          : customPitchToKeyId[note.pitch];
      if (keyId == null || !playableKeyIds.contains(keyId)) {
        continue;
      }
      final actionKey = (startMs: note.startMs, keyId: keyId);
      final existing = candidatesByAction[actionKey];
      if (existing == null || note.velocity > existing.velocity) {
        candidatesByAction[actionKey] = _PreviewCandidate(
          sourcePitch: note.pitch,
          velocity: note.velocity,
        );
      }
    }
  }

  final notes = <PreviewLaneNote>[];
  for (final action in semanticPlan.actions) {
    for (final keyId in action.keyIds) {
      final candidate =
          candidatesByAction[(startMs: action.atMs, keyId: keyId)];
      if (candidate == null) {
        continue;
      }
      final nominalPitch = nominalPitchByKeyId[keyId];
      final previewPitch = nominalPitch == null
          ? candidate.sourcePitch
          : variant.effectivePitchForLayoutPitch(nominalPitch);
      final rawDuration = action.durationMsForKey(keyId);
      final effectiveDuration = rawDuration == null || rawDuration <= 0
          ? _previewFallbackPointDurationMs
          : rawDuration;
      notes.add(
        PreviewLaneNote(
          keyId: keyId,
          pitch: previewPitch,
          startMs: action.atMs,
          durationMs: effectiveDuration,
          velocity: candidate.velocity,
          isPoint:
              rawDuration == null || rawDuration <= _previewPointThresholdMs,
        ),
      );
    }
  }
  notes.sort((a, b) => a.startMs.compareTo(b.startMs));
  return notes;
}

class _PreviewCandidate {
  const _PreviewCandidate({required this.sourcePitch, required this.velocity});

  final int sourcePitch;
  final int velocity;
}
