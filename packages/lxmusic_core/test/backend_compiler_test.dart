import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const plan = SemanticPlan(
    profileId: 'demo',
    layoutId: 'layout',
    variantId: 'default',
    totalDurationMs: 500,
    actions: <SemanticAction>[
      SemanticAction(atMs: 100, durationMs: 80, keyIds: <String>['C4']),
      SemanticAction(atMs: 120, durationMs: 60, keyIds: <String>['E4']),
      SemanticAction(atMs: 220, durationMs: 40, keyIds: <String>['G4']),
    ],
  );

  const layout = KeyLayout(
    id: 'layout',
    algorithm: LayoutAlgorithm.explicit,
    keys: <KeyDefinition>[
      KeyDefinition(id: 'C4', pitch: 60, normX: 0.1, normY: 0.8),
      KeyDefinition(id: 'E4', pitch: 64, normX: 0.3, normY: 0.8),
      KeyDefinition(id: 'G4', pitch: 67, normX: 0.5, normY: 0.8),
    ],
    pitchToKeyId: <int, String>{60: 'C4', 64: 'E4', 67: 'G4'},
  );

  final calibration = Calibration(
    key: const CalibrationKey(
      profileId: 'demo',
      layoutId: 'layout',
      deviceId: 'device',
      orientation: 'portrait',
    ),
    leftTopPx: (10, 20),
    rightBottomPx: (110, 220),
    capturedAt: DateTime.utc(2026, 4, 12, 8, 0, 0),
  );

  test('compiles hold-capable actions into touch gestures', () {
    const holdPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 240,
      actions: <SemanticAction>[
        SemanticAction(atMs: 100, durationMs: 80, keyIds: <String>['C4']),
        SemanticAction(atMs: 120, durationMs: 60, keyIds: <String>['E4']),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      holdPlan,
      BackendContext(
        constraints: BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{'touchGesture', 'touchPoints', 'overlayHint'},
          marginDurationMs: 10,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(1));
    expect(executablePlan.actions.first.kind, ExecutableActionKind.touchGesture);
    expect(executablePlan.actions.first.atMs, 100);
    expect(executablePlan.actions.first.durationMs, 80);

    final points =
        executablePlan.actions.first.payload['points']! as List<Object?>;
    expect(points, hasLength(2));
    expect(points.first, <String, Object?>{
      'keyId': 'C4',
      'x': 20.0,
      'y': 180.0,
      'delayMs': 0,
      'durationMs': 80,
    });
    expect(points.last, <String, Object?>{
      'keyId': 'E4',
      'x': 40.0,
      'y': 180.0,
      'delayMs': 20,
      'durationMs': 60,
    });
  });

  test('compiles non-hold actions into touch points', () {
    final executablePlan = const BackendCompiler().compile(
      plan,
      BackendContext(
        constraints: BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{'touchGesture', 'touchPoints', 'overlayHint'},
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.none,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(executablePlan.actions.first.kind, ExecutableActionKind.touchPoints);
    expect(executablePlan.actions.first.durationMs, 0);
    expect(
      executablePlan.actions.first.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{'keyId': 'C4', 'x': 20.0, 'y': 180.0, 'delayMs': 0},
        <String, Object?>{'keyId': 'E4', 'x': 40.0, 'y': 180.0, 'delayMs': 20},
      ],
    );
  });

  test('falls back to overlay hints without calibration data', () {
    final executablePlan = const BackendCompiler().compile(
      plan,
      const BackendContext(
        constraints: BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{'touchGesture', 'touchPoints', 'overlayHint'},
        ),
      ),
    );

    expect(executablePlan.actions, hasLength(3));
    expect(executablePlan.actions.first.kind, ExecutableActionKind.overlayHint);
    expect(executablePlan.actions.first.payload['keyIds'], <String>['C4']);
  });

  test('truncates overlapping native-hold notes and splits distant groups', () {
    const holdPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 1000,
      actions: <SemanticAction>[
        SemanticAction(atMs: 100, durationMs: 300, keyIds: <String>['C4']),
        SemanticAction(atMs: 220, durationMs: 120, keyIds: <String>['C4']),
        SemanticAction(atMs: 700, durationMs: 80, keyIds: <String>['E4']),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      holdPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{'touchGesture', 'touchPoints', 'overlayHint'},
          marginDurationMs: 100,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(executablePlan.actions.first.kind, ExecutableActionKind.touchGesture);
    expect(
      executablePlan.actions.first.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 20,
        },
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 120,
          'durationMs': 120,
        },
      ],
    );
    expect(
      executablePlan.actions.last.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'E4',
          'x': 40.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 80,
        },
      ],
    );
  });
}
