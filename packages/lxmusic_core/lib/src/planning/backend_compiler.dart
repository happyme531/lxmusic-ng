import '../domain/game_profile.dart';
import '../domain/executable_plan.dart';
import '../domain/semantic_plan.dart';
import 'execution_context.dart';

class BackendCompiler {
  const BackendCompiler();

  ExecutablePlan compile(SemanticPlan plan, BackendContext context) {
    if (context.calibration == null || context.layout == null) {
      return _compileOverlayHints(plan, context);
    }

    final preferredKind = _resolvePreferredActionKind(context);
    if (preferredKind == null) {
      return _compileOverlayHints(plan, context);
    }

    final actions = <ExecutableAction>[];
    final batches = preferredKind == ExecutableActionKind.touchGesture
        ? _batchGestureActions(plan.actions, context.constraints)
        : _batchActions(plan.actions, context.constraints);

    for (final batch in batches) {
      final payload = _buildPayload(
        batch: batch,
        context: context,
        kind: preferredKind,
      );
      if (payload == null) {
        continue;
      }
      actions.add(
        ExecutableAction(
          atMs: batch.atMs,
          durationMs: payload.durationMs,
          kind: preferredKind,
          payload: payload.payload,
        ),
      );
    }

    return ExecutablePlan(
      backendId: context.constraints.backendId,
      actions: actions,
      totalDurationMs: plan.totalDurationMs,
    );
  }

  ExecutablePlan _compileOverlayHints(SemanticPlan plan, BackendContext context) {
    final actions = <ExecutableAction>[
      for (final action in plan.actions)
        ExecutableAction(
          atMs: action.atMs,
          durationMs: action.durationMs,
          kind: ExecutableActionKind.overlayHint,
          payload: <String, Object?>{
            'keyIds': action.keyIds,
            'backendId': context.constraints.backendId,
            'supportsHold': context.constraints.supportsHold,
          },
        ),
    ];

    return ExecutablePlan(
      backendId: context.constraints.backendId,
      actions: actions,
      totalDurationMs: plan.totalDurationMs,
    );
  }

  ExecutableActionKind? _resolvePreferredActionKind(BackendContext context) {
    final supportsHoldOutput =
        context.constraints.supportsHold &&
        context.noteDurationMode != NoteDurationMode.none;
    if (supportsHoldOutput &&
        context.constraints.supportedKinds.contains(
          ExecutableActionKind.touchGesture.name,
        )) {
      return ExecutableActionKind.touchGesture;
    }
    if (context.constraints.supportedKinds.contains(
      ExecutableActionKind.touchPoints.name,
    )) {
      return ExecutableActionKind.touchPoints;
    }
    if (context.constraints.supportedKinds.contains(
      ExecutableActionKind.touchGesture.name,
    )) {
      return ExecutableActionKind.touchGesture;
    }
    return null;
  }

  List<_ActionBatch> _batchActions(
    List<SemanticAction> actions,
    BackendConstraints constraints,
  ) {
    if (actions.isEmpty) {
      return const <_ActionBatch>[];
    }

    final sorted = actions.toList()..sort((a, b) => a.atMs.compareTo(b.atMs));
    final batches = <_ActionBatch>[];
    var current = _ActionBatch.fromAction(sorted.first);

    for (final action in sorted.skip(1)) {
      final merged = current.tryMerge(
        action,
        windowMs: constraints.gestureBatchWindowMs,
        maxTouches: constraints.maxSimultaneousTouches,
      );
      if (merged != null) {
        current = merged;
      } else {
        batches.add(current);
        current = _ActionBatch.fromAction(action);
      }
    }
    batches.add(current);
    return batches;
  }

