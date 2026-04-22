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
      final keyIds = <String>[];
      var durationMs = 0;

      for (final note in entry.value) {
        final mappedPitch =
            (note.attrs['mappedPitch'] as int?) ??
            context.variant.mapPitch(note.pitch);
        final precomputedKeyId = note.attrs['keyId'] as String?;

        if (precomputedKeyId == null &&
            !context.variant.supportsPitch(mappedPitch)) {
          warnings.add(
            PlanWarning(
              code: 'pitch_out_of_range',
              message:
                  'Pitch $mappedPitch was dropped by variant ${context.variant.id}.',
            ),
          );
          continue;
        }

        final keyId =
            precomputedKeyId ?? context.layout.keyIdForPitch(mappedPitch);
        if (keyId == null) {
          warnings.add(
            PlanWarning(
              code: 'missing_key_mapping',
              message:
                  'Pitch $mappedPitch is not mapped in layout ${context.layout.id}.',
            ),
          );
          continue;
        }

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

        keyIds.add(keyId);
        lastKeyTime[keyId] = entry.key;
        if (note.durationMs != null && note.durationMs! > durationMs) {
          durationMs = note.durationMs!;
        }
      }

      if (keyIds.isNotEmpty) {
        actions.add(
          SemanticAction(
            atMs: entry.key,
            durationMs: durationMs,
            keyIds: keyIds.toSet().toList()..sort(),
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
