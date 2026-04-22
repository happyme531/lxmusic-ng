import 'dart:math' as math;

import '../domain/game_profile.dart';
import '../util/midi_pitch.dart';

class LayoutGenerator {
  const LayoutGenerator();

  KeyLayout generate({
    required String id,
    required Map<String, Object?> params,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final pitchRangeOrList = (params['pitchRangeOrList'] as List<Object?>)
        .cast<String>();
    final row = params['row'] as int;
    final column = params['column'] as int;
    final haveSemitone = params['haveSemitone'] as bool? ?? false;
    final semiToneWidth = (params['semiToneWidth'] as num?)?.toDouble() ?? 0.0;
    final semiToneHeightOffset =
        (params['semiToneHeightOffset'] as num?)?.toDouble() ?? 0.5;
    final transformMatrix =
        ((params['transformMatrix'] as List<Object?>?) ??
                const <Object?>[
                  <Object?>[1, 0, 0],
                  <Object?>[0, 1, 0],
                  <Object?>[0, 0, 1],
                ])
            .map(
              (row) => (row as List<Object?>)
                  .map((value) => (value as num).toDouble())
                  .toList(),
            )
            .toList();
    final centerAngle = (params['centerAngle'] as num?)?.toDouble() ?? 0.0;
    final centerRadius = (params['centerRadius'] as num?)?.toDouble() ?? 1.0;
    final rowLengthOverride = _toPairMap(
      params['rowLengthOverride'] as List<Object?>?,
    );
    final insertDummyKeys = _toPairList(
      params['insertDummyKeys'] as List<Object?>?,
    );

    final rows = <List<_LayoutKey>>[];
    final usePitchRange = pitchRangeOrList.length == 2;
    var pitchOrIndex = usePitchRange
        ? MidiPitch.nameToMidiPitch(pitchRangeOrList[0])
        : 0;
    for (var rowIndex = 0; rowIndex < row; rowIndex++) {
      final colLen = rowLengthOverride[rowIndex] ?? column;
      final currentRow = <_LayoutKey>[];
      for (var colIndex = 0; colIndex < colLen; colIndex++) {
        final pitch = usePitchRange
            ? pitchOrIndex
            : MidiPitch.nameToMidiPitch(pitchRangeOrList[pitchOrIndex]);
        currentRow.add(_LayoutKey(pitch: pitch));
        if (usePitchRange) {
          if (!haveSemitone && MidiPitch.isHalf(pitch + 1)) {
            pitchOrIndex++;
          }
          pitchOrIndex++;
        } else {
          pitchOrIndex++;
        }
      }
      rows.add(currentRow);
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final inserts =
          insertDummyKeys
              .where((item) => item.$1 == rowIndex)
              .map((item) => item.$2)
              .toList()
            ..sort((a, b) => b.compareTo(a));
      for (final columnIndex in inserts) {
        rows[rowIndex].insert(columnIndex, _LayoutKey(pitch: -1));
      }
    }

    final rowDistance = row == 1 ? 1.0 : 1 / (row - 1);
    final colDistance = column == 1 ? 1.0 : 1 / (column - 1);

    for (final currentRow in rows) {
      var curX = 0.0;
      for (var keyIndex = 0; keyIndex < currentRow.length; keyIndex++) {
        final key = currentRow[keyIndex];
        key.x = curX;
        if (MidiPitch.isHalf(key.pitch) ||
            (keyIndex + 1 < currentRow.length &&
                MidiPitch.isHalf(currentRow[keyIndex + 1].pitch))) {
          curX += colDistance * (1 + semiToneWidth);
        } else {
          curX += colDistance * 2;
        }
      }
    }

    _normalizeX(rows);

    for (final currentRow in rows) {
      final centerX = (currentRow.last.x - currentRow.first.x) / 2;
      for (final key in currentRow) {
        key.x -= centerX - 0.5;
      }
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      for (final key in rows[rowIndex]) {
        key.y = 1 - rowDistance * rowIndex;
        if (MidiPitch.isHalf(key.pitch)) {
          key.y -= rowDistance * semiToneHeightOffset;
        }
      }
    }

    for (final currentRow in rows) {
      for (final key in currentRow) {
        final x = key.x;
        final y = key.y;
        key.x =
            x * transformMatrix[0][0] +
            y * transformMatrix[0][1] +
            transformMatrix[0][2];
        key.y =
            x * transformMatrix[1][0] +
            y * transformMatrix[1][1] +
            transformMatrix[1][2];
      }
    }

    if (centerAngle != 0) {
      final centerX = 0.5;
      final centerY = -centerRadius;
      final startAngle = math.pi / 2 - centerAngle / 2;
      final endAngle = math.pi / 2 + centerAngle / 2;

      for (final currentRow in rows) {
        for (final key in currentRow) {
          final angle = startAngle + (endAngle - startAngle) * key.x;
          final newX = centerX + (centerRadius + key.y) * math.cos(angle);
          final newY = centerY + (centerRadius + key.y) * math.sin(angle);
          key.x = newX;
          key.y = newY;
        }
      }
      _normalizeBoth(rows);
      for (final currentRow in rows) {
        final positions = currentRow
            .map((item) => (item.x, item.y))
            .toList()
            .reversed
            .toList();
        for (var index = 0; index < currentRow.length; index++) {
          currentRow[index].x = positions[index].$1;
          currentRow[index].y = positions[index].$2;
        }
      }
    }

    _normalizeBoth(rows);

    final keys = <KeyDefinition>[];
    final pitchToKeyId = <int, String>{};
    for (final currentRow in rows) {
      for (final key in currentRow) {
        if (key.pitch == -1) {
          continue;
        }
        final keyId = MidiPitch.midiPitchToName(key.pitch);
        keys.add(
          KeyDefinition(
            id: keyId,
            pitch: key.pitch,
            normX: key.x,
            normY: key.y,
          ),
        );
        pitchToKeyId[key.pitch] = keyId;
      }
    }

    return KeyLayout(
      id: id,
      algorithm: LayoutAlgorithm.procedural,
      keys: keys,
      pitchToKeyId: pitchToKeyId,
      metadata: metadata,
    );
  }

  Map<int, int> _toPairMap(List<Object?>? source) {
    final result = <int, int>{};
    if (source == null) {
      return result;
    }
    for (final item in source.cast<List<Object?>>()) {
      result[item[0] as int] = item[1] as int;
    }
    return result;
  }

  List<(int, int)> _toPairList(List<Object?>? source) {
    if (source == null) {
      return const <(int, int)>[];
    }
    return source
        .cast<List<Object?>>()
        .map((item) => (item[0] as int, item[1] as int))
        .toList();
  }

  void _normalizeX(List<List<_LayoutKey>> rows) {
    var minX = 0.0;
    var maxX = 0.0;
    for (final row in rows) {
      for (final key in row) {
        if (key.x < minX) minX = key.x;
        if (key.x > maxX) maxX = key.x;
      }
    }
    final width = maxX - minX;
    if (width == 0) {
      return;
    }
    for (final row in rows) {
      for (final key in row) {
        key.x = (key.x - minX) / width;
      }
    }
  }

  void _normalizeBoth(List<List<_LayoutKey>> rows) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final row in rows) {
      for (final key in row) {
        if (key.x < minX) minX = key.x;
        if (key.x > maxX) maxX = key.x;
        if (key.y < minY) minY = key.y;
        if (key.y > maxY) maxY = key.y;
      }
    }
    final width = maxX - minX;
    final height = maxY - minY;
    for (final row in rows) {
      for (final key in row) {
        key.x = width == 0 ? 0.5 : (key.x - minX) / width;
        key.y = height == 0 ? 0.5 : (key.y - minY) / height;
      }
    }
  }
}

class _LayoutKey {
  _LayoutKey({required this.pitch});

  final int pitch;
  double x = 0;
  double y = 0;
}
