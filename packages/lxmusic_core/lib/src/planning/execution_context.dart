import '../domain/game_profile.dart';

class PlanningContext {
  const PlanningContext({
    required this.profile,
    required this.layout,
    required this.variant,
  });

  final GameProfile profile;
  final KeyLayout layout;
  final InstrumentVariant variant;
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
  });

  final String backendId;
  final bool supportsHold;
  final int maxSimultaneousTouches;
  final int minTapGapMs;
  final int gestureBatchWindowMs;
  final Set<String> supportedKinds;
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
