import '../domain/game_profile.dart';

class CalibrationGeometry {
  const CalibrationGeometry._();

  static ({double x, double y}) mapNormalized(
    Calibration calibration, {
    required double normX,
    required double normY,
  }) {
    if (!normX.isFinite || !normY.isFinite) {
      throw const CalibrationFormatException(
        'non_finite_normalized_coordinate',
        'Normalized key coordinates must be finite numbers.',
      );
    }
    calibration.validate();
    final left = calibration.leftTopPx.$1;
    final top = calibration.leftTopPx.$2;
    return (
      x: left + (calibration.rightBottomPx.$1 - left) * normX,
      y: top + (calibration.rightBottomPx.$2 - top) * normY,
    );
  }
}
