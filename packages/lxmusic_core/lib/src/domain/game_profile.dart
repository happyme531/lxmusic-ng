enum NoteDurationMode { none, nativeHold, extraLongKey }

class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;

  bool contains(int value) => value >= min && value <= max;

  Map<String, Object?> toJson() => <String, Object?>{'min': min, 'max': max};
}

class LayoutBinding {
  const LayoutBinding({
    required this.layoutId,
    this.displayName,
    this.isDefault = false,
  });

  final String layoutId;
  final String? displayName;
  final bool isDefault;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'layoutId': layoutId,
      'displayName': displayName,
      'isDefault': isDefault,
    };
  }
}

class InstrumentVariant {
  const InstrumentVariant({
    required this.id,
    required this.displayName,
    required this.noteDurationMode,
    this.aliases = const [],
    this.availablePitchRange,
    this.replacePitchMap = const {},
    this.sameKeyMinIntervalOverrideMs,
  });

  final String id;
  final String displayName;
  final List<String> aliases;
  final IntRange? availablePitchRange;
  final Map<int, int> replacePitchMap;
  final NoteDurationMode noteDurationMode;
  final int? sameKeyMinIntervalOverrideMs;

  int mapPitch(int pitch) => replacePitchMap[pitch] ?? pitch;

  bool supportsPitch(int pitch) {
    if (availablePitchRange == null) {
      return true;
    }
    return availablePitchRange!.contains(pitch);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'displayName': displayName,
      'aliases': aliases,
      'availablePitchRange': availablePitchRange?.toJson(),
      'replacePitchMap': replacePitchMap.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'noteDurationMode': noteDurationMode.name,
      'sameKeyMinIntervalOverrideMs': sameKeyMinIntervalOverrideMs,
    };
  }
}

class KeyDefinition {
  const KeyDefinition({
    required this.id,
    required this.normX,
    required this.normY,
    this.pitch,
  });

  final String id;
  final int? pitch;
  final double normX;
  final double normY;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pitch': pitch,
      'normX': normX,
      'normY': normY,
    };
  }
}

enum LayoutAlgorithm { explicit, procedural }

class KeyLayout {
  const KeyLayout({
    required this.id,
    required this.algorithm,
    required this.keys,
    required this.pitchToKeyId,
    this.metadata = const {},
  });

  final String id;
  final LayoutAlgorithm algorithm;
  final List<KeyDefinition> keys;
  final Map<int, String> pitchToKeyId;
  final Map<String, Object?> metadata;

  String? keyIdForPitch(int pitch) => pitchToKeyId[pitch];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'algorithm': algorithm.name,
      'keys': keys.map((key) => key.toJson()).toList(),
      'pitchToKeyId': pitchToKeyId.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'metadata': metadata,
    };
  }
}

class GameProfile {
  const GameProfile({
    required this.id,
    required this.displayName,
    required this.packageNameHints,
    required this.layouts,
    required this.variants,
    required this.sameKeyMinIntervalMs,
    this.defaultLayoutId,
    this.featureFlags = const {},
  });

  final String id;
  final String displayName;
  final List<String> packageNameHints;
  final String? defaultLayoutId;
  final List<LayoutBinding> layouts;
  final List<InstrumentVariant> variants;
  final int sameKeyMinIntervalMs;
  final Set<String> featureFlags;

  InstrumentVariant? variantById(String id) {
    for (final variant in variants) {
      if (variant.id == id || variant.aliases.contains(id)) {
        return variant;
      }
    }
    return null;
  }

  LayoutBinding? layoutById(String id) {
    for (final layout in layouts) {
      if (layout.layoutId == id) {
        return layout;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'displayName': displayName,
      'packageNameHints': packageNameHints,
      'defaultLayoutId': defaultLayoutId,
      'sameKeyMinIntervalMs': sameKeyMinIntervalMs,
      'featureFlags': featureFlags.toList(),
      'layouts': layouts.map((layout) => layout.toJson()).toList(),
      'variants': variants.map((variant) => variant.toJson()).toList(),
    };
  }
}

class CalibrationKey {
  const CalibrationKey({
    required this.profileId,
    required this.layoutId,
    required this.deviceId,
    required this.orientation,
  });

  final String profileId;
  final String layoutId;
  final String deviceId;
  final String orientation;

  String get fileStem =>
      '$profileId'
      '__$layoutId'
      '__$orientation';
}

class Calibration {
  const Calibration({
    required this.key,
    required this.leftTopPx,
    required this.rightBottomPx,
    required this.capturedAt,
    this.viewportPx,
    this.metadata = const {},
  });

  final CalibrationKey key;
  final (double x, double y) leftTopPx;
  final (double x, double y) rightBottomPx;
  final ({double left, double top, double right, double bottom})? viewportPx;
  final DateTime capturedAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': key.profileId,
      'layoutId': key.layoutId,
      'deviceId': key.deviceId,
      'orientation': key.orientation,
      'leftTop': <double>[leftTopPx.$1, leftTopPx.$2],
      'rightBottom': <double>[rightBottomPx.$1, rightBottomPx.$2],
      'viewport': viewportPx == null
          ? null
          : <double>[
              viewportPx!.left,
              viewportPx!.top,
              viewportPx!.right,
              viewportPx!.bottom,
            ],
      'capturedAt': capturedAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}
