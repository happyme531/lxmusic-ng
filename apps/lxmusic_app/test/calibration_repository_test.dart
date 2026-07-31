import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/calibration/data/app_calibration_repository.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const key = CalibrationKey(
    profileId: 'sky',
    layoutId: 'sky_3x5',
    deviceId: 'android-test',
  );
  final bundled = Calibration(
    key: key,
    orientation: 'portrait',
    leftTopPx: (10, 20),
    rightBottomPx: (100, 200),
    viewportPx: (left: 0, top: 0, right: 1080, bottom: 1920),
    capturedAt: DateTime.utc(2026, 7, 1),
  );
  final user = Calibration(
    key: key,
    orientation: 'portrait',
    leftTopPx: (30, 40),
    rightBottomPx: (300, 400),
    viewportPx: (left: 0, top: 0, right: 1080, bottom: 1920),
    capturedAt: DateTime.utc(2026, 7, 30),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('user records persist and override bundled calibrations', () async {
    final preferences = await SharedPreferences.getInstance();
    final firstUserRepository = SharedPreferencesCalibrationRepository(
      preferences,
    );
    final firstComposite = CompositeCalibrationRepository(
      userRepository: firstUserRepository,
      bundledRepository: _ReadOnlyRepository(<Calibration>[bundled]),
    );

    expect(firstComposite.load(key)?.leftTopPx, bundled.leftTopPx);
    await firstComposite.save(user);
    expect(firstComposite.load(key)?.leftTopPx, user.leftTopPx);
    expect(firstComposite.isUserCalibration(key), isTrue);
    expect(firstComposite.list(), hasLength(1));

    final reloadedUserRepository = SharedPreferencesCalibrationRepository(
      preferences,
    );
    final reloadedComposite = CompositeCalibrationRepository(
      userRepository: reloadedUserRepository,
      bundledRepository: _ReadOnlyRepository(<Calibration>[bundled]),
    );
    expect(reloadedComposite.load(key)?.leftTopPx, user.leftTopPx);

    await reloadedComposite.delete(key);
    expect(reloadedComposite.load(key)?.leftTopPx, bundled.leftTopPx);
    expect(reloadedComposite.isUserCalibration(key), isFalse);
  });

  test('recalibrating the same layout overwrites its only record', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesCalibrationRepository(preferences);
    await repository.save(user);
    final landscape = Calibration(
      key: key,
      orientation: 'landscape',
      leftTopPx: (40, 30),
      rightBottomPx: (400, 300),
      viewportPx: (left: 0, top: 0, right: 1920, bottom: 1080),
      capturedAt: DateTime.utc(2026, 7, 31),
    );

    await repository.save(landscape);

    expect(repository.list(), hasLength(1));
    expect(repository.load(key)?.orientation, 'landscape');
    final reloaded = SharedPreferencesCalibrationRepository(preferences);
    expect(reloaded.list(), hasLength(1));
    expect(reloaded.load(key)?.orientation, 'landscape');
  });

  test('legacy orientation-split records collapse to the newest one', () async {
    final landscape = Calibration(
      key: key,
      orientation: 'landscape',
      leftTopPx: (40, 30),
      rightBottomPx: (400, 300),
      viewportPx: (left: 0, top: 0, right: 1920, bottom: 1080),
      capturedAt: DateTime.utc(2026, 7, 31),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesCalibrationRepository.storageKey: jsonEncode(
        <String, Object?>{
          'schemaVersion': 1,
          'calibrations': <String, Object?>{
            '${key.storageKey}/portrait': user.toJson(),
            '${key.storageKey}/landscape': landscape.toJson(),
          },
        },
      ),
    });

    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesCalibrationRepository(preferences);

    expect(repository.list(), hasLength(1));
    expect(repository.load(key)?.orientation, 'landscape');
  });

  test('unknown persisted schema fails with a stable storage code', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesCalibrationRepository.storageKey:
          '{"schemaVersion":2,"calibrations":{}}',
    });
    final preferences = await SharedPreferences.getInstance();

    expect(
      () => SharedPreferencesCalibrationRepository(preferences),
      throwsA(
        isA<CalibrationStorageException>().having(
          (error) => error.code,
          'code',
          'unsupported_schema',
        ),
      ),
    );
  });
}

class _ReadOnlyRepository implements CalibrationRepository {
  _ReadOnlyRepository(List<Calibration> calibrations)
    : _calibrations = <CalibrationKey, Calibration>{
        for (final calibration in calibrations) calibration.key: calibration,
      };

  final Map<CalibrationKey, Calibration> _calibrations;

  @override
  Calibration? load(CalibrationKey key) => _calibrations[key];

  @override
  List<Calibration> list() => _calibrations.values.toList();
}