  List<_ActionBatch> _batchGestureActions(
    List<SemanticAction> actions,
    BackendConstraints constraints,
  ) {
    if (actions.isEmpty) {
      return const <_ActionBatch>[];
    }

    final notes = <_BatchKey>[
      for (final action in actions)
        for (final keyId in action.keyIds)
          _BatchKey(
            keyId: keyId,
            atMs: action.atMs,
            durationMs: action.durationMs > constraints.maxGestureDurationMs
                ? constraints.maxGestureDurationMs
                : action.durationMs,
          ),
    ]..sort((a, b) => a.atMs.compareTo(b.atMs));

    final groups = <List<_BatchKey>>[];
    var currentGroup = <_BatchKey>[];
    var currentGroupEndMs = 0;
    final maxGestureSize = constraints.maxSimultaneousTouches;
    final maxGestureSizeMid = (maxGestureSize * 2 / 3).ceil();
    final maxGestureSizeLow = (maxGestureSize / 3).ceil();
    const epsMid = 1;

    for (final note in notes) {
      final noteEndMs = note.atMs + note.durationMs;
      if (currentGroup.isEmpty) {
        currentGroup = <_BatchKey>[note];
        currentGroupEndMs = noteEndMs;
        continue;
      }

      final shouldSplit =
          currentGroup.length >= maxGestureSize ||
          (currentGroup.length < maxGestureSizeLow &&
              note.atMs - currentGroupEndMs > constraints.marginDurationMs) ||
          (currentGroup.length > maxGestureSizeMid &&
              note.atMs - currentGroupEndMs > -constraints.marginDurationMs) ||
          (currentGroup.length >= maxGestureSizeLow &&
              currentGroup.length <= maxGestureSizeMid &&
              note.atMs - currentGroupEndMs > epsMid);

      if (shouldSplit) {
        _truncateGroupToNextStart(
          currentGroup,
          note.atMs,
          constraints.marginDurationMs,
        );
        groups.add(currentGroup);
        currentGroup = <_BatchKey>[note];
        currentGroupEndMs = noteEndMs;
        continue;
      }

      _truncateSameKeyOverlap(
        currentGroup,
        note,
        constraints.marginDurationMs,
      );
      _avoidHeadTailConnections(
        currentGroup,
        note.atMs,
        constraints.marginDurationMs,
      );

      currentGroup.add(note);
      if (noteEndMs > currentGroupEndMs) {
        currentGroupEndMs = noteEndMs;
      }
    }

    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    final batches = <_ActionBatch>[];
    for (final group in groups) {
      final filtered = group
          .where((note) => note.durationMs >= constraints.pressDurationMs)
          .toList();
      if (filtered.isEmpty) {
        continue;
      }
      batches.add(
        _ActionBatch(
          atMs: filtered.first.atMs,
          keys: filtered,
        ),
      );
    }
    return batches;
  }

  void _truncateGroupToNextStart(
    List<_BatchKey> group,
    int nextStartMs,
    int marginDurationMs,
  ) {
    for (var i = 0; i < group.length; i++) {
      var durationMs = group[i].durationMs;
      final endMs = group[i].atMs + durationMs;
      if (endMs > nextStartMs) {
        durationMs = nextStartMs - group[i].atMs;
      }
      if ((group[i].atMs + durationMs - nextStartMs).abs() < marginDurationMs) {
        durationMs = nextStartMs - group[i].atMs - marginDurationMs;
      }
      group[i] = group[i].copyWith(durationMs: durationMs < 0 ? 0 : durationMs);
    }
  }

  void _truncateSameKeyOverlap(
    List<_BatchKey> group,
    _BatchKey incoming,
    int marginDurationMs,
  ) {
    for (var i = 0; i < group.length; i++) {
      final current = group[i];
      if (current.keyId != incoming.keyId) {
        continue;
      }
      final currentEndMs = current.atMs + current.durationMs;
      if (currentEndMs > incoming.atMs) {
        final durationMs = incoming.atMs - current.atMs - marginDurationMs;
        group[i] = current.copyWith(durationMs: durationMs < 0 ? 0 : durationMs);
      }
    }
  }

