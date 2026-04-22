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
  });

  final int atMs;
  final int durationMs;
  final List<String> keyIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'atMs': atMs,
      'durationMs': durationMs,
      'keyIds': keyIds,
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
