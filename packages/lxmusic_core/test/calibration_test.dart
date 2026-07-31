import 'dart:convert';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const key = CalibrationKey(
    profileId: 'sky',
    layoutId: 'sky_3x5',
    deviceId: 'android-device',
  );

  final calibration = Calibration(
    key: key,
    orientation: 'portrait',
    leftTopPx: (120, 900),
    rightBottomPx: (960, 1800),
    viewportPx: (left: 0, top: 0, right: 1080, bottom: 2400),
    capturedAt: DateTime.utc(2026, 7, 30, 12, 0),
    metadata: const <String, Object?>{
      'density': 2.75,
      'foregroundPackage': 'com.example.game',
    },
  );

  test('calibration JSON round-trips schema version 1', () {
    final encoded = jsonEncode(calibration.toJson());
    final decoded = Calibration.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );

    expect(decoded.key, key);
    expect(decoded.leftTopPx, (120.0, 900.0));
    expect(decoded.rightBottomPx, (960.0, 1800.0));
    expect(decoded.viewportPx, (
      left: 0.0,
      top: 0.0,
      right: 1080.0,
      bottom: 2400.0,
    ));
    expect(decoded.capturedAt, calibration.capturedAt);
    expect(decoded.metadata, calibration.metadata);
    expect(decoded.toJson()['schemaVersion'], 1);
  });

  test('legacy bundled data may use its storage key and omit viewport', () {
    final decoded = Calibration.fromJson(<String, Object?>{
      'orientation': 'portrait',
      'leftTop': <Object?>[120, 1500],
      'rightBottom': <Object?>[960, 2200],
      'capturedAt': '2026-04-11T21:30:00Z',
    }, fallbackKey: key);

    expect(decoded.key, key);
    expect(decoded.viewportPx, isNull);
  });

  test('maps normalized layout coordinates through shared geometry', () {
    final point = CalibrationGeometry.mapNormalized(
      calibration,
      normX: 0.25,
      normY: 0.5,
    );

    expect(point, (x: 330.0, y: 1350.0));
  });

  test('orientation is calibration metadata, not part of its unique key', () {
    final landscapeCalibration = Calibration(
      key: key,
      orientation: 'landscape',
      leftTopPx: (120, 200),
      rightBottomPx: (1800, 900),
      capturedAt: DateTime.utc(2026, 7, 30, 13),
    );

    expect(key.storageKey, 'android-device/sky/sky_3x5');
    expect(landscapeCalibration.key, calibration.key);
    expect(landscapeCalibration.orientation, isNot(calibration.orientation));
  });

  test('rejects unsupported schema and orientation with stable codes', () {
    expect(
      () => Calibration.fromJson(<String, Object?>{
        ...calibration.toJson(),
        'schemaVersion': 2,
      }),
      throwsA(
        isA<CalibrationFormatException>().having(
          (error) => error.code,
          'code',
          'unsupported_schema',
        ),
      ),
    );
    expect(
      () => Calibration.fromJson(<String, Object?>{
        ...calibration.toJson(),
        'orientation': 'portraitUpsideDown',
      }),
      throwsA(
        isA<CalibrationFormatException>().having(
          (error) => error.code,
          'code',
          'invalid_orientation',
        ),
      ),
    );
  });

  test('rejects non-finite, reversed, and out-of-viewport rectangles', () {
    void expectCode(Map<String, Object?> json, String code) {
      expect(
        () => Calibration.fromJson(json),
        throwsA(
          isA<CalibrationFormatException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }

    expectCode(<String, Object?>{
      ...calibration.toJson(),
      'leftTop': <Object?>[double.nan, 900],
    }, 'non_finite_coordinate');
    expectCode(<String, Object?>{
      ...calibration.toJson(),
      'leftTop': <Object?>[970, 900],
    }, 'invalid_rectangle');
    expectCode(<String, Object?>{
      ...calibration.toJson(),
      'rightBottom': <Object?>[1200, 1800],
    }, 'outside_viewport');
  });
}
