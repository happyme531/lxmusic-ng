class PassStat {
  const PassStat({required this.name, this.values = const <String, Object?>{}});

  final String name;
  final Map<String, Object?> values;

  Map<String, Object?> toJson() {
    return <String, Object?>{'name': name, 'values': values};
  }
}

/// 管线整体音符数量变化（按每一步前后音符条数差累加「增加」「减少」）。
class NotePipelineSummary {
  const NotePipelineSummary({
    required this.inputNoteCount,
    required this.outputNoteCount,
    required this.pipelineNotesAdded,
    required this.pipelineNotesRemoved,
  });

  final int inputNoteCount;
  final int outputNoteCount;

  /// 各步中 `after - before` 为正时的增量之和。
  final int pipelineNotesAdded;

  /// 各步中 `before - after` 为正时的减量之和。
  final int pipelineNotesRemoved;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'inputNoteCount': inputNoteCount,
      'outputNoteCount': outputNoteCount,
      'pipelineNotesAdded': pipelineNotesAdded,
      'pipelineNotesRemoved': pipelineNotesRemoved,
    };
  }
}

class TransformReport {
  const TransformReport({
    this.stats = const <PassStat>[],
    this.warnings = const <String>[],
    this.noteSummary,
  });

  final List<PassStat> stats;
  final List<String> warnings;
  final NotePipelineSummary? noteSummary;
}
