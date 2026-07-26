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
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          marginDurationMs: 10,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(1));
    expect(
      executablePlan.actions.first.kind,
      ExecutableActionKind.touchGesture,
    );
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
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
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

  test('keeps repeated touch points in separate batches', () {
    const repeatedPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'default',
      totalDurationMs: 200,
      actions: <SemanticAction>[
        SemanticAction(atMs: 100, durationMs: 0, keyIds: <String>['C4']),
        SemanticAction(atMs: 120, durationMs: 0, keyIds: <String>['C4']),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      repeatedPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.none,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(executablePlan.actions.map((action) => action.atMs), <int>[
      100,
      120,
    ]);
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
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
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
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          marginDurationMs: 100,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(
      executablePlan.actions.first.kind,
      ExecutableActionKind.touchGesture,
    );
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

  test('recomputes the gesture group end after hold truncation', () {
    const truncatedPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 530,
      actions: <SemanticAction>[
        SemanticAction(atMs: 0, durationMs: 500, keyIds: <String>['C4']),
        SemanticAction(atMs: 300, durationMs: 100, keyIds: <String>['C4']),
        SemanticAction(atMs: 450, durationMs: 80, keyIds: <String>['E4']),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      truncatedPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          marginDurationMs: 100,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(executablePlan.actions.map((action) => action.atMs), <int>[0, 450]);
  });

  test('preserves a per-key chord with positive hold margins', () {
    final perKeyPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 100,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 100,
          durationMsByKeyId: <String, int?>{'C4': 80, 'E4': 400, 'G4': 2},
        ),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      perKeyPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          maxGestureDurationMs: 250,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(1));
    expect(executablePlan.actions.single.durationMs, 250);
    expect(executablePlan.totalDurationMs, 350);
    expect(
      executablePlan.actions.single.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 80,
        },
        <String, Object?>{
          'keyId': 'E4',
          'x': 40.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 250,
        },
        <String, Object?>{
          'keyId': 'G4',
          'x': 60.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 5,
        },
      ],
    );
  });

  test('materializes missing native-hold duration as a minimum tap', () {
    const variant = InstrumentVariant(
      id: 'hold',
      displayName: 'Hold',
      noteDurationMode: NoteDurationMode.nativeHold,
    );
    const profile = GameProfile(
      id: 'demo',
      displayName: 'Demo',
      packageNameHints: <String>[],
      defaultLayoutId: 'layout',
      layouts: <LayoutBinding>[
        LayoutBinding(layoutId: 'layout', isDefault: true),
      ],
      variants: <InstrumentVariant>[variant],
      sameKeyMinIntervalMs: 20,
    );
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 100),
            NoteEvent(pitch: 64, startMs: 100, durationMs: 300),
          ],
        ),
      ],
    );
    final mixedPlan = const PerformancePlanner().plan(
      score,
      const PlanningContext(profile: profile, layout: layout, variant: variant),
    );
    expect(mixedPlan.actions.single.durationMsByKeyId, <String, int?>{
      'C4': null,
      'E4': 300,
    });

    final executablePlan = const BackendCompiler().compile(
      mixedPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          marginDurationMs: 0,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(1));
    expect(
      executablePlan.actions.single.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 5,
        },
        <String, Object?>{
          'keyId': 'E4',
          'x': 40.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 300,
        },
      ],
    );
    expect(executablePlan.totalDurationMs, 400);
  });

  test('keeps nearby fallback taps from being truncated by hold margins', () {
    final tapPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 100,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 0,
          durationMsByKeyId: <String, int?>{'C4': 5},
        ),
        SemanticAction.perKey(
          atMs: 100,
          durationMsByKeyId: <String, int?>{'E4': null},
        ),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      tapPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(1));
    expect(
      executablePlan.actions.single.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 5,
        },
        <String, Object?>{
          'keyId': 'E4',
          'x': 40.0,
          'y': 180.0,
          'delayMs': 100,
          'durationMs': 5,
        },
      ],
    );
    expect(executablePlan.actions.single.durationMs, 105);
    expect(executablePlan.totalDurationMs, 105);
  });

  test('applies max gesture duration to each stroke, not the batch span', () {
    const delayedPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 0,
      actions: <SemanticAction>[
        SemanticAction(atMs: 0, durationMs: 400, keyIds: <String>['C4']),
        SemanticAction(atMs: 100, durationMs: 400, keyIds: <String>['E4']),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      delayedPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          maxGestureDurationMs: 250,
          marginDurationMs: 0,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions.single.durationMs, 350);
    expect(
      executablePlan.actions.single.payload['points'],
      <Map<String, Object?>>[
        <String, Object?>{
          'keyId': 'C4',
          'x': 20.0,
          'y': 180.0,
          'delayMs': 0,
          'durationMs': 250,
        },
        <String, Object?>{
          'keyId': 'E4',
          'x': 40.0,
          'y': 180.0,
          'delayMs': 100,
          'durationMs': 250,
        },
      ],
    );
  });

  test('keeps per-key duration metadata in overlay fallback', () {
    final perKeyPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 100,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 100,
          durationMsByKeyId: <String, int?>{'C4': 100, 'E4': 400},
        ),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      perKeyPlan,
      const BackendContext(
        constraints: BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
        ),
      ),
    );

    expect(executablePlan.actions.single.durationMs, 400);
    expect(executablePlan.totalDurationMs, 500);
    expect(
      executablePlan.actions.single.payload['durationMsByKeyId'],
      <String, int?>{'C4': 100, 'E4': 400},
    );
  });

  test('carries same-start keys into a capacity-created gesture group', () {
    const capacityLayout = KeyLayout(
      id: 'capacity',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'K1', normX: 0.1, normY: 0.5),
        KeyDefinition(id: 'K2', normX: 0.2, normY: 0.5),
        KeyDefinition(id: 'K3', normX: 0.3, normY: 0.5),
        KeyDefinition(id: 'K4', normX: 0.4, normY: 0.5),
        KeyDefinition(id: 'K5', normX: 0.5, normY: 0.5),
        KeyDefinition(id: 'K6', normX: 0.6, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{},
    );
    const capacityPlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'capacity',
      variantId: 'hold',
      totalDurationMs: 300,
      actions: <SemanticAction>[
        SemanticAction(atMs: 0, durationMs: 300, keyIds: <String>['K1']),
        SemanticAction(
          atMs: 100,
          durationMs: 80,
          keyIds: <String>['K2', 'K3', 'K4'],
        ),
      ],
    );

    final executablePlan = const BackendCompiler().compile(
      capacityPlan,
      BackendContext(
        constraints: const BackendConstraints(
          backendId: 'preview',
          supportsHold: true,
          maxSimultaneousTouches: 3,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
          marginDurationMs: 0,
        ),
        calibration: calibration,
        layout: capacityLayout,
        noteDurationMode: NoteDurationMode.nativeHold,
      ),
    );

    expect(executablePlan.actions, hasLength(2));
    expect(executablePlan.actions.map((action) => action.atMs), <int>[0, 100]);
    expect(
      executablePlan.actions.map(
        (action) => (action.payload['points']! as List<Object?>).length,
      ),
      <int>[1, 3],
    );
  });

  test('rejects a chord wider than the backend touch capacity', () {
    const capacityLayout = KeyLayout(
      id: 'capacity',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'K1', normX: 0.1, normY: 0.5),
        KeyDefinition(id: 'K2', normX: 0.2, normY: 0.5),
        KeyDefinition(id: 'K3', normX: 0.3, normY: 0.5),
        KeyDefinition(id: 'K4', normX: 0.4, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{},
    );
    const tooWidePlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'capacity',
      variantId: 'hold',
      totalDurationMs: 80,
      actions: <SemanticAction>[
        SemanticAction(
          atMs: 0,
          durationMs: 80,
          keyIds: <String>['K1', 'K2', 'K3', 'K4'],
        ),
      ],
    );

    expect(
      () => const BackendCompiler().compile(
        tooWidePlan,
        BackendContext(
          constraints: const BackendConstraints(
            backendId: 'preview',
            supportsHold: true,
            maxSimultaneousTouches: 3,
            minTapGapMs: 8,
            gestureBatchWindowMs: 32,
            supportedKinds: <String>{
              'touchGesture',
              'touchPoints',
              'overlayHint',
            },
            marginDurationMs: 0,
          ),
          calibration: calibration,
          layout: capacityLayout,
          noteDurationMode: NoteDurationMode.nativeHold,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('requires 4 simultaneous touches'),
        ),
      ),
    );
  });

  test('rejects duplicate keys at the same timestamp', () {
    const duplicatePlan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 80,
      actions: <SemanticAction>[
        SemanticAction(atMs: 0, durationMs: 80, keyIds: <String>['C4', 'C4']),
      ],
    );

    expect(
      () => const BackendCompiler().compile(
        duplicatePlan,
        BackendContext(
          constraints: const BackendConstraints(
            backendId: 'preview',
            supportsHold: true,
            maxSimultaneousTouches: 3,
            minTapGapMs: 8,
            gestureBatchWindowMs: 32,
            supportedKinds: <String>{
              'touchGesture',
              'touchPoints',
              'overlayHint',
            },
          ),
          calibration: calibration,
          layout: layout,
          noteDurationMode: NoteDurationMode.nativeHold,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Duplicate key C4 at 0ms'),
        ),
      ),
    );
  });
}
