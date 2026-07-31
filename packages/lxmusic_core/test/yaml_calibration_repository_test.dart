import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const path = 'calibrations/android-demo/sky__sky_3x5__portrait.yaml';
  const key = CalibrationKey(
    profileId: 'sky',
    layoutId: 'sky_3x5',
    deviceId: 'android-demo',
  );

  test('lists and loads complete bundled calibration data', () {
    final repository = YamlCalibrationRepository(
      YamlAssetBundle(<String, String>{
        path: '''
schemaVersion: 1
leftTop: [100, 200]
rightBottom: [900, 1200]
viewport: [0, 0, 1080, 1920]
capturedAt: '2026-07-30T12:00:00Z'
metadata:
  density: 2.75
  displayRotation: 0
''',
      }),
    );

    final calibration = repository.load(key);
    expect(calibration, isNotNull);
    expect(repository.list(), hasLength(1));
    expect(calibration!.orientation, 'portrait');
    expect(calibration.viewportPx, (
      left: 0.0,
      top: 0.0,
      right: 1080.0,
      bottom: 1920.0,
    ));
    expect(calibration.metadata['density'], 2.75);
  });

  test('reports corrupt YAML through a stable calibration error', () {
    final repository = YamlCalibrationRepository(
      YamlAssetBundle(<String, String>{path: 'leftTop: nope'}),
    );

    expect(repository.list, throwsA(isA<CalibrationFormatException>()));
  });
}
