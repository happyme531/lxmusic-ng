import '../domain/game_profile.dart';

abstract class CalibrationRepository {
  Calibration? load(CalibrationKey key);

  List<Calibration> list();
}

abstract class MutableCalibrationRepository implements CalibrationRepository {
  Future<void> save(Calibration calibration);

  Future<void> delete(CalibrationKey key);
}
