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
    required this.steps,
    this.recommendedPitchOffset = 0,
    this.configLevel = ConfigLevel.simple,
  });

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
    _upsertStep('speedChange', {'speed': value},
        insertAfter: 'singleKeyFrequencyLimit');
  }

  int get pitchOffset {
    final step = _findStep('pitchOffset');
    return step?.config['offset'] as int? ?? 0;
  }

  set pitchOffset(int value) {
    if (value == 0) {
      steps.removeWhere((s) => s.type == 'pitchOffset');
    } else {
      _upsertStep('pitchOffset', {'offset': value}, insertAfter: 'mergeTracks');
    }
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

  int get sameKeyMinIntervalMs {
    final step = _findStep('singleKeyFrequencyLimit');
    return step?.config['minIntervalMs'] as int? ?? 20;
  }

  set sameKeyMinIntervalMs(int value) {
    _upsertStep('singleKeyFrequencyLimit', {'minIntervalMs': value});
  }

  int? get chordMaxNoteCount {
    final step = _findStep('chordNoteCountLimit');
    return step?.config['maxNoteCount'] as int?;
  }

  set chordMaxNoteCount(int? value) {
    if (value == null) {
      steps.removeWhere((s) => s.type == 'chordNoteCountLimit');
    } else {
      _upsertStep('chordNoteCountLimit', {'maxNoteCount': value},
          insertAfter: 'singleKeyFrequencyLimit');
    }
  }

  double? get humanifyStrength {
    final step = _findStep('humanify');
    return (step?.config['noteAbsTimeStdDev'] as num?)?.toDouble();
  }

  set humanifyStrength(double? value) {
    if (value == null || value == 0) {
      steps.removeWhere((s) => s.type == 'humanify');
    } else {
      _upsertStep('humanify', {'noteAbsTimeStdDev': value});
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
    final idx = steps.indexWhere((s) => s.type == type);
    if (idx >= 0) {
      steps[idx] = replacement;
    }
  }

  void _upsertStep(String type, Map<String, Object?> config,
      {String? insertAfter}) {
    final newStep = TransformStep(type: type, config: config);
    final idx = steps.indexWhere((s) => s.type == type);
    if (idx >= 0) {
      steps[idx] = newStep;
    } else if (insertAfter != null) {
      final afterIdx = steps.indexWhere((s) => s.type == insertAfter);
      steps.insert(afterIdx >= 0 ? afterIdx + 1 : steps.length, newStep);
    } else {
      steps.add(newStep);
    }
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
        'steps': steps
            .map((s) => {'type': s.type, 'config': s.config})
            .toList(),
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
