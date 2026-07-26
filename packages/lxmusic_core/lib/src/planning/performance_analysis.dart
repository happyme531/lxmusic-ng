import '../domain/game_profile.dart';
import '../domain/score.dart';
import '../transform/pass_options.dart';
import '../transform/passes.dart';
import '../transform/recommended_pipeline_policy.dart';
import '../transform/transform_pipeline.dart';

class AnalysisTarget {
  const AnalysisTarget({
    required this.profile,
    required this.variant,
    required this.layout,
  });

  final GameProfile profile;
  final InstrumentVariant variant;
  final KeyLayout layout;

  List<int> get supportedPitches {
    final pitches =
        layout.pitchToKeyId.keys
            .where((pitch) => variant.supportsPitch(pitch))
            .toList()
          ..sort();
    if (pitches.isEmpty) {
      throw StateError(
        'Layout ${layout.id} has no playable pitches for variant ${variant.id}.',
      );
    }
    return pitches;
  }

  int get sameKeyMinIntervalMs =>
      variant.sameKeyMinIntervalOverrideMs ?? profile.sameKeyMinIntervalMs;

  Map<String, Object?> toJson() {
    final supported = supportedPitches;
    return <String, Object?>{
      'profileId': profile.id,
      'variantId': variant.id,
      'layoutId': layout.id,
      'playablePitchRange': <int>[supported.first, supported.last],
      'playablePitchCount': supported.length,
    };
  }
}

class PitchOffsetCandidate {
  const PitchOffsetCandidate({
    required this.offset,
    required this.outRangedWeight,
    required this.overFlowedNoteCount,
    required this.underFlowedNoteCount,
    required this.roundedNoteCount,
  });

  final int offset;
  final int outRangedWeight;
  final int overFlowedNoteCount;
  final int underFlowedNoteCount;
  final int roundedNoteCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'offset': offset,
      'outRangedWeight': outRangedWeight,
      'overFlowedNoteCount': overFlowedNoteCount,
      'underFlowedNoteCount': underFlowedNoteCount,
      'roundedNoteCount': roundedNoteCount,
    };
  }
}

class PitchOffsetInference {
  const PitchOffsetInference({
    required this.bestOffset,
    required this.bestCandidate,
    required this.candidates,
  });

  final int bestOffset;
  final PitchOffsetCandidate bestCandidate;
  final List<PitchOffsetCandidate> candidates;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recommendedPitchOffset': bestOffset,
      'recommendedStats': bestCandidate.toJson(),
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    };
  }
}

class TrackPlayabilityRecommendation {
  const TrackPlayabilityRecommendation({
    required this.trackIndex,
    required this.trackName,
    required this.isPercussion,
    required this.noteCount,
    required this.playableNoteCount,
    required this.playableRatio,
    required this.overFlowedNoteCount,
    required this.underFlowedNoteCount,
    required this.roundedNoteCount,
    required this.recommended,
  });

  final int trackIndex;
  final String trackName;
  final bool isPercussion;
  final int noteCount;
  final int playableNoteCount;
  final double playableRatio;
  final int overFlowedNoteCount;
  final int underFlowedNoteCount;
  final int roundedNoteCount;
  final bool recommended;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackIndex': trackIndex,
      'trackName': trackName,
      'isPercussion': isPercussion,
      'noteCount': noteCount,
      'playableNoteCount': playableNoteCount,
      'playableRatio': playableRatio,
      'overFlowedNoteCount': overFlowedNoteCount,
      'underFlowedNoteCount': underFlowedNoteCount,
      'roundedNoteCount': roundedNoteCount,
      'recommended': recommended,
    };
  }
}

class TrackSelectionAnalysis {
  const TrackSelectionAnalysis({
    required this.threshold,
    required this.recommendedTrackIndexes,
    required this.recommendations,
  });

  final double threshold;
  final List<int> recommendedTrackIndexes;
  final List<TrackPlayabilityRecommendation> recommendations;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'threshold': threshold,
      'recommendedTrackIndexes': recommendedTrackIndexes,
      'recommendations': recommendations
          .map((recommendation) => recommendation.toJson())
          .toList(),
    };
  }
}

class ScoreAnalysis {
  const ScoreAnalysis({
    required this.source,
    required this.target,
    required this.pitchOffset,
    required this.trackSelection,
  });

