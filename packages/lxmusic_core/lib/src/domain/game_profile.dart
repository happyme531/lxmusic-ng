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

  /// Returns the pitch actually produced by a physical layout key.
  ///
  /// [replacePitchMap] is keyed by the base pitch declared by the layout. It
  /// does not rewrite an incoming score pitch.
  int effectivePitchForLayoutPitch(int layoutPitch) {
    return replacePitchMap[layoutPitch] ?? layoutPitch;
  }

  /// Backwards-compatible alias for [effectivePitchForLayoutPitch].
  int mapPitch(int pitch) => effectivePitchForLayoutPitch(pitch);

  /// Builds the playable-pitch to physical-key map for [layout].
  Map<int, String> playablePitchToKeyId(KeyLayout layout) {
    final result = <int, String>{};
    final layoutPitches = layout.pitchToKeyId.keys.toList()..sort();
    for (final layoutPitch in layoutPitches) {
      final effectivePitch = effectivePitchForLayoutPitch(layoutPitch);
      if (!supportsPitch(effectivePitch)) {
        continue;
      }
      if (result.containsKey(effectivePitch)) {
        throw StateError(
          'Variant $id maps multiple keys in layout ${layout.id} to pitch '
          '$effectivePitch.',
        );
      }
      result[effectivePitch] = layout.pitchToKeyId[layoutPitch]!;
    }
    return Map<int, String>.unmodifiable(result);
  }

  /// Returns the base layout pitches whose physical keys are available to
  /// this variant.
  ///
  /// These pitches describe the physical keyboard bounds used for octave
  /// wrapping. They can differ from the effective pitches produced by those
  /// keys when [replacePitchMap] is non-empty.
  List<int> playableLayoutPitches(KeyLayout layout) {
    final playablePitchToKey = playablePitchToKeyId(layout);
    final result = <int>[];
    final layoutPitches = layout.pitchToKeyId.keys.toList()..sort();
    for (final layoutPitch in layoutPitches) {
      final effectivePitch = effectivePitchForLayoutPitch(layoutPitch);
      if (playablePitchToKey[effectivePitch] ==
          layout.pitchToKeyId[layoutPitch]) {
        result.add(layoutPitch);
      }
    }
    return List<int>.unmodifiable(result);
  }

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
  });

  final String profileId;
  final String layoutId;
  final String deviceId;

  String get fileStem => '${profileId}__$layoutId';

  String get storageKey => '$deviceId/$profileId/$layoutId';

  factory CalibrationKey.fromJson(Map<String, Object?> json) {
    final key = CalibrationKey(
      profileId: _calibrationString(json, 'profileId'),
      layoutId: _calibrationString(json, 'layoutId'),
      deviceId: _calibrationString(json, 'deviceId'),
    );
    key.validate();
    return key;
  }

  void validate() {
    if (profileId.trim().isEmpty ||
        layoutId.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      throw const CalibrationFormatException(
        'invalid_key',
        'Calibration key fields must not be empty.',
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'layoutId': layoutId,
      'deviceId': deviceId,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is CalibrationKey &&
        other.profileId == profileId &&
        other.layoutId == layoutId &&
        other.deviceId == deviceId;
  }

  @override
  int get hashCode => Object.hash(profileId, layoutId, deviceId);
}

class Calibration {
  const Calibration({
    required this.key,
    required this.orientation,
    required this.leftTopPx,
    required this.rightBottomPx,
    required this.capturedAt,
    this.viewportPx,
    this.metadata = const {},
  });

  final CalibrationKey key;
  final String orientation;
  final (double x, double y) leftTopPx;
  final (double x, double y) rightBottomPx;
  final ({double left, double top, double right, double bottom})? viewportPx;
  final DateTime capturedAt;
  final Map<String, Object?> metadata;

  static const int schemaVersion = 1;
  static const Set<String> supportedOrientations = <String>{
    'portrait',
    'landscape',
  };

  factory Calibration.fromJson(
    Map<String, Object?> json, {
    CalibrationKey? fallbackKey,
  }) {
    final rawVersion = json['schemaVersion'];
    if (rawVersion != null && rawVersion != schemaVersion) {
      throw CalibrationFormatException(
        'unsupported_schema',
        'Unsupported calibration schema version "$rawVersion".',
      );
    }

    final parsedKey = _hasCalibrationKeyFields(json)
        ? CalibrationKey.fromJson(json)
        : fallbackKey;
    if (parsedKey == null) {
      throw const CalibrationFormatException(
        'missing_key',
        'Calibration key fields are missing.',
      );
    }
    parsedKey.validate();
    if (fallbackKey != null && parsedKey != fallbackKey) {
      throw const CalibrationFormatException(
        'key_mismatch',
        'Calibration key does not match its storage location.',
      );
    }

    final capturedAtText = _calibrationString(json, 'capturedAt');
    final capturedAt = DateTime.tryParse(capturedAtText);
    if (capturedAt == null) {
      throw CalibrationFormatException(
        'invalid_captured_at',
        'Invalid calibration capturedAt "$capturedAtText".',
      );
    }
    final rawMetadata = json['metadata'];
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const CalibrationFormatException(
        'invalid_metadata',
        'Calibration metadata must be an object.',
      );
    }

    final calibration = Calibration(
      key: parsedKey,
      orientation: _calibrationString(json, 'orientation'),
      leftTopPx: _calibrationPoint(json, 'leftTop'),
      rightBottomPx: _calibrationPoint(json, 'rightBottom'),
      viewportPx: _calibrationViewport(json['viewport']),
      capturedAt: capturedAt,
      metadata: rawMetadata == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              (rawMetadata as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
    );
    calibration.validate();
    return calibration;
  }

  void validate() {
    key.validate();
    if (!supportedOrientations.contains(orientation)) {
      throw CalibrationFormatException(
        'invalid_orientation',
        'Unsupported calibration orientation "$orientation".',
      );
    }
    final values = <double>[
      leftTopPx.$1,
      leftTopPx.$2,
      rightBottomPx.$1,
      rightBottomPx.$2,
      if (viewportPx != null) ...<double>[
        viewportPx!.left,
        viewportPx!.top,
        viewportPx!.right,
        viewportPx!.bottom,
      ],
    ];
    if (values.any((value) => !value.isFinite)) {
      throw const CalibrationFormatException(
        'non_finite_coordinate',
        'Calibration coordinates must be finite numbers.',
      );
    }
    if (leftTopPx.$1 >= rightBottomPx.$1 || leftTopPx.$2 >= rightBottomPx.$2) {
      throw const CalibrationFormatException(
        'invalid_rectangle',
        'Calibration rectangle must have positive width and height.',
      );
    }
    final viewport = viewportPx;
    if (viewport == null) {
      return;
    }
    if (viewport.left >= viewport.right || viewport.top >= viewport.bottom) {
      throw const CalibrationFormatException(
        'invalid_viewport',
        'Calibration viewport must have positive width and height.',
      );
    }
    if (leftTopPx.$1 < viewport.left ||
        leftTopPx.$2 < viewport.top ||
        rightBottomPx.$1 > viewport.right ||
        rightBottomPx.$2 > viewport.bottom) {
      throw const CalibrationFormatException(
        'outside_viewport',
        'Calibration rectangle must be inside the viewport.',
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      ...key.toJson(),
      'orientation': orientation,
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

class CalibrationFormatException extends FormatException {
  const CalibrationFormatException(this.code, String message) : super(message);

  final String code;

  @override
  String toString() => 'CalibrationFormatException($code): $message';
}

bool _hasCalibrationKeyFields(Map<String, Object?> json) {
  return json.containsKey('profileId') ||
      json.containsKey('layoutId') ||
      json.containsKey('deviceId');
}

String _calibrationString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw CalibrationFormatException(
      'invalid_$key',
      'Calibration field "$key" must be a non-empty string.',
    );
  }
  return value;
}

(double, double) _calibrationPoint(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.length != 2) {
    throw CalibrationFormatException(
      'invalid_$key',
      'Calibration field "$key" must contain exactly two numbers.',
    );
  }
  final x = value[0];
  final y = value[1];
  if (x is! num || y is! num) {
    throw CalibrationFormatException(
      'invalid_$key',
      'Calibration field "$key" must contain exactly two numbers.',
    );
  }
  return (x.toDouble(), y.toDouble());
}

({double left, double top, double right, double bottom})? _calibrationViewport(
  Object? value,
) {
  if (value == null) {
    return null;
  }
  if (value is! List ||
      value.length != 4 ||
      value.any((item) => item is! num)) {
    throw const CalibrationFormatException(
      'invalid_viewport',
      'Calibration viewport must contain exactly four numbers.',
    );
  }
  return (
    left: (value[0] as num).toDouble(),
    top: (value[1] as num).toDouble(),
    right: (value[2] as num).toDouble(),
    bottom: (value[3] as num).toDouble(),
  );
}
