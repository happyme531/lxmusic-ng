import 'package:yaml/yaml.dart';

import '../domain/game_profile.dart';
import 'calibration_repository.dart';
import 'yaml_asset_bundle.dart';

class YamlCalibrationRepository implements CalibrationRepository {
  YamlCalibrationRepository(this.bundle);

  final YamlAssetBundle bundle;
  Map<CalibrationKey, Calibration>? _cache;

  @override
  Calibration? load(CalibrationKey key) {
    key.validate();
    return (_cache ??= _loadAll())[key];
  }

  @override
  List<Calibration> list() {
    final values = (_cache ??= _loadAll()).values.toList();
    values.sort((a, b) => a.key.storageKey.compareTo(b.key.storageKey));
    return List<Calibration>.unmodifiable(values);
  }

  Map<CalibrationKey, Calibration> _loadAll() {
    final result = <CalibrationKey, Calibration>{};
    final paths = bundle
        .listFiles('calibrations')
        .where((path) => path.endsWith('.yaml'));
    for (final path in paths) {
      final assetKey = _keyFromPath(path);
      final key = assetKey.key;
      final text = bundle.readText(path);
      if (text == null) {
        continue;
      }
      try {
        final decoded = loadYaml(text);
        if (decoded is! YamlMap) {
          throw const CalibrationFormatException(
            'invalid_yaml',
            'Calibration YAML root must be a map.',
          );
        }
        final json = _yamlMapToObjectMap(decoded);
        if (!json.containsKey('orientation') &&
            assetKey.legacyOrientation != null) {
          json['orientation'] = assetKey.legacyOrientation;
        }
        if (result.containsKey(key)) {
          throw CalibrationFormatException(
            'duplicate_calibration',
            'Multiple bundled calibrations target "${key.storageKey}".',
          );
        }
        result[key] = Calibration.fromJson(json, fallbackKey: key);
      } on CalibrationFormatException {
        rethrow;
      } on Object catch (error) {
        throw CalibrationFormatException(
          'invalid_yaml',
          'Invalid calibration YAML at "$path": $error',
        );
      }
    }
    return result;
  }

  ({CalibrationKey key, String? legacyOrientation}) _keyFromPath(String path) {
    const prefix = 'calibrations/';
    if (!path.startsWith(prefix)) {
      throw CalibrationFormatException(
        'invalid_asset_path',
        'Invalid calibration asset path "$path".',
      );
    }
    final relative = path.substring(prefix.length);
    final slash = relative.indexOf('/');
    if (slash <= 0 || !relative.endsWith('.yaml')) {
      throw CalibrationFormatException(
        'invalid_asset_path',
        'Invalid calibration asset path "$path".',
      );
    }
    final deviceId = relative.substring(0, slash);
    final fileStem = relative.substring(slash + 1, relative.length - 5);
    final parts = fileStem.split('__');
    if (parts.length != 2 && parts.length != 3) {
      throw CalibrationFormatException(
        'invalid_asset_path',
        'Invalid calibration asset filename "$path".',
      );
    }
    final key = CalibrationKey(
      profileId: parts[0],
      layoutId: parts[1],
      deviceId: deviceId,
    );
    key.validate();
    return (key: key, legacyOrientation: parts.length == 3 ? parts[2] : null);
  }

  Map<String, Object?> _yamlMapToObjectMap(YamlMap yaml) {
    return <String, Object?>{
      for (final entry in yaml.entries)
        entry.key.toString(): _convertYamlValue(entry.value),
    };
  }

  Object? _convertYamlValue(Object? value) {
    if (value is YamlMap) {
      return _yamlMapToObjectMap(value);
    }
    if (value is YamlList) {
      return value.map(_convertYamlValue).toList();
    }
    return value;
  }
}