  final Score source;
  final AnalysisTarget target;
  final PitchOffsetInference pitchOffset;
  final TrackSelectionAnalysis? trackSelection;

  TransformPipeline buildRecommendedPipeline({
    SemiToneRoundingMode roundingMode = SemiToneRoundingMode.floor,
  }) {
    final supported = target.supportedPitches;
    final mergeTracksConfig = <String, Object?>{'skipPercussion': false};
    if (trackSelection != null &&
        trackSelection!.recommendedTrackIndexes.isNotEmpty &&
        source.tracks.length > 1) {
      mergeTracksConfig['selectedTracks'] =
          trackSelection!.recommendedTrackIndexes;
    }
    return TransformPipeline(
      canonicalizeRecommendedTransformSteps(<TransformStep>[
        TransformStep(type: 'mergeTracks', config: mergeTracksConfig),
        const TransformStep(type: 'storeCurrentNoteTime'),
        const TransformStep(
          type: 'mergeNearbyNotes',
          config: <String, Object?>{'maxIntervalMs': 50, 'maxBatchSize': 19},
        ),
        if (pitchOffset.bestOffset != 0)
          TransformStep(
            type: 'pitchOffset',
            config: <String, Object?>{'offset': pitchOffset.bestOffset},
          ),
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': supported,
            'semiToneRoundingMode': roundingMode.name,
            'wrapHigherOctave': 1,
            'wrapLowerOctave': 0,
          },
        ),
        TransformStep(
          type: 'singleKeyFrequencyLimit',
          config: <String, Object?>{
            'minIntervalMs': target.sameKeyMinIntervalMs,
          },
        ),
        const TransformStep(
          type: 'skipIntro',
          config: <String, Object?>{'maxIntroMs': 2000},
        ),
        const TransformStep(
          type: 'limitBlankDuration',
          config: <String, Object?>{'maxBlankDurationMs': 5000},
        ),
        const TransformStep(
          type: 'bindLyrics',
          config: <String, Object?>{'useStoredOriginalTime': true},
        ),
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': target.layout.pitchToKeyId.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          },
        ),
      ]),
    );
  }

  Map<String, Object?> toAnalysisJson() {
    return <String, Object?>{
      'source': <String, Object?>{
        'trackCount': source.tracks.length,
        'noteCount': source.totalNoteCount,
        'totalDurationMs': source.totalDurationMs,
      },
      'target': target.toJson(),
      ...pitchOffset.toJson(),
      if (trackSelection != null) 'trackSelection': trackSelection!.toJson(),
      'notes': <String>[
        '当前 analyze 主要覆盖移调和目标可演奏音域合法化。',
        '同键频率限制、歌词绑定、按键映射等步骤会直接写入推荐转换配置。',
        if (trackSelection != null) '多音轨输入会按推荐移调评估每条音轨的可演奏比例，并给出推荐选轨。',
      ],
    };
  }

  Map<String, Object?> toConfigJson({
    SemiToneRoundingMode roundingMode = SemiToneRoundingMode.floor,
  }) {
    return <String, Object?>{
      'version': 1,
      'target': <String, Object?>{
        'profileId': target.profile.id,
        'variantId': target.variant.id,
        'layoutId': target.layout.id,
      },
      'analysis': <String, Object?>{
        'recommendedPitchOffset': pitchOffset.bestOffset,
        'recommendedStats': pitchOffset.bestCandidate.toJson(),
        if (trackSelection != null)
          'recommendedTrackIndexes': trackSelection!.recommendedTrackIndexes,
      },
      'pipeline': <String, Object?>{
        'steps': buildRecommendedPipeline(roundingMode: roundingMode).steps.map(
          (step) {
            return <String, Object?>{'type': step.type, 'config': step.config};
          },
        ).toList(),
      },
    };
  }
}

ScoreAnalysis analyzeScoreForTarget(
  Score score, {
  required AnalysisTarget target,
  SemiToneRoundingMode roundingMode = SemiToneRoundingMode.floor,
  double trackDisableThreshold = 0.5,
  bool skipPercussionTracks = true,
  int? fixedPitchOffset,
}) {
  final merged = const MergeTracksPass(MergeTracksOptions()).run(score).score;
  final supportedPitches = target.supportedPitches;
  final pitchOffset = fixedPitchOffset == null
      ? inferBestPitchOffset(
          score: merged,
          supportedPitches: supportedPitches,
          roundingMode: roundingMode,
        )
      : evaluateFixedPitchOffset(
          score: merged,
          supportedPitches: supportedPitches,
          roundingMode: roundingMode,
          offset: fixedPitchOffset,
        );
  return ScoreAnalysis(
    source: score,
    target: target,
    pitchOffset: pitchOffset,
    trackSelection: analyzeTrackSelection(
      score: score,
      recommendedOffset: pitchOffset.bestOffset,
      supportedPitches: supportedPitches,
      roundingMode: roundingMode,
      threshold: trackDisableThreshold,
      skipPercussionTracks: skipPercussionTracks,
    ),
  );
}

