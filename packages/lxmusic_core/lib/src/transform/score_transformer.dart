import '../domain/score.dart';

class TransformContext {
  const TransformContext({this.mergeTracks = true});

  final bool mergeTracks;
}

class ScoreTransformer {
  const ScoreTransformer();

  Score transform(Score score, TransformContext context) {
    if (!context.mergeTracks || score.tracks.length <= 1) {
      return score;
    }

    final mergedNotes = <NoteEvent>[
      for (final track in score.tracks) ...track.notes,
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));

    // MVP 先稳定把多音轨压成单音轨，后续再补更多 pass。
    return score.copyWith(
      tracks: <Track>[Track(name: 'Merged', channel: 0, notes: mergedNotes)],
    );
  }
}
