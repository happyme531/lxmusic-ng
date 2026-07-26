import 'package:lxmusic_core/lxmusic_core.dart';

/// Persisted per-song configuration.
///
/// Flow: user selects file + target → auto-analyze once → recommended pipeline
/// is saved as the default config → user can then tweak any step manually.
class SongConfig {
  SongConfig({
    required this.fileName,
    required this.profileId,
    required this.variantId,
    required this.layoutId,
    required List<TransformStep> steps,
    this.recommendedPitchOffset = 0,
    this.configLevel = ConfigLevel.simple,
  }) : steps = canonicalizeRecommendedTransformSteps(steps);

  final String fileName;
  final String profileId;
  final String variantId;
  final String layoutId;

  /// Pipeline steps (the user-editable part).
  List<TransformStep> steps;

  /// The pitch offset suggested by analysis (informational).
  int recommendedPitchOffset;

  /// Which config level the user is currently viewing.
  ConfigLevel configLevel;

  // -------------------------------------------------------------------------
  // Convenience accessors for common step parameters
  // -------------------------------------------------------------------------

  double get speed {
    final step = _findStep('speedChange');
    return (step?.config['speed'] as num?)?.toDouble() ?? 1.0;
  }

  set speed(double value) {
    if (value == 1.0) {
      _removeSteps(const <String>{'speedChange'});
      return;
    }
    _upsertStep('speedChange', {'speed': value});
  }

  int get pitchOffset {
    final step = _findStep('pitchOffset');
    return step?.config['offset'] as int? ?? 0;
  }

  set pitchOffset(int value) {
    _writePitchOffset(
      value,
      uiConfig: <String, Object?>{
        'octaveOffset': _octaveComponent(value),
        'semitoneOffset': _semitoneComponent(value),
      },
      preserveUiConfig: false,
    );
  }

  int get recommendedPitchOctaveOffset {
    return _octaveComponent(recommendedPitchOffset);
  }

  int get recommendedPitchSemitoneOffset {
    return _semitoneComponent(recommendedPitchOffset);
  }

  int get pitchOctaveOffset {
    final stored = _findStep('pitchOffset')?.config['octaveOffset'] as int?;
    return stored ?? _octaveComponent(pitchOffset);
  }

  set pitchOctaveOffset(int value) {
    final octave = value.clamp(-2, 2).toInt();
    _writePitchOffset(
      octave * 12 + pitchSemitoneOffset,
      uiConfig: <String, Object?>{
        'octaveOffset': octave,
        'semitoneOffset': pitchSemitoneOffset,
      },
    );
  }

  int get pitchSemitoneOffset {
    final stored = _findStep('pitchOffset')?.config['semitoneOffset'] as int?;
    return stored ?? _semitoneComponent(pitchOffset);
  }

  set pitchSemitoneOffset(int value) {
    final semitone = value.clamp(-11, 11).toInt();
    _writePitchOffset(
      pitchOctaveOffset * 12 + semitone,
      uiConfig: <String, Object?>{
        'octaveOffset': pitchOctaveOffset,
        'semitoneOffset': semitone,
      },
    );
  }

  int get simplePitchOctaveShift {
    final stored =
        _findStep('pitchOffset')?.config['simpleOctaveShift'] as int?;
    if (stored != null) {
      return stored.clamp(-1, 1);
    }
    return (pitchOctaveOffset - recommendedPitchOctaveOffset)
        .clamp(-1, 1)
        .toInt();
  }

  set simplePitchOctaveShift(int value) {
    final shift = value.clamp(-1, 1).toInt();
    final octave = recommendedPitchOctaveOffset + shift;
    final semitone = recommendedPitchSemitoneOffset;
    _writePitchOffset(
      octave * 12 + semitone,
      uiConfig: <String, Object?>{
        'simpleOctaveShift': shift,
        'octaveOffset': octave,
        'semitoneOffset': semitone,
      },
    );
  }

  bool get skipPercussion {
    final step = _findStep('mergeTracks');
    return step?.config['skipPercussion'] as bool? ?? true;
  }

