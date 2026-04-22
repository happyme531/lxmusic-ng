import '../domain/game_profile.dart';

abstract class CalibrationRepository {
  Calibration? load(CalibrationKey key);
}
