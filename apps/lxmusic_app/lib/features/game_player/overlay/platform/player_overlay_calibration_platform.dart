import '../../../calibration/platform/calibration_platform.dart';
import 'player_overlay_bridge.dart';

/// Exposes the primary engine's calibration services to the overlay engine.
///
/// The overlay runs in a separate Flutter engine, so MainActivity's calibration
/// MethodChannel is not attached to it. These calls travel through the overlay
/// host and are handled by the primary engine instead.
class PlayerOverlayCalibrationPlatform implements CalibrationPlatform {
  const PlayerOverlayCalibrationPlatform(this.bridge);

  final PlayerOverlayBridge bridge;

  @override
  Future<CalibrationPlatformState> getState() async {
    return CalibrationPlatformState.fromMap(
      await bridge.sendAction(const <String, Object?>{
        'type': 'calibrationGetState',
      }),
    );
  }

  @override
  Future<List<LaunchableCalibrationTarget>> findLaunchableTargets(
    List<String> packageNameHints,
  ) async {
    final response = await bridge.sendAction(<String, Object?>{
      'type': 'calibrationFindTargets',
      'packageNameHints': packageNameHints,
    });
    return <LaunchableCalibrationTarget>[
      for (final item in response['targets'] as List? ?? const <Object?>[])
        if (item is Map)
          LaunchableCalibrationTarget.fromMap(Map<Object?, Object?>.from(item)),
    ];
  }

  @override
  Future<void> openAccessibilitySettings() async {
    await bridge.sendAction(const <String, Object?>{
      'type': 'calibrationOpenAccessibilitySettings',
    });
  }

  @override
  Future<CalibrationSessionResult> startSession(
    CalibrationSessionRequest request,
  ) async {
    return CalibrationSessionResult.fromMap(
      await bridge.sendAction(<String, Object?>{
        'type': 'calibrationStartSession',
        'profileId': request.profileId,
        'layoutId': request.layoutId,
        'launchOrigin': CalibrationLaunchOrigin.playerOverlay.name,
        if (request.targetPackageName != null)
          'targetPackageName': request.targetPackageName,
      }),
    );
  }

  @override
  Future<void> cancelSession() async {
    await bridge.sendAction(const <String, Object?>{
      'type': 'calibrationCancelSession',
    });
  }

  @override
  Future<CalibrationSessionResult?> consumePendingResult() async {
    final response = await bridge.sendAction(const <String, Object?>{
      'type': 'calibrationConsumePendingResult',
    });
    if (response['hasResult'] != true) return null;
    return CalibrationSessionResult.fromMap(response);
  }
}
