import 'dart:convert';
import 'dart:typed_data';

import '../../domain/score.dart';
import '../music_text_decoder.dart';
import '../score_parser.dart';

class ToneJsJsonScoreParser implements ScoreParser {
  @override
  String get formatId => 'tonejs-json';

  @override
  Score parse(Uint8List bytes) {
    final decoded = jsonDecode(decodeMusicText(bytes));
    if (decoded is! Map) {
      throw const FormatException('Tone.js JSON 根节点必须是对象');
    }
    final json = Map<String, Object?>.from(decoded);
    final trackList = (json['tracks'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<Object?, Object?>>();

    final tracks = <Track>[];
    for (var index = 0; index < trackList.length; index++) {
      final trackJson = Map<String, Object?>.from(trackList[index]);
      final notes =
          (trackJson['notes'] as List<Object?>? ?? const <Object?>[])
              .cast<Map<Object?, Object?>>()
              .map((noteJson) {
                final note = Map<String, Object?>.from(noteJson);
                final timeSeconds = (note['time'] as num?)?.toDouble() ?? 0.0;
                final durationSeconds = (note['duration'] as num?)?.toDouble();
                return NoteEvent(
                  pitch: (note['midi'] as num).toInt(),
                  startMs: (timeSeconds * 1000).round(),
                  durationMs: durationSeconds == null
                      ? null
                      : (durationSeconds * 1000).round(),
                  velocity:
                      (((note['velocity'] as num?)?.toDouble() ?? 0.8) * 127)
                          .round(),
                  attrs: <String, Object?>{'name': note['name']},
                );
              })
              .toList()
            ..sort((a, b) => a.startMs.compareTo(b.startMs));

      tracks.add(
        Track(
          name: trackJson['name'] as String? ?? 'Track ${index + 1}',
          channel: (trackJson['channel'] as num?)?.toInt() ?? index,
          instrumentId: (trackJson['instrument'] as Map?)?['number'] as int?,
          notes: notes,
        ),
      );
    }

    return Score(
      tracks: tracks,
      format: SourceFormat.jsonScore,
      metadata: <String, Object?>{
        'source': 'tonejs-json',
        'header': json['header'],
      },
    );
  }
}