PitchOffsetInference evaluateFixedPitchOffset({
  required Score score,
  required List<int> supportedPitches,
  required SemiToneRoundingMode roundingMode,
  required int offset,
}) {
  final candidate = evaluatePitchOffset(
    score: score,
    supportedPitches: supportedPitches,
    roundingMode: roundingMode,
    offset: offset,
  );
  return PitchOffsetInference(
    bestOffset: offset,
    bestCandidate: candidate,
    candidates: <PitchOffsetCandidate>[candidate],
  );
}

TrackSelectionAnalysis? analyzeTrackSelection({
  required Score score,
  required int recommendedOffset,
  required List<int> supportedPitches,
  required SemiToneRoundingMode roundingMode,
  required double threshold,
  bool skipPercussionTracks = true,
}) {
  if (score.tracks.length <= 1) {
    return null;
  }

  final ranked =
      <
        ({
          int trackIndex,
          Track track,
          int noteCount,
          int playableNoteCount,
          double playableRatio,
          int overFlowedNoteCount,
          int underFlowedNoteCount,
          int roundedNoteCount,
          bool isPercussion,
        })
      >[];

  for (var trackIndex = 0; trackIndex < score.tracks.length; trackIndex++) {
    final track = score.tracks[trackIndex];
    final trackScore = Score(
      format: score.format,
      lyrics: score.lyrics,
      metadata: score.metadata,
      tracks: <Track>[track],
    );
    final shifted = PitchOffsetPass(
      PitchOffsetOptions(offset: recommendedOffset),
    ).run(trackScore);
    final legalized = LegalizeTargetNoteRangePass(
      LegalizeTargetNoteRangeOptions(
        supportedPitches: supportedPitches,
        semiToneRoundingMode: roundingMode,
      ),
    ).run(shifted.score);
    final stat = legalized.report.stats.single;
    final overflow = (stat.values['overFlowedNoteCount'] as int?) ?? 0;
    final underflow = (stat.values['underFlowedNoteCount'] as int?) ?? 0;
    final rounded = (stat.values['roundedNoteCount'] as int?) ?? 0;
    final noteCount = track.notes.length;
    final playableNoteCount = noteCount - overflow - underflow;
    final playableRatio = noteCount == 0 ? 0.0 : playableNoteCount / noteCount;
    ranked.add((
      trackIndex: trackIndex,
      track: track,
      noteCount: noteCount,
      playableNoteCount: playableNoteCount,
      playableRatio: playableRatio,
      overFlowedNoteCount: overflow,
      underFlowedNoteCount: underflow,
      roundedNoteCount: rounded,
      isPercussion: track.channel == 9,
    ));
  }

  ranked.sort((a, b) {
    final ratioOrder = b.playableRatio.compareTo(a.playableRatio);
    if (ratioOrder != 0) {
      return ratioOrder;
    }
    final countOrder = b.playableNoteCount.compareTo(a.playableNoteCount);
    if (countOrder != 0) {
      return countOrder;
    }
    return a.trackIndex.compareTo(b.trackIndex);
  });

  final recommendationCandidates = skipPercussionTracks
      ? ranked.where((entry) => !entry.isPercussion).toList()
      : ranked;
  final effectiveCandidates = recommendationCandidates.isNotEmpty
      ? recommendationCandidates
      : ranked;
  final recommendedTrackIndexes = <int>[
    effectiveCandidates.first.trackIndex,
    ...effectiveCandidates
        .skip(1)
        .where((entry) => entry.playableRatio > threshold)
        .map((entry) => entry.trackIndex),
  ];
  final recommendedSet = recommendedTrackIndexes.toSet();

  return TrackSelectionAnalysis(
    threshold: threshold,
    recommendedTrackIndexes: recommendedTrackIndexes,
    recommendations:
        (ranked.toList()..sort((a, b) => a.trackIndex.compareTo(b.trackIndex)))
            .map(
              (entry) => TrackPlayabilityRecommendation(
                trackIndex: entry.trackIndex,
                trackName: entry.track.name,
                isPercussion: entry.isPercussion,
                noteCount: entry.noteCount,
                playableNoteCount: entry.playableNoteCount,
                playableRatio: entry.playableRatio,
                overFlowedNoteCount: entry.overFlowedNoteCount,
                underFlowedNoteCount: entry.underFlowedNoteCount,
                roundedNoteCount: entry.roundedNoteCount,
                recommended: recommendedSet.contains(entry.trackIndex),
              ),
            )
            .toList(),
  );
}

