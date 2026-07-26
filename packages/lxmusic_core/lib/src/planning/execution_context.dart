import '../domain/game_profile.dart';

class PlanningContext {
  const PlanningContext({
    required this.profile,
    required this.layout,
    required this.variant,
    this.customPitchToKeyId,
  });

  final GameProfile profile;
  final KeyLayout layout;
  final InstrumentVariant variant;

  /// Authoritative custom map resolved from the current pipeline config.
  ///
  /// When null, planning derives keys from [variant] and [layout]. Note attrs
  /// are never allowed to opt into custom behavior on their own.
  final Map<int, String>? customPitchToKeyId;
}

class BackendConstraints {
  const BackendConstraints({
    required this.backendId,
    required this.supportsHold,
    required this.maxSimultaneousTouches,
    required this.minTapGapMs,
    required this.gestureBatchWindowMs,
    required this.supportedKinds,
    this.maxGestureDurationMs = 10000,
    this.marginDurationMs = 100,
    this.pressDurationMs = 5,
    this.metadata = const {},
  }) : assert(maxSimultaneousTouches > 0),
       assert(minTapGapMs >= 0),
       assert(gestureBatchWindowMs >= 0),
       assert(maxGestureDurationMs > 0),
       assert(marginDurationMs >= 0),
       assert(pressDurationMs > 0),
       assert(pressDurationMs <= maxGestureDurationMs);

  final String backendId;
  final bool supportsHold;
  final int maxSimultaneousTouches;
  final int minTapGapMs;
  final int gestureBatchWindowMs;
  final Set<String> supportedKinds;

  /// Maximum duration of one touch stroke, not the span of a batched action.
  final int maxGestureDurationMs;
  final int marginDurationMs;
  final int pressDurationMs;
  final Map<String, Object?> metadata;
}

class BackendContext {
  const BackendContext({
    required this.constraints,
    this.calibration,
    this.layout,
    this.noteDurationMode = NoteDurationMode.none,
  });

  final BackendConstraints constraints;
  final Calibration? calibration;
  final KeyLayout? layout;
  final NoteDurationMode noteDurationMode;
}
