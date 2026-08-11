import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const detector = ScoreFormatDetector();

  group('fixed suffixes', () {
    test('trusts MIDI without inspecting content', () {
      expect(
        _formatId(
          detector.detect(
            fileName: 'anything.midi',
            bytes: Uint8List.fromList(const <int>[0, 1, 2]),
          ),
        ),
        'midi',
      );
    });

    test('compound text suffix wins over content', () {
      expect(
        _formatId(
          detector.detect(
            fileName: 'renamed.dms.txt',
            bytes: _utf8(_skyStudioJson),
          ),
        ),
        'domiso',
      );
    });

    test('recognizes internal score compound suffix', () {
      expect(
        _formatId(
          detector.detect(fileName: 'song.score.json', bytes: _utf8('{broken')),
        ),
        'json-score',
      );
    });
  });

  group('JSON structure detection', () {
    test('detects all supported JSON score shapes', () {
      expect(_detect(detector, 'internal.json', _jsonScore), 'json-score');
      expect(_detect(detector, 'sky.json', _skyStudioJson), 'skystudio-json');
      expect(_detect(detector, 'tone.json', _toneJsJson), 'tonejs-json');
    });

    test('detects external JSON stored in plain txt', () {
      expect(_detect(detector, 'sky.txt', _skyStudioJson), 'skystudio-json');
      expect(_detect(detector, 'tone.txt', _toneJsJson), 'tonejs-json');
    });

    test('rejects internal JSON stored in plain txt', () {
      final result = detector.detect(
        fileName: 'internal.txt',
        bytes: _utf8(_jsonScore),
      );

      expect(result, isA<RejectedScoreFormat>());
      expect(
        (result as RejectedScoreFormat).reason,
        ScoreFormatDetectionFailure.unknownJsonSchema,
      );
    });

    test('does not downgrade malformed JSON-looking txt to DoMiSo', () {
      final result = detector.detect(
        fileName: 'broken.txt',
        bytes: _utf8('{"tracks": [1, 2'),
      );

      expect(
        (result as RejectedScoreFormat).reason,
        ScoreFormatDetectionFailure.malformedJson,
      );
    });
  });

  group('plain DoMiSo detection', () {
    test('accepts strong marker plus one note', () {
      expect(_detect(detector, 'one-note.txt', 'bpm=120\n1'), 'domiso');
    });

    test('accepts at least two valid note tokens', () {
      expect(_detect(detector, 'scale.txt', '1 2'), 'domiso');
    });

    test('rejects a single ambiguous note token', () {
      final result = detector.detect(
        fileName: 'not-enough.txt',
        bytes: _utf8('1'),
      );

      expect(
        (result as RejectedScoreFormat).reason,
        ScoreFormatDetectionFailure.unknownTextFormat,
      );
    });

    test('rejects unrelated text', () {
      final result = detector.detect(
        fileName: 'readme.txt',
        bytes: _utf8('这只是一段普通说明文字。'),
      );

      expect(result, isA<RejectedScoreFormat>());
    });
  });

  group('text encodings', () {
    test('detects UTF-8 BOM and UTF-16 LE/BE without BOM', () {
      final utf8Bom = Uint8List.fromList(<int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(_toneJsJson),
      ]);
      expect(
        _formatId(detector.detect(fileName: 'bom.txt', bytes: utf8Bom)),
        'tonejs-json',
      );
      expect(
        _formatId(
          detector.detect(
            fileName: 'le.txt',
            bytes: _utf16(_skyStudioJson, littleEndian: true),
          ),
        ),
        'skystudio-json',
      );
      expect(
        _formatId(
          detector.detect(
            fileName: 'be.txt',
            bytes: _utf16(_skyStudioJson, littleEndian: false),
          ),
        ),
        'skystudio-json',
      );
    });

    test('detects and parses GBK DoMiSo with Chinese comments', () {
      final bytes = Uint8List.fromList(gbk.encode('中文标题\n==\nbpm=120\n1 2'));
      final result = detector.detect(fileName: 'legacy.txt', bytes: bytes);
      final score = DoMiSoScoreParser().parse(bytes);

      expect(_formatId(result), 'domiso');
      expect(score.totalNoteCount, 2);
      expect(score.metadata['comment'], '中文标题');
    });

    test('all JSON score parsers decode GBK text', () {
      final internal = const JsonScoreParser().parse(
        Uint8List.fromList(gbk.encode(_jsonScore)),
      );
      final sky = const SkyStudioJsonScoreParser().parse(
        Uint8List.fromList(
          gbk.encode(_skyStudioJson.replaceFirst('Sky', '天空')),
        ),
      );
      final tone = ToneJsJsonScoreParser().parse(
        Uint8List.fromList(gbk.encode(_toneJsJson.replaceFirst('Tone', '钢琴'))),
      );

      expect(internal.totalNoteCount, 1);
      expect(sky.tracks.single.name, '天空');
      expect(tone.totalNoteCount, 1);
    });

    test('reports bytes invalid in every supported encoding', () {
      final result = detector.detect(
        fileName: 'broken.txt',
        bytes: Uint8List.fromList(const <int>[0x81]),
      );

      expect(
        (result as RejectedScoreFormat).reason,
        ScoreFormatDetectionFailure.invalidTextEncoding,
      );
    });
  });
}

String _detect(ScoreFormatDetector detector, String fileName, String contents) {
  return _formatId(detector.detect(fileName: fileName, bytes: _utf8(contents)));
}

String _formatId(ScoreFormatDetectionResult result) {
  expect(result, isA<DetectedScoreFormat>());
  return (result as DetectedScoreFormat).formatId;
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _utf16(String value, {required bool littleEndian}) {
  final data = ByteData(value.codeUnits.length * 2);
  for (var index = 0; index < value.codeUnits.length; index++) {
    data.setUint16(
      index * 2,
      value.codeUnits[index],
      littleEndian ? Endian.little : Endian.big,
    );
  }
  return data.buffer.asUint8List();
}

const _jsonScore = '''
{
  "format": "jsonScore",
  "tracks": [{"notes": [{"pitch": 60, "startMs": 0}]}],
  "metadata": {"title": "内部乐谱"}
}
''';

const _skyStudioJson = '''
[
  {
    "name": "Sky",
    "songNotes": [{"time": 0, "key": "1Key0"}]
  }
]
''';

const _toneJsJson = '''
{
  "header": {"name": "Tone"},
  "tracks": [
    {"notes": [{"midi": 60, "time": 0, "duration": 0.25}]}
  ]
}
''';
