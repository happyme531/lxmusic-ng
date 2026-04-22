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
  final semanticPlan = const PerformancePlanner().plan(
    transformed.score,
    PlanningContext(profile: profile, layout: layout, variant: variant),
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
      final notes = <PreviewLaneNote>[];
      for (final track in session.transformedScore.tracks) {
        for (final note in track.notes) {
          final mappedPitch =
              (note.attrs['mappedPitch'] as int?) ??
              session.variant.mapPitch(note.pitch);
          final keyId =
              note.attrs['keyId'] as String? ??
              session.layout.keyIdForPitch(mappedPitch);
          if (keyId == null) {
            continue;
          }
          final rawDuration = note.durationMs ?? 0;
          final effectiveDuration = rawDuration <= 0
              ? _previewFallbackPointDurationMs
              : rawDuration;
          notes.add(
            PreviewLaneNote(
              keyId: keyId,
              pitch: mappedPitch,
              startMs: note.startMs,
              durationMs: effectiveDuration,
              velocity: note.velocity,
              isPoint:
                  rawDuration <= 0 || rawDuration <= _previewPointThresholdMs,
            ),
          );
        }
      }
      notes.sort((a, b) => a.startMs.compareTo(b.startMs));
      return notes;
    });
