enum ExecutableActionKind {
  touchGesture,
  touchPoints,
  midiMessage,
  hidReport,
  overlayHint,
}

class ExecutableAction {
  const ExecutableAction({
    required this.atMs,
    required this.durationMs,
    required this.kind,
    required this.payload,
  });

  final int atMs;
  final int durationMs;
  final ExecutableActionKind kind;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'atMs': atMs,
      'durationMs': durationMs,
      'kind': kind.name,
      'payload': payload,
    };
  }
}

class ExecutablePlan {
  const ExecutablePlan({
    required this.backendId,
    required this.actions,
    required this.totalDurationMs,
  });

  final String backendId;
  final List<ExecutableAction> actions;
  final int totalDurationMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendId': backendId,
      'totalDurationMs': totalDurationMs,
      'actions': actions.map((action) => action.toJson()).toList(),
    };
  }
}
