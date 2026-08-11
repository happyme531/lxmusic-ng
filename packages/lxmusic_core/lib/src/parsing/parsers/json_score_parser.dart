import 'dart:convert';
import 'dart:typed_data';

import '../../domain/score.dart';
import '../music_text_decoder.dart';
import '../score_parser.dart';

class JsonScoreParser implements ScoreParser {
  const JsonScoreParser();

  @override
  String get formatId => 'json-score';

  @override
  Score parse(Uint8List bytes) {
    final decoded = jsonDecode(decodeMusicText(bytes));
    if (decoded is! Map) {
      throw const FormatException('JSON score 根节点必须是对象');
    }
    return Score.fromJson(Map<String, Object?>.from(decoded));
  }
}
