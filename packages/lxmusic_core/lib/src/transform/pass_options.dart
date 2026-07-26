import '../domain/game_profile.dart';
import '../domain/score.dart';

enum SemiToneRoundingMode { none, floor, ceil, drop, both, alternating }

const String customTargetMappingMode = 'custom';
const String targetDerivedMappingMode = 'target';
const String noteKeyMappingModeAttr = 'keyMappingMode';

class LegalizeTargetNoteRangeOptions {
  const LegalizeTargetNoteRangeOptions({
    required this.supportedPitches,
    this.semiToneRoundingMode = SemiToneRoundingMode.floor,
    this.wrapHigherOctave = 0,
    this.wrapLowerOctave = 0,
    this.wrapPitchRange,
  });

  final List<int> supportedPitches;
  final SemiToneRoundingMode semiToneRoundingMode;
  final int wrapHigherOctave;
  final int wrapLowerOctave;

  /// Nominal/physical pitch bounds used only to decide octave wrapping.
  ///
  /// When omitted, the first and last [supportedPitches] retain the legacy
  /// behavior as the wrapping bounds. This can differ from the effective
  /// pitches when an instrument variant retunes its physical keys.
  final IntRange? wrapPitchRange;
}

class NoteToKeyOptions {
  const NoteToKeyOptions({
    required this.pitchToKeyId,
    this.mappingMode = customTargetMappingMode,
  });

  final Map<int, String> pitchToKeyId;

  /// Marks whether downstream consumers should revalidate this key against
  /// the current target or honor it as an explicit custom mapping.
  final String mappingMode;
}

class BindLyricsOptions {
  const BindLyricsOptions({this.lyrics, this.useStoredOriginalTime = false});

  final List<LyricEvent>? lyrics;
  final bool useStoredOriginalTime;
}

class MergeTracksOptions {
  const MergeTracksOptions({this.selectedTracks, this.skipPercussion = true});

  final List<int>? selectedTracks;
  final bool skipPercussion;
}

class PitchOffsetOptions {
  const PitchOffsetOptions({required this.offset});

  final int offset;
}

class MergeNearbyNotesOptions {
  const MergeNearbyNotesOptions({
    required this.maxIntervalMs,
    this.maxBatchSize = 19,
  });

  final int maxIntervalMs;
  final int maxBatchSize;
}

class FoldFrequentSameNoteOptions {
  const FoldFrequentSameNoteOptions({this.maxIntervalMs = 150});

  final int maxIntervalMs;
}

class EstimateNoteDurationOptions {
  const EstimateNoteDurationOptions({this.multiplier = 0.75});

  final double multiplier;
}

class SplitLongNoteOptions {
  const SplitLongNoteOptions({
    this.minDurationMs = 500,
    this.splitDurationMs = 100,
  });

  final int minDurationMs;
  final int splitDurationMs;
}

class SpeedChangeOptions {
  const SpeedChangeOptions({required this.speed});

  final double speed;
}

class LimitBlankDurationOptions {
  const LimitBlankDurationOptions({this.maxBlankDurationMs = 5000});

  final int maxBlankDurationMs;
}

class SkipIntroOptions {
  const SkipIntroOptions({this.maxIntroMs = 2000});

  final int maxIntroMs;
}

class SingleKeyFrequencyLimitOptions {
  const SingleKeyFrequencyLimitOptions({required this.minIntervalMs});

  final int minIntervalMs;
}

class NoteFrequencySoftLimitOptions {
  const NoteFrequencySoftLimitOptions({required this.minIntervalMs});

  final int minIntervalMs;
}

class ChordNoteCountLimitOptions {
  const ChordNoteCountLimitOptions({
    required this.maxNoteCount,
    this.keepHigherPitches = true,
    this.limitMode = 'delete',
    this.splitDelayMs = 5,
    this.selectMode,
    this.randomSeed = 74751,
  });

  final int maxNoteCount;
  final bool keepHigherPitches;
  final String limitMode;
  final int splitDelayMs;
  final String? selectMode;
  final int randomSeed;

  String get effectiveSelectMode =>
      selectMode ?? (keepHigherPitches ? 'high' : 'low');
}

class HumanifyOptions {
  const HumanifyOptions({required this.noteAbsTimeStdDev, this.randomSeed});

  final double noteAbsTimeStdDev;
  final int? randomSeed;
}
