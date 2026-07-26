import '../domain/score.dart';
import '../domain/semantic_plan.dart';
import 'execution_context.dart';

class PerformancePlanner {
  const PerformancePlanner();

  SemanticPlan plan(Score score, PlanningContext context) {
    final warnings = <PlanWarning>[];
    final actions = <SemanticAction>[];
    final sameKeyMinInterval =
        context.variant.sameKeyMinIntervalOverrideMs ??
        context.profile.sameKeyMinIntervalMs;
    final playablePitchToKeyId = context.variant.playablePitchToKeyId(
      context.layout,
    );
    final playableKeyIds = playablePitchToKeyId.values.toSet();
    final customPitchToKeyId = context.customPitchToKeyId;
    final lastKeyTime = <String, int>{};

    final allNotes = <NoteEvent>[
      for (final track in score.tracks) ...track.notes,
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));

    final grouped = <int, List<NoteEvent>>{};
    for (final note in allNotes) {
      grouped.putIfAbsent(note.startMs, () => <NoteEvent>[]).add(note);
    }

    for (final entry
        in grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final durationMsByKeyId = <String, int?>{};

      for (final note in entry.value) {
        final playablePitch = note.pitch;
        final annotatedKeyId = note.attrs['keyId'] as String?;
        final annotatedPitch = note.attrs['mappedPitch'];
        late final String keyId;
        if (customPitchToKeyId != null) {
          final customKeyId = customPitchToKeyId[playablePitch];
          if (customKeyId == null || !playableKeyIds.contains(customKeyId)) {
            warnings.add(
              PlanWarning(
                code: 'missing_key_mapping',
                message:
                    'Pitch $playablePitch has no valid custom key mapping '
                    'for layout ${context.layout.id}.',
              ),
            );
            continue;
          }
          keyId = customKeyId;

          if ((annotatedKeyId != null && annotatedKeyId != keyId) ||
              (annotatedPitch != null && annotatedPitch != playablePitch)) {
            warnings.add(
              PlanWarning(
                code: 'stale_key_mapping',
                message:
                    'Pitch $playablePitch ignored stale note annotations and '
                    'used custom key $keyId from the current pipeline.',
              ),
            );
          }
        } else {
          if (!context.variant.supportsPitch(playablePitch)) {
            warnings.add(
              PlanWarning(
                code: 'pitch_out_of_range',
                message:
                    'Pitch $playablePitch was dropped by variant ${context.variant.id}.',
              ),
            );
            continue;
          }

          final targetKeyId = playablePitchToKeyId[playablePitch];
          if (targetKeyId == null) {
            warnings.add(
              PlanWarning(
                code: 'missing_key_mapping',
                message:
                    'Pitch $playablePitch is not mapped for variant '
                    '${context.variant.id} in layout ${context.layout.id}.',
              ),
            );
            continue;
          }
          keyId = targetKeyId;

          if (annotatedKeyId != null && annotatedKeyId != keyId) {
            warnings.add(
              PlanWarning(
                code: 'stale_key_mapping',
                message:
                    'Pitch $playablePitch was remapped from annotated key '
                    '$annotatedKeyId to $keyId for variant '
                    '${context.variant.id}.',
              ),
            );
          }
        }

        final noteDurationMs = note.durationMs == null
            ? null
            : note.durationMs! < 0
            ? 0
            : note.durationMs;
        if (!durationMsByKeyId.containsKey(keyId)) {
          durationMsByKeyId[keyId] = noteDurationMs;
          continue;
        }

        final existingDurationMs = durationMsByKeyId[keyId];
        if (existingDurationMs == null ||
            (noteDurationMs != null && noteDurationMs > existingDurationMs)) {
          durationMsByKeyId[keyId] = noteDurationMs;
        }
      }

      final acceptedDurationMsByKeyId = <String, int?>{};
      final sortedKeyIds = durationMsByKeyId.keys.toList()..sort();
      for (final keyId in sortedKeyIds) {
        final lastPlayedAt = lastKeyTime[keyId];
        if (lastPlayedAt != null &&
            entry.key - lastPlayedAt < sameKeyMinInterval) {
          warnings.add(
            PlanWarning(
              code: 'same_key_throttled',
              message:
                  'Key $keyId at ${entry.key}ms was skipped due to same-key limit.',
            ),
          );
          continue;
        }
        acceptedDurationMsByKeyId[keyId] = durationMsByKeyId[keyId];
        lastKeyTime[keyId] = entry.key;
      }

      if (acceptedDurationMsByKeyId.isNotEmpty) {
        actions.add(
          SemanticAction.perKey(
            atMs: entry.key,
            durationMsByKeyId: acceptedDurationMsByKeyId,
          ),
        );
      }
    }

    return SemanticPlan(
      profileId: context.profile.id,
      layoutId: context.layout.id,
      variantId: context.variant.id,
      actions: actions,
      totalDurationMs: score.totalDurationMs,
      warnings: warnings,
    );
  }
}
