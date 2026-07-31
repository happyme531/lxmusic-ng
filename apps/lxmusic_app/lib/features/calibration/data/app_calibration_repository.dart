import 'dart:convert';

import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesCalibrationRepository
    implements MutableCalibrationRepository {
  SharedPreferencesCalibrationRepository(this.preferences)
    : _calibrations = _decode(preferences.getString(storageKey));

  static const String storageKey = 'calibrations.v1';
  static const int schemaVersion = 1;

  final SharedPreferences preferences;
  Map<CalibrationKey, Calibration> _calibrations;

  @override
  Calibration? load(CalibrationKey key) {
    key.validate();
    return _calibrations[key];
  }

  @override
  List<Calibration> list() {
    final values = _calibrations.values.toList()
      ..sort((a, b) => a.key.storageKey.compareTo(b.key.storageKey));
    return List<Calibration>.unmodifiable(values);
  }

  @override
  Future<void> save(Calibration calibration) async {
    calibration.validate();
    final next = <CalibrationKey, Calibration>{
      ..._calibrations,
      calibration.key: calibration,
    };
    await _persist(next);
    _calibrations = next;
  }

  @override
  Future<void> delete(CalibrationKey key) async {
    key.validate();
    if (!_calibrations.containsKey(key)) {
      return;
    }
    final next = <CalibrationKey, Calibration>{..._calibrations}..remove(key);
    await _persist(next);
    _calibrations = next;
  }

  Future<void> _persist(Map<CalibrationKey, Calibration> calibrations) async {
    final values = <String, Object?>{
      for (final calibration in calibrations.values)
        calibration.key.storageKey: calibration.toJson(),
    };
    final saved = await preferences.setString(
      storageKey,
      jsonEncode(<String, Object?>{
        'schemaVersion': schemaVersion,
        'calibrations': values,
      }),
    );
    if (!saved) {
      throw StateError('Failed to persist calibration records.');
    }
  }

  static Map<CalibrationKey, Calibration> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <CalibrationKey, Calibration>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const CalibrationStorageException(
          'invalid_root',
          'Calibration storage root must be an object.',
        );
      }
      if (decoded['schemaVersion'] != schemaVersion) {
        throw CalibrationStorageException(
          'unsupported_schema',
          'Unsupported calibration storage schema '
              '"${decoded['schemaVersion']}".',
        );
      }
      final rawCalibrations = decoded['calibrations'];
      if (rawCalibrations is! Map<String, Object?>) {
        throw const CalibrationStorageException(
          'invalid_records',
          'Calibration storage records must be an object.',
        );
      }
      final result = <CalibrationKey, Calibration>{};
      for (final entry in rawCalibrations.entries) {
        final rawCalibration = entry.value;
        if (rawCalibration is! Map<String, Object?>) {
          throw CalibrationStorageException(
            'invalid_record',
            'Calibration record "${entry.key}" must be an object.',
          );
        }
        final calibration = Calibration.fromJson(rawCalibration);
        final legacyStorageKey =
            '${calibration.key.storageKey}/${calibration.orientation}';
        if (calibration.key.storageKey != entry.key &&
            legacyStorageKey != entry.key) {
          throw CalibrationStorageException(
            'key_mismatch',
            'Calibration record "${entry.key}" has a mismatched key.',
          );
        }
        final existing = result[calibration.key];
        if (existing == null ||
            calibration.capturedAt.isAfter(existing.capturedAt)) {
          result[calibration.key] = calibration;
        }
      }
      return result;
    } on CalibrationStorageException {
      rethrow;
    } on CalibrationFormatException catch (error) {
      throw CalibrationStorageException(error.code, error.message);
    } on Object catch (error) {
      throw CalibrationStorageException(
        'invalid_json',
        'Invalid persisted calibration data: $error',
      );
    }
  }
}

class CompositeCalibrationRepository implements MutableCalibrationRepository {
  CompositeCalibrationRepository({
    required this.userRepository,
    required this.bundledRepository,
  });

  final MutableCalibrationRepository userRepository;
  final CalibrationRepository bundledRepository;

  bool isUserCalibration(CalibrationKey key) =>
      userRepository.load(key) != null;

  @override
  Calibration? load(CalibrationKey key) {
    return userRepository.load(key) ?? bundledRepository.load(key);
  }

  @override
  List<Calibration> list() {
    final byKey = <CalibrationKey, Calibration>{
      for (final calibration in bundledRepository.list())
        calibration.key: calibration,
      for (final calibration in userRepository.list())
        calibration.key: calibration,
    };
    final values = byKey.values.toList()
      ..sort((a, b) => a.key.storageKey.compareTo(b.key.storageKey));
    return List<Calibration>.unmodifiable(values);
  }

  @override
  Future<void> save(Calibration calibration) =>
      userRepository.save(calibration);

  @override
  Future<void> delete(CalibrationKey key) => userRepository.delete(key);
}

class CalibrationStorageException extends FormatException {
  const CalibrationStorageException(this.code, String message) : super(message);

  final String code;

  @override
  String toString() => 'CalibrationStorageException($code): $message';
}
