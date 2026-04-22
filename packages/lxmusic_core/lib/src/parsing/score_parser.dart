import 'dart:typed_data';

import '../domain/score.dart';

abstract class ScoreParser {
  String get formatId;

  Score parse(Uint8List bytes);
}
