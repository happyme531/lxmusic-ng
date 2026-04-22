import 'dart:typed_data';

import '../domain/score.dart';
import 'score_parser.dart';

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
