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
    _validateSimultaneousTouchCapacity(
      plan.actions,
      context.constraints.maxSimultaneousTouches,
    );

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
      totalDurationMs: _resolveTotalDurationMs(plan.totalDurationMs, actions),
    );
  }

  ExecutablePlan _compileOverlayHints(
    SemanticPlan plan,
    BackendContext context,
  ) {
    final actions = <ExecutableAction>[
      for (final action in plan.actions)
        ExecutableAction(
          atMs: action.atMs,
          durationMs: action.durationMs,
          kind: ExecutableActionKind.overlayHint,
          payload: <String, Object?>{
            'keyIds': action.keyIds,
            if (action.durationMsByKeyId.isNotEmpty)
              'durationMsByKeyId': action.durationMsByKeyId,
            'backendId': context.constraints.backendId,
            'supportsHold': context.constraints.supportsHold,
          },
        ),
    ];

    return ExecutablePlan(
      backendId: context.constraints.backendId,
      actions: actions,
      totalDurationMs: _resolveTotalDurationMs(plan.totalDurationMs, actions),
    );
  }

  int _resolveTotalDurationMs(
    int semanticTotalDurationMs,
    List<ExecutableAction> actions,
  ) {
    var totalDurationMs = semanticTotalDurationMs;
    for (final action in actions) {
      final endMs = action.atMs + action.durationMs;
      if (endMs > totalDurationMs) {
        totalDurationMs = endMs;
      }
    }
    return totalDurationMs;
  }

  void _validateSimultaneousTouchCapacity(
    List<SemanticAction> actions,
    int maxTouches,
  ) {
    final keyIdsByStartMs = <int, Set<String>>{};
    for (final action in actions) {
      final keyIds = keyIdsByStartMs.putIfAbsent(action.atMs, () => <String>{});
      for (final keyId in action.keyIds) {
        if (!keyIds.add(keyId)) {
          throw StateError('Duplicate key $keyId at ${action.atMs}ms.');
        }
      }
    }
    for (final entry in keyIdsByStartMs.entries) {
      if (entry.value.length > maxTouches) {
        throw StateError(
          'Action at ${entry.key}ms requires ${entry.value.length} '
          'simultaneous touches, but the backend supports $maxTouches.',
        );
      }
    }
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

    final notes =
        <_BatchKey>[
          for (final action in actions)
            for (final keyId in action.keyIds)
              _gestureBatchKey(
                action: action,
                keyId: keyId,
                constraints: constraints,
              ),
        ]..sort((a, b) {
          final timeOrder = a.atMs.compareTo(b.atMs);
          return timeOrder != 0 ? timeOrder : a.keyId.compareTo(b.keyId);
        });

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
        final sameStartKeys = currentGroup
            .where((key) => key.atMs == note.atMs)
            .toList();
        if (sameStartKeys.isNotEmpty) {
          currentGroup.removeWhere((key) => key.atMs == note.atMs);
        }
        if (currentGroup.isNotEmpty) {
          _truncateGroupToNextStart(
            currentGroup,
            note.atMs,
            constraints.marginDurationMs,
          );
          groups.add(currentGroup);
        }
        currentGroup = <_BatchKey>[...sameStartKeys, note];
        currentGroupEndMs = _groupEndMs(currentGroup);
        continue;
      }

      _truncateSameKeyOverlap(currentGroup, note, constraints.marginDurationMs);
      _avoidHeadTailConnections(
        currentGroup,
        note.atMs,
        constraints.marginDurationMs,
      );

      currentGroup.add(note);
      currentGroupEndMs = _groupEndMs(currentGroup);
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
      batches.add(_ActionBatch(atMs: filtered.first.atMs, keys: filtered));
    }
    return batches;
  }

  int _groupEndMs(List<_BatchKey> group) {
    return group
        .map((key) => key.atMs + key.durationMs)
        .reduce((a, b) => a > b ? a : b);
  }

  _BatchKey _gestureBatchKey({
    required SemanticAction action,
    required String keyId,
    required BackendConstraints constraints,
  }) {
    final requestedDurationMs = action.durationMsForKey(keyId);
    final isFallbackTap =
        requestedDurationMs == null ||
        requestedDurationMs <= constraints.pressDurationMs;
    var durationMs = requestedDurationMs ?? 0;
    if (durationMs < constraints.pressDurationMs) {
      durationMs = constraints.pressDurationMs;
    }
    if (durationMs > constraints.maxGestureDurationMs) {
      durationMs = constraints.maxGestureDurationMs;
    }
    return _BatchKey(
      keyId: keyId,
      atMs: action.atMs,
      durationMs: durationMs,
      isFallbackTap: isFallbackTap,
    );
  }

  void _truncateGroupToNextStart(
    List<_BatchKey> group,
    int nextStartMs,
    int marginDurationMs,
  ) {
    for (var i = 0; i < group.length; i++) {
      if (group[i].atMs >= nextStartMs) {
        continue;
      }
      if (group[i].isFallbackTap) {
        continue;
      }
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
        group[i] = current.copyWith(
          durationMs: durationMs < 0 ? 0 : durationMs,
        );
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
      if (current.isFallbackTap || nextStartMs <= current.atMs) {
        continue;
      }
      final currentEndMs = current.atMs + current.durationMs;
      if ((currentEndMs - nextStartMs).abs() < marginDurationMs) {
        final durationMs = nextStartMs - current.atMs - marginDurationMs;
        group[i] = current.copyWith(
          durationMs: durationMs < 0 ? 0 : durationMs,
        );
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
    this.isFallbackTap = false,
  });

  final String keyId;
  final int atMs;
  final int durationMs;
  final bool isFallbackTap;

  _BatchKey copyWith({int? durationMs}) {
    return _BatchKey(
      keyId: keyId,
      atMs: atMs,
      durationMs: durationMs ?? this.durationMs,
      isFallbackTap: isFallbackTap,
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
            durationMs: action.durationMsForKey(keyId) ?? 0,
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
        return null;
      }
      if (mergedKeys.length >= maxTouches) {
        return null;
      }
      mergedKeys.add(
        _BatchKey(
          keyId: keyId,
          atMs: action.atMs,
          durationMs: action.durationMsForKey(keyId) ?? 0,
        ),
      );
      existingIds.add(keyId);
    }
    return _ActionBatch(atMs: atMs, keys: mergedKeys);
  }
}
