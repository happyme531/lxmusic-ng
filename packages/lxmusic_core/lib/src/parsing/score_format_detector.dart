import 'dart:convert';
import 'dart:typed_data';

import 'music_text_decoder.dart';

enum ScoreFormatDetectionFailure {
  unsupportedExtension,
  invalidTextEncoding,
  malformedJson,
  unknownJsonSchema,
  unknownTextFormat,
  ambiguousFormat,
}

sealed class ScoreFormatDetectionResult {
  const ScoreFormatDetectionResult();
}

final class DetectedScoreFormat extends ScoreFormatDetectionResult {
  const DetectedScoreFormat(this.formatId);

  final String formatId;
}

final class RejectedScoreFormat extends ScoreFormatDetectionResult {
  const RejectedScoreFormat({required this.reason, required this.message});

  final ScoreFormatDetectionFailure reason;
  final String message;
}

class ScoreFormatDetector {
  const ScoreFormatDetector();

  ScoreFormatDetectionResult detect({
    required String fileName,
    required Uint8List bytes,
  }) {
    final lower = fileName.toLowerCase().replaceAll('\\', '/');

    const fixedSuffixes = <(String, String)>[
      ('.skystudio.json', 'skystudio-json'),
      ('.skystudio.txt', 'skystudio-json'),
      ('.score.json', 'json-score'),
      ('.dms.txt', 'domiso'),
      ('.midi', 'midi'),
      ('.dms', 'domiso'),
      ('.mid', 'midi'),
    ];
    for (final (suffix, formatId) in fixedSuffixes) {
      if (lower.endsWith(suffix)) {
        return DetectedScoreFormat(formatId);
      }
    }

    if (lower.endsWith('.json')) {
      return _detectJson(bytes, allowInternalJson: true);
    }
    if (lower.endsWith('.txt')) {
      return _detectPlainText(bytes);
    }
    return const RejectedScoreFormat(
      reason: ScoreFormatDetectionFailure.unsupportedExtension,
      message: '不支持的文件扩展名',
    );
  }

  ScoreFormatDetectionResult _detectPlainText(Uint8List bytes) {
    final textResult = _decodeText(bytes);
    if (textResult case RejectedScoreFormat()) {
      return textResult;
    }
    final text = textResult as String;
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) {
      return const RejectedScoreFormat(
        reason: ScoreFormatDetectionFailure.unknownTextFormat,
        message: 'TXT 文件为空或无法识别为乐谱',
      );
    }

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _classifyJsonText(text, allowInternalJson: false);
    }
    if (_looksLikeDomiso(text)) {
      return const DetectedScoreFormat('domiso');
    }
    return const RejectedScoreFormat(
      reason: ScoreFormatDetectionFailure.unknownTextFormat,
      message: '无法识别 TXT 乐谱格式',
    );
  }

  ScoreFormatDetectionResult _detectJson(
    Uint8List bytes, {
    required bool allowInternalJson,
  }) {
    final textResult = _decodeText(bytes);
    if (textResult case RejectedScoreFormat()) {
      return textResult;
    }
    return _classifyJsonText(
      textResult as String,
      allowInternalJson: allowInternalJson,
    );
  }

  Object _decodeText(Uint8List bytes) {
    try {
      return decodeMusicText(bytes);
    } on FormatException catch (error) {
      return RejectedScoreFormat(
        reason: ScoreFormatDetectionFailure.invalidTextEncoding,
        message: error.message,
      );
    }
  }

  ScoreFormatDetectionResult _classifyJsonText(
    String text, {
    required bool allowInternalJson,
  }) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const RejectedScoreFormat(
        reason: ScoreFormatDetectionFailure.malformedJson,
        message: 'JSON 语法无效',
      );
    }

    final matches = <String>[];
    if (allowInternalJson && _isJsonScore(decoded)) {
      matches.add('json-score');
    }
    if (_isSkyStudioJson(decoded)) {
      matches.add('skystudio-json');
    }
    if (_isToneJsJson(decoded)) {
      matches.add('tonejs-json');
    }

    if (matches.length == 1) {
      return DetectedScoreFormat(matches.single);
    }
    if (matches.length > 1) {
      return const RejectedScoreFormat(
        reason: ScoreFormatDetectionFailure.ambiguousFormat,
        message: 'JSON 同时符合多个乐谱格式',
      );
    }
    return RejectedScoreFormat(
      reason: ScoreFormatDetectionFailure.unknownJsonSchema,
      message: allowInternalJson ? '无法识别 JSON 乐谱结构' : 'TXT 中的 JSON 不是支持的外部乐谱格式',
    );
  }

  bool _isJsonScore(Object? decoded) {
    return decoded is Map &&
        decoded['format'] == 'jsonScore' &&
        decoded['tracks'] is List;
  }

  bool _isSkyStudioJson(Object? decoded) {
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      return false;
    }
    final song = decoded.first as Map;
    final notes = song['songNotes'];
    if (notes is! List) {
      return false;
    }
    return notes.every(
      (note) => note is Map && note['key'] is String && note['time'] is num,
    );
  }

  bool _isToneJsJson(Object? decoded) {
    if (decoded is! Map || decoded['tracks'] is! List) {
      return false;
    }
    final tracks = decoded['tracks'] as List;
    if (tracks.isEmpty) {
      return decoded['header'] is Map;
    }
    for (final track in tracks) {
      if (track is! Map || track['notes'] is! List) {
        return false;
      }
      final notes = track['notes'] as List;
      if (!notes.every(
        (note) => note is Map && note['midi'] is num && note['time'] is num,
      )) {
        return false;
      }
    }
    return true;
  }

  bool _looksLikeDomiso(String text) {
    final lines = const LineSplitter().convert(text);
    final separatorIndex = lines.indexWhere((line) => line.contains('=='));
    final bodyLines = separatorIndex < 0
        ? lines
        : lines.skip(separatorIndex + 1);
    var noteTokenCount = 0;
    var hasStrongMarker = separatorIndex >= 0;

    for (final line in bodyLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//')) {
        continue;
      }
      for (final token in trimmed.split(RegExp(r'\s+'))) {
        if (RegExp(r'^(?:bpm|rollback|1)=\S+$').hasMatch(token)) {
          hasStrongMarker = true;
        } else if (RegExp(r'^[+-]*[0-7][#b]?[./-]*$').hasMatch(token)) {
          noteTokenCount++;
        }
      }
    }
    return noteTokenCount >= 1 && (hasStrongMarker || noteTokenCount >= 2);
  }
}
