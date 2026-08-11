import 'dart:typed_data';

import '../domain/score.dart';
import 'score_parser.dart';
import 'parsers/domiso_score_parser.dart';
import 'parsers/json_score_parser.dart';
import 'parsers/midi_score_parser.dart';
import 'parsers/skystudio_json_score_parser.dart';
import 'parsers/tonejs_json_score_parser.dart';

class ParserRegistry {
  ParserRegistry(this._parsers);

  final Map<String, ScoreParser> _parsers;

  List<String> get supportedFormats => _parsers.keys.toList()..sort();

  Score parse({required Uint8List bytes, required String formatId}) {
    final parser = _parsers[formatId];
    if (parser == null) {
      throw ArgumentError(
        'Unsupported format "$formatId". Supported: ${supportedFormats.join(', ')}',
      );
    }
    return parser.parse(bytes);
  }
}

/// Creates the parser set shared by the App, CLI, and background workers.
ParserRegistry createDefaultParserRegistry() {
  return ParserRegistry(<String, ScoreParser>{
    'domiso': DoMiSoScoreParser(),
    'json-score': const JsonScoreParser(),
    'midi': const MidiScoreParser(),
    'skystudio-json': const SkyStudioJsonScoreParser(),
    'tonejs-json': ToneJsJsonScoreParser(),
  });
}
