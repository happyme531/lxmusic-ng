import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;

/// Decodes text-based score files using the encodings seen in legacy imports.
String decodeMusicText(Uint8List bytes) {
  if (bytes.isEmpty) {
    return '';
  }

  if (_startsWith(bytes, const <int>[0xef, 0xbb, 0xbf])) {
    return utf8.decode(bytes.sublist(3));
  }
  if (_startsWith(bytes, const <int>[0xff, 0xfe])) {
    return _decodeUtf16(bytes, littleEndian: true, offset: 2);
  }
  if (_startsWith(bytes, const <int>[0xfe, 0xff])) {
    return _decodeUtf16(bytes, littleEndian: false, offset: 2);
  }

  final inferredUtf16Endian = _inferBomlessUtf16Endian(bytes);
  if (inferredUtf16Endian != null) {
    return _decodeUtf16(bytes, littleEndian: inferredUtf16Endian);
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException('文本不是有效的 UTF-8、UTF-16 或 GBK 编码');
    }
  }
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

/// Returns true for little endian, false for big endian, and null if the bytes
/// do not have a convincing UTF-16 ASCII/NUL pattern.
bool? _inferBomlessUtf16Endian(Uint8List bytes) {
  if (bytes.length < 4 || bytes.length.isOdd) {
    return null;
  }
  final inspectedLength = bytes.length < 512 ? bytes.length : 512;
  final evenLength = inspectedLength.isEven
      ? inspectedLength
      : inspectedLength - 1;
  final pairCount = evenLength ~/ 2;
  var evenZeros = 0;
  var oddZeros = 0;
  for (var index = 0; index < evenLength; index += 2) {
    if (bytes[index] == 0) {
      evenZeros++;
    }
    if (bytes[index + 1] == 0) {
      oddZeros++;
    }
  }

  final strongThreshold = (pairCount * 0.3).ceil();
  final weakThreshold = (pairCount * 0.1).floor();
  if (oddZeros >= strongThreshold && evenZeros <= weakThreshold) {
    return true;
  }
  if (evenZeros >= strongThreshold && oddZeros <= weakThreshold) {
    return false;
  }
  return null;
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  int offset = 0,
}) {
  if ((bytes.length - offset).isOdd) {
    throw const FormatException('UTF-16 文本字节数不是偶数');
  }
  final data = ByteData.sublistView(bytes);
  final codeUnits = <int>[];
  for (var index = offset; index < bytes.length; index += 2) {
    codeUnits.add(
      data.getUint16(index, littleEndian ? Endian.little : Endian.big),
    );
  }

  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (index + 1 >= codeUnits.length ||
          codeUnits[index + 1] < 0xdc00 ||
          codeUnits[index + 1] > 0xdfff) {
        throw const FormatException('UTF-16 文本包含未配对的代理项');
      }
      index++;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      throw const FormatException('UTF-16 文本包含未配对的代理项');
    }
  }
  return String.fromCharCodes(codeUnits);
}