PitchOffsetInference inferBestPitchOffset({
  required Score score,
  required List<int> supportedPitches,
  required SemiToneRoundingMode roundingMode,
}) {
  const majorOffsets = <int>[0, -1, 1, -2, 2];
  const minorOffsets = <int>[0, 1, -1, 2, -2, 3, -3, 4, -4, 5, 6, 7];
  const betterResultThreshold = 0.05;

  var bestMajor = 0;
  var bestMinor = 0;
  final candidates = <PitchOffsetCandidate>[];

  bool isSignificantlyBetter(int previous, int current) {
    return previous - current > current * betterResultThreshold;
  }

  var bestOutRanged = 1 << 30;
  for (final major in majorOffsets) {
    final candidate = evaluatePitchOffset(
      score: score,
      supportedPitches: supportedPitches,
      roundingMode: roundingMode,
      offset: major * 12,
    );
    candidates.add(candidate);
    if (isSignificantlyBetter(bestOutRanged, candidate.outRangedWeight)) {
      bestOutRanged = candidate.outRangedWeight;
      bestMajor = major;
    }
  }

  var bestRounded = 1 << 30;
  for (final minor in minorOffsets) {
    final candidate = evaluatePitchOffset(
      score: score,
      supportedPitches: supportedPitches,
      roundingMode: roundingMode,
      offset: bestMajor * 12 + minor,
    );
    candidates.add(candidate);
    if (isSignificantlyBetter(bestRounded, candidate.roundedNoteCount)) {
      bestRounded = candidate.roundedNoteCount;
      bestMinor = minor;
    }
  }

  PitchOffsetCandidate? bestCandidate;
  bestOutRanged = 1 << 30;
  for (final major in majorOffsets) {
    final candidate = evaluatePitchOffset(
      score: score,
      supportedPitches: supportedPitches,
      roundingMode: roundingMode,
      offset: major * 12 + bestMinor,
    );
    candidates.add(candidate);
    if (isSignificantlyBetter(bestOutRanged, candidate.outRangedWeight)) {
      bestOutRanged = candidate.outRangedWeight;
      bestMajor = major;
      bestCandidate = candidate;
    }
  }

  bestCandidate ??= evaluatePitchOffset(
    score: score,
    supportedPitches: supportedPitches,
    roundingMode: roundingMode,
    offset: bestMajor * 12 + bestMinor,
  );

  return PitchOffsetInference(
    bestOffset: bestCandidate.offset,
    bestCandidate: bestCandidate,
    candidates: candidates,
  );
}

PitchOffsetCandidate evaluatePitchOffset({
  required Score score,
  required List<int> supportedPitches,
  required SemiToneRoundingMode roundingMode,
  required int offset,
}) {
  const overFlowWeight = 5;
  final shifted = PitchOffsetPass(
    PitchOffsetOptions(offset: offset),
  ).run(score);
  final legalized = LegalizeTargetNoteRangePass(
    LegalizeTargetNoteRangeOptions(
      supportedPitches: supportedPitches,
      semiToneRoundingMode: roundingMode,
    ),
  ).run(shifted.score);
  final stat = legalized.report.stats.single;
  final overflow = (stat.values['overFlowedNoteCount'] as int?) ?? 0;
  final underflow = (stat.values['underFlowedNoteCount'] as int?) ?? 0;
  final rounded = (stat.values['roundedNoteCount'] as int?) ?? 0;
  return PitchOffsetCandidate(
    offset: offset,
    outRangedWeight: overflow * overFlowWeight + underflow,
    overFlowedNoteCount: overflow,
    underFlowedNoteCount: underflow,
    roundedNoteCount: rounded,
  );
}