  void _avoidHeadTailConnections(
    List<_BatchKey> group,
    int nextStartMs,
    int marginDurationMs,
  ) {
    for (var i = 0; i < group.length; i++) {
      final current = group[i];
      final currentEndMs = current.atMs + current.durationMs;
      if ((currentEndMs - nextStartMs).abs() < marginDurationMs) {
        final durationMs = nextStartMs - current.atMs - marginDurationMs;
        group[i] = current.copyWith(durationMs: durationMs < 0 ? 0 : durationMs);
      }
    }
  }

  _CompiledPayload? _buildPayload({
    required _ActionBatch batch,
    required BackendContext context,
    required ExecutableActionKind kind,
  }) {
    final layout = context.layout!;
    final calibration = context.calibration!;
    final left = calibration.leftTopPx.$1;
    final top = calibration.leftTopPx.$2;
    final width = calibration.rightBottomPx.$1 - left;
    final height = calibration.rightBottomPx.$2 - top;
    final points = <Map<String, Object?>>[];
    var durationMs = 0;

    for (final key in batch.keys) {
      final definition = _findKey(layout, key.keyId);
      if (definition == null) {
        continue;
      }
      final x = left + width * definition.normX;
      final y = top + height * definition.normY;
      final point = <String, Object?>{
        'keyId': key.keyId,
        'x': x,
        'y': y,
        'delayMs': key.atMs - batch.atMs,
      };
      if (kind == ExecutableActionKind.touchGesture) {
        point['durationMs'] = key.durationMs;
        final endMs = key.atMs - batch.atMs + key.durationMs;
        if (endMs > durationMs) {
          durationMs = endMs;
        }
      }
      points.add(point);
    }

    if (points.isEmpty) {
      return null;
    }
    if (kind != ExecutableActionKind.touchGesture) {
      durationMs = 0;
    }

    return _CompiledPayload(
      durationMs: durationMs,
      payload: <String, Object?>{
        'backendId': context.constraints.backendId,
        'points': points,
        'calibrated': true,
      },
    );
  }

  KeyDefinition? _findKey(KeyLayout layout, String keyId) {
    for (final key in layout.keys) {
      if (key.id == keyId) {
        return key;
      }
    }
    return null;
  }
}

class _CompiledPayload {
  const _CompiledPayload({required this.durationMs, required this.payload});

  final int durationMs;
  final Map<String, Object?> payload;
}

class _BatchKey {
  const _BatchKey({
    required this.keyId,
    required this.atMs,
    required this.durationMs,
  });

  final String keyId;
  final int atMs;
  final int durationMs;

  _BatchKey copyWith({int? durationMs}) {
    return _BatchKey(
      keyId: keyId,
      atMs: atMs,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class _ActionBatch {
  const _ActionBatch({required this.atMs, required this.keys});

  factory _ActionBatch.fromAction(SemanticAction action) {
    return _ActionBatch(
      atMs: action.atMs,
      keys: <_BatchKey>[
        for (final keyId in action.keyIds)
          _BatchKey(
            keyId: keyId,
            atMs: action.atMs,
            durationMs: action.durationMs,
          ),
      ],
    );
  }

  final int atMs;
  final List<_BatchKey> keys;

  _ActionBatch? tryMerge(
    SemanticAction action, {
    required int windowMs,
    required int maxTouches,
  }) {
    if (action.atMs - atMs >= windowMs) {
      return null;
    }

    final mergedKeys = <_BatchKey>[...keys];
    final existingIds = <String>{for (final key in keys) key.keyId};
    for (final keyId in action.keyIds) {
      if (existingIds.contains(keyId)) {
        continue;
      }
      if (mergedKeys.length >= maxTouches) {
        return null;
      }
      mergedKeys.add(
        _BatchKey(keyId: keyId, atMs: action.atMs, durationMs: action.durationMs),
      );
      existingIds.add(keyId);
    }
    return _ActionBatch(atMs: atMs, keys: mergedKeys);
  }
}
