import '../domain/score.dart';
import 'pass_options.dart';
import 'passes.dart';
import 'transform_report.dart';

class TransformStep {
  const TransformStep({
    required this.type,
    this.config = const <String, Object?>{},
  });

  final String type;
  final Map<String, Object?> config;
}

class TransformPipeline {
  const TransformPipeline(this.steps);

  final List<TransformStep> steps;

  ({Score score, TransformReport report}) run(Score input) {
    var score = input;
    final stats = <PassStat>[];
    final warnings = <String>[];
    final inputNotes = input.totalNoteCount;
    var pipelineAdded = 0;
    var pipelineRemoved = 0;

    for (final step in steps) {
      final before = score.totalNoteCount;
      final result = _runStep(step, score);
      score = result.score;
      final after = score.totalNoteCount;
      final delta = after - before;
      if (delta > 0) {
        pipelineAdded += delta;
      } else if (delta < 0) {
        pipelineRemoved += -delta;
      }
      stats.addAll(result.report.stats);
      warnings.addAll(result.report.warnings);
    }

    final summary = NotePipelineSummary(
      inputNoteCount: inputNotes,
      outputNoteCount: score.totalNoteCount,
      pipelineNotesAdded: pipelineAdded,
      pipelineNotesRemoved: pipelineRemoved,
    );

    return (
      score: score,
      report: TransformReport(
        stats: stats,
        warnings: warnings,
        noteSummary: summary,
      ),
    );
  }

  ({Score score, TransformReport report}) _runStep(
    TransformStep step,
    Score score,
  ) {
    switch (step.type) {
      case 'mergeTracks':
        return MergeTracksPass(
          MergeTracksOptions(
            selectedTracks: (step.config['selectedTracks'] as List<Object?>?)
                ?.map((value) => value as int)
                .toList(),
            skipPercussion: step.config['skipPercussion'] as bool? ?? true,
          ),
        ).run(score);
      case 'removeEmptyTracks':
        return const RemoveEmptyTracksPass().run(score);
      case 'pitchOffset':
        return PitchOffsetPass(
          PitchOffsetOptions(offset: step.config['offset'] as int),
        ).run(score);
      case 'legalizeTargetNoteRange':
        return LegalizeTargetNoteRangePass(
          LegalizeTargetNoteRangeOptions(
            supportedPitches:
                (step.config['supportedPitches'] as List<Object?>? ??
                        const <Object?>[])
                    .map((value) => value as int)
                    .toList(),
            semiToneRoundingMode: SemiToneRoundingMode.values.byName(
              (step.config['semiToneRoundingMode'] as String?) ?? 'floor',
            ),
            wrapHigherOctave: step.config['wrapHigherOctave'] as int? ?? 0,
            wrapLowerOctave: step.config['wrapLowerOctave'] as int? ?? 0,
          ),
        ).run(score);
      case 'noteToKey':
        return NoteToKeyPass(
          NoteToKeyOptions(
            pitchToKeyId: Map<String, Object?>.from(
              step.config['pitchToKeyId'] as Map? ?? const <String, Object?>{},
            ).map((key, value) => MapEntry(int.parse(key), value as String)),
          ),
        ).run(score);
      case 'bindLyrics':
        return BindLyricsPass(
          BindLyricsOptions(
            useStoredOriginalTime:
                step.config['useStoredOriginalTime'] as bool? ?? false,
          ),
        ).run(score);
      case 'storeCurrentNoteTime':
        return const StoreCurrentNoteTimePass().run(score);
      case 'mergeNearbyNotes':
        return MergeNearbyNotesPass(
          MergeNearbyNotesOptions(
            maxIntervalMs: step.config['maxIntervalMs'] as int,
            maxBatchSize: step.config['maxBatchSize'] as int? ?? 19,
          ),
        ).run(score);
      case 'foldFrequentSameNote':
        return FoldFrequentSameNotePass(
          FoldFrequentSameNoteOptions(
            maxIntervalMs: step.config['maxIntervalMs'] as int? ?? 150,
          ),
        ).run(score);
      case 'estimateNoteDuration':
        return EstimateNoteDurationPass(
          EstimateNoteDurationOptions(
            multiplier: (step.config['multiplier'] as num?)?.toDouble() ?? 0.75,
          ),
        ).run(score);
      case 'splitLongNote':
        return SplitLongNotePass(
          SplitLongNoteOptions(
            minDurationMs: step.config['minDurationMs'] as int? ?? 500,
            splitDurationMs: step.config['splitDurationMs'] as int? ?? 100,
          ),
        ).run(score);
      case 'speedChange':
        return SpeedChangePass(
          SpeedChangeOptions(speed: (step.config['speed'] as num).toDouble()),
        ).run(score);
      case 'limitBlankDuration':
        return LimitBlankDurationPass(
          LimitBlankDurationOptions(
            maxBlankDurationMs:
                step.config['maxBlankDurationMs'] as int? ?? 5000,
          ),
        ).run(score);
      case 'skipIntro':
        return SkipIntroPass(
          SkipIntroOptions(
            maxIntroMs: step.config['maxIntroMs'] as int? ?? 2000,
          ),
        ).run(score);
      case 'singleKeyFrequencyLimit':
        return SingleKeyFrequencyLimitPass(
          SingleKeyFrequencyLimitOptions(
            minIntervalMs: step.config['minIntervalMs'] as int,
          ),
        ).run(score);
      case 'noteFrequencySoftLimit':
        return NoteFrequencySoftLimitPass(
          NoteFrequencySoftLimitOptions(
            minIntervalMs: step.config['minIntervalMs'] as int,
          ),
        ).run(score);
      case 'chordNoteCountLimit':
        return ChordNoteCountLimitPass(
          ChordNoteCountLimitOptions(
            maxNoteCount: step.config['maxNoteCount'] as int,
            keepHigherPitches:
                step.config['keepHigherPitches'] as bool? ?? true,
            limitMode: step.config['limitMode'] as String? ?? 'delete',
            splitDelayMs: step.config['splitDelayMs'] as int? ??
                step.config['splitDelay'] as int? ??
                5,
            selectMode: step.config['selectMode'] as String?,
            randomSeed: step.config['randomSeed'] as int? ?? 74751,
          ),
        ).run(score);
      case 'humanify':
        return HumanifyPass(
          HumanifyOptions(
            noteAbsTimeStdDev: (step.config['noteAbsTimeStdDev'] as num)
                .toDouble(),
            randomSeed: step.config['randomSeed'] as int?,
          ),
        ).run(score);
      default:
        throw ArgumentError('Unknown transform step type "${step.type}".');
    }
  }
}
