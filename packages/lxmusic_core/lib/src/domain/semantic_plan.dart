class PlanWarning {
  const PlanWarning({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{'code': code, 'message': message};
  }
}

class SemanticAction {
  const SemanticAction({
    required this.atMs,
    required this.durationMs,
    required this.keyIds,
  }) : durationMsByKeyId = const <String, int?>{};

  const SemanticAction._({
    required this.atMs,
    required this.durationMs,
    required this.keyIds,
    required this.durationMsByKeyId,
  });

  factory SemanticAction.perKey({
    required int atMs,
    required Map<String, int?> durationMsByKeyId,
  }) {
    final normalizedDurationMsByKeyId = <String, int?>{};
    for (final entry in durationMsByKeyId.entries) {
      final durationMs = entry.value;
      normalizedDurationMsByKeyId[entry.key] =
          durationMs != null && durationMs < 0 ? 0 : durationMs;
    }

    final keyIds = normalizedDurationMsByKeyId.keys.toList()..sort();
    var durationMs = 0;
    var hasUnknownDuration = false;
    int? uniformDurationMs;
    var hasDifferentKnownDurations = false;

    for (final keyId in keyIds) {
      final keyDurationMs = normalizedDurationMsByKeyId[keyId];
      if (keyDurationMs == null) {
        hasUnknownDuration = true;
        continue;
      }
      if (keyDurationMs > durationMs) {
        durationMs = keyDurationMs;
      }
      if (uniformDurationMs == null) {
        uniformDurationMs = keyDurationMs;
      } else if (uniformDurationMs != keyDurationMs) {
        hasDifferentKnownDurations = true;
      }
    }

    final needsPerKeyDuration =
        hasUnknownDuration || hasDifferentKnownDurations;
    return SemanticAction._(
      atMs: atMs,
      durationMs: durationMs,
      keyIds: keyIds,
      durationMsByKeyId: needsPerKeyDuration
          ? <String, int?>{
              for (final keyId in keyIds)
                keyId: normalizedDurationMsByKeyId[keyId],
            }
          : const <String, int?>{},
    );
  }

  final int atMs;

  /// Maximum known duration across [keyIds], retained for compatibility.
  final int durationMs;
  final List<String> keyIds;

  /// Per-key durations when the action cannot be represented by [durationMs].
  ///
  /// A null value means the source note had no duration. When this map does
  /// not contain [keyId], consumers should fall back to [durationMs].
  final Map<String, int?> durationMsByKeyId;

  int? durationMsForKey(String keyId) {
    if (!keyIds.contains(keyId)) {
      return null;
    }
    if (durationMsByKeyId.containsKey(keyId)) {
      return durationMsByKeyId[keyId];
    }
    return durationMs;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'atMs': atMs,
      'durationMs': durationMs,
      'keyIds': keyIds,
      if (durationMsByKeyId.isNotEmpty) 'durationMsByKeyId': durationMsByKeyId,
    };
  }
}

class SemanticPlan {
  const SemanticPlan({
    required this.profileId,
    required this.layoutId,
    required this.variantId,
    required this.actions,
    required this.totalDurationMs,
    this.warnings = const [],
  });

  final String profileId;
  final String layoutId;
  final String variantId;
  final List<SemanticAction> actions;
  final int totalDurationMs;
  final List<PlanWarning> warnings;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'layoutId': layoutId,
      'variantId': variantId,
      'totalDurationMs': totalDurationMs,
      'actions': actions.map((action) => action.toJson()).toList(),
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
    };
  }
}