  set skipPercussion(bool value) {
    final step = _findStep('mergeTracks');
    if (step != null) {
      _replaceStep(
        'mergeTracks',
        TransformStep(
          type: 'mergeTracks',
          config: {...step.config, 'skipPercussion': value},
        ),
      );
    }
  }

  List<int>? get selectedTrackIndexes {
    final raw = _findStep('mergeTracks')?.config['selectedTracks'] as List?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw.map((value) => value as int).toList();
  }

  set selectedTrackIndexes(List<int>? value) {
    final step = _findStep('mergeTracks');
    if (step == null) {
      return;
    }
    final nextConfig = Map<String, Object?>.from(step.config);
    final normalized = value == null ? null : (value.toSet().toList()..sort());
    if (normalized == null || normalized.isEmpty) {
      nextConfig.remove('selectedTracks');
    } else {
      nextConfig['selectedTracks'] = normalized;
    }
    _replaceStep(
      'mergeTracks',
      TransformStep(type: 'mergeTracks', config: nextConfig),
    );
  }

  String get semiToneRoundingMode {
    final step = _findStep('legalizeTargetNoteRange');
    return step?.config['semiToneRoundingMode'] as String? ?? 'floor';
  }

  set semiToneRoundingMode(String value) {
    final step = _findStep('legalizeTargetNoteRange');
    if (step != null) {
      _replaceStep(
        'legalizeTargetNoteRange',
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: {...step.config, 'semiToneRoundingMode': value},
        ),
      );
    }
  }

  bool get wrapHigherOctaveIntoRange {
    final step = _findStep('legalizeTargetNoteRange');
    return (step?.config['wrapHigherOctave'] as int? ?? 1) > 0;
  }

  set wrapHigherOctaveIntoRange(bool value) {
    _setLegalizeIntConfig('wrapHigherOctave', value ? 1 : 0);
  }

  bool get wrapLowerOctaveIntoRange {
    final step = _findStep('legalizeTargetNoteRange');
    return (step?.config['wrapLowerOctave'] as int? ?? 0) > 0;
  }

  set wrapLowerOctaveIntoRange(bool value) {
    _setLegalizeIntConfig('wrapLowerOctave', value ? 1 : 0);
  }

  int get sameKeyMinIntervalMs {
    final step = _findStep('singleKeyFrequencyLimit');
    return step?.config['minIntervalMs'] as int? ?? 20;
  }

  set sameKeyMinIntervalMs(int value) {
    _upsertStep('singleKeyFrequencyLimit', {'minIntervalMs': value});
  }

  double? get clickLimitPerSecond {
    final step = _findStep('noteFrequencySoftLimit');
    final minIntervalMs = step?.config['minIntervalMs'] as int?;
    if (minIntervalMs == null || minIntervalMs <= 0) {
      return null;
    }
    return 1000 / minIntervalMs;
  }

  set clickLimitPerSecond(double? value) {
    if (value == null || value <= 0) {
      _removeSteps(const <String>{'noteFrequencySoftLimit'});
      return;
    }
    final minIntervalMs = (1000 / value).round().clamp(1, 10000);
    _upsertStep('noteFrequencySoftLimit', {'minIntervalMs': minIntervalMs});
  }

  int? get chordMaxNoteCount {
    final step = _findStep('chordNoteCountLimit');
    return step?.config['maxNoteCount'] as int?;
  }

  set chordMaxNoteCount(int? value) {
    if (value == null) {
      _removeSteps(const <String>{'chordNoteCountLimit'});
      return;
    }

    final existing = _findStep('chordNoteCountLimit');
    _upsertStep(
      'chordNoteCountLimit',
      existing == null
          ? <String, Object?>{
              'maxNoteCount': value,
              'limitMode': 'split',
              'splitDelayMs': 75,
              'selectMode': 'high',
            }
          : <String, Object?>{'maxNoteCount': value},
    );
  }

  bool get skipBlank {
    return _findStep('skipIntro') != null &&
        _findStep('limitBlankDuration') != null;
  }

  set skipBlank(bool value) {
    _removeSteps(const <String>{'skipIntro', 'limitBlankDuration'});
    if (!value) {
      return;
    }
    _upsertStep('skipIntro', const <String, Object?>{'maxIntroMs': 2000});
    _upsertStep('limitBlankDuration', const <String, Object?>{
      'maxBlankDurationMs': 5000,
    });
  }

  double? get humanifyStrength {
    final step = _findStep('humanify');
    return (step?.config['noteAbsTimeStdDev'] as num?)?.toDouble();
  }

  set humanifyStrength(double? value) {
    if (value == null || value == 0) {
      _removeSteps(const <String>{'humanify'});
    } else {
      _upsertStep('humanify', {'noteAbsTimeStdDev': value});
    }
  }

  void setOptionalTransformStep({
    required bool enabled,
    required TransformStep step,
  }) {
    if (enabled) {
      _upsertStep(step.type, step.config);
    } else {
      _removeSteps(<String>{step.type});
    }
  }

  // -------------------------------------------------------------------------
  // Step manipulation helpers
  // -------------------------------------------------------------------------

  TransformStep? _findStep(String type) {
    for (final step in steps) {
      if (step.type == type) return step;
    }
    return null;
  }

  void _replaceStep(String type, TransformStep replacement) {
    if (_findStep(type) != null) {
      steps = upsertRecommendedTransformStep(
        steps,
        replacement,
        mergeConfig: false,
      );
    }
  }

  void _upsertStep(String type, Map<String, Object?> config) {
    steps = upsertRecommendedTransformStep(
      steps,
      TransformStep(type: type, config: config),
    );
  }

  void _removeSteps(Iterable<String> types) {
    steps = removeRecommendedTransformSteps(steps, types);
  }

  void _setLegalizeIntConfig(String key, int value) {
    final step = _findStep('legalizeTargetNoteRange');
    if (step == null) {
      return;
    }
    _replaceStep(
      'legalizeTargetNoteRange',
      TransformStep(
        type: 'legalizeTargetNoteRange',
        config: {...step.config, key: value},
      ),
    );
  }

  void _writePitchOffset(
    int value, {
    Map<String, Object?> uiConfig = const <String, Object?>{},
    bool preserveUiConfig = true,
  }) {
    final offset = value;
    final existing = _findStep('pitchOffset')?.config ?? const {};
    final nextConfig = <String, Object?>{
      if (preserveUiConfig) ...existing,
      'offset': offset,
      ...uiConfig,
    };
    if (offset == 0 && nextConfig.length == 1) {
      _removeSteps(const <String>{'pitchOffset'});
    } else {
      _upsertStep('pitchOffset', nextConfig);
    }
  }

  int _octaveComponent(int offset) {
    if (offset >= 0) {
      return offset ~/ 12;
    }
    return -((-offset + 11) ~/ 12);
  }

  int _semitoneComponent(int offset) {
    return offset - _octaveComponent(offset) * 12;
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'profileId': profileId,
    'variantId': variantId,
    'layoutId': layoutId,
    'recommendedPitchOffset': recommendedPitchOffset,
    'configLevel': configLevel.name,
    'steps': steps.map((s) => {'type': s.type, 'config': s.config}).toList(),
  };

  factory SongConfig.fromJson(Map<String, Object?> json) {
    final stepsList = (json['steps'] as List?) ?? [];
    return SongConfig(
      fileName: json['fileName'] as String,
      profileId: json['profileId'] as String,
      variantId: json['variantId'] as String,
      layoutId: json['layoutId'] as String,
      recommendedPitchOffset: json['recommendedPitchOffset'] as int? ?? 0,
      configLevel: ConfigLevel.values.byName(
        json['configLevel'] as String? ?? 'simple',
      ),
      steps: stepsList.map((raw) {
        final map = raw as Map<String, Object?>;
        return TransformStep(
          type: map['type'] as String,
          config: Map<String, Object?>.from(map['config'] as Map? ?? {}),
        );
      }).toList(),
    );
  }
}

enum ConfigLevel { simple, advanced, expert }
