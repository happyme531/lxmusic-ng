import 'package:yaml/yaml.dart';

import '../domain/game_profile.dart';
import 'calibration_repository.dart';
import 'yaml_asset_bundle.dart';

class YamlCalibrationRepository implements CalibrationRepository {
  YamlCalibrationRepository(this.bundle);

  final YamlAssetBundle bundle;

  @override
  Calibration? load(CalibrationKey key) {
    final text = bundle.readText(
      'calibrations/${key.deviceId}/${key.fileStem}.yaml',
    );
    if (text == null) {
      return null;
    }
    final yaml = loadYaml(text) as YamlMap;
    final leftTop = (yaml['leftTop'] as YamlList).cast<num>();
    final rightBottom = (yaml['rightBottom'] as YamlList).cast<num>();

    return Calibration(
      key: key,
      leftTopPx: (leftTop[0].toDouble(), leftTop[1].toDouble()),
      rightBottomPx: (rightBottom[0].toDouble(), rightBottom[1].toDouble()),
      capturedAt: DateTime.parse(yaml['capturedAt'] as String),
      viewportPx: null,
      metadata: <String, Object?>{},
    );
  }
}
