import 'package:flutter/services.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

class CalibrationPlatformState {
  const CalibrationPlatformState({
    required this.supported,
    required this.accessibilityEnabled,
    required this.apiLevel,
    required this.deviceId,
    required this.deviceDisplayName,
    required this.viewportWidthPx,
    required this.viewportHeightPx,
    required this.density,
    required this.displayRotation,
    this.targetOrientation,
    this.targetProfileId,
    this.targetLayoutId,
    this.activeSessionId,
  });

  final bool supported;
  final bool accessibilityEnabled;
  final int apiLevel;
  final String deviceId;
  final String deviceDisplayName;
  final double viewportWidthPx;
  final double viewportHeightPx;
  final double density;
  final int displayRotation;
  final String? targetOrientation;
  final String? targetProfileId;
  final String? targetLayoutId;
  final String? activeSessionId;

  bool get canCalibrate => supported && apiLevel >= 24;

  factory CalibrationPlatformState.fromMap(Map<Object?, Object?> map) {
    return CalibrationPlatformState(
      supported: map['supported'] == true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
      apiLevel: (map['apiLevel'] as num?)?.toInt() ?? 0,
      deviceId: map['deviceId'] as String? ?? 'unsupported-device',
      deviceDisplayName: map['deviceDisplayName'] as String? ?? '未知设备',
      viewportWidthPx: (map['viewportWidthPx'] as num?)?.toDouble() ?? 0,
      viewportHeightPx: (map['viewportHeightPx'] as num?)?.toDouble() ?? 0,
      density: (map['density'] as num?)?.toDouble() ?? 1,
      displayRotation: (map['displayRotation'] as num?)?.toInt() ?? 0,
      targetOrientation: map['targetOrientation'] as String?,
      targetProfileId: map['targetProfileId'] as String?,
      targetLayoutId: map['targetLayoutId'] as String?,
      activeSessionId: map['activeSessionId'] as String?,
    );
  }
}

class LaunchableCalibrationTarget {
  const LaunchableCalibrationTarget({
    required this.packageName,
    required this.label,
  });

  final String packageName;
  final String label;

  factory LaunchableCalibrationTarget.fromMap(Map<Object?, Object?> map) {
    return LaunchableCalibrationTarget(
      packageName: map['packageName'] as String? ?? '',
      label: map['label'] as String? ?? map['packageName'] as String? ?? '',
    );
  }
}

enum CalibrationSessionStatus { started, saved, cancelled, error }

class CalibrationSessionResult {
  const CalibrationSessionResult({
    required this.status,
    this.sessionId,
    this.calibration,
    this.errorCode,
    this.message,
  });

  final CalibrationSessionStatus status;
  final String? sessionId;
  final Calibration? calibration;
  final String? errorCode;
  final String? message;

  factory CalibrationSessionResult.fromMap(Map<Object?, Object?> map) {
    final statusName = map['status'] as String? ?? 'error';
    final status = CalibrationSessionStatus.values
        .where((value) => value.name == statusName)
        .firstOrNull;
    final rawCalibration = map['calibration'];
    return CalibrationSessionResult(
      status: status ?? CalibrationSessionStatus.error,
      sessionId: map['sessionId'] as String?,
      calibration: rawCalibration is Map
          ? Calibration.fromJson(
              Map<String, Object?>.from(
                rawCalibration.map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              ),
            )
          : null,
      errorCode: map['errorCode'] as String?,
      message: map['message'] as String?,
    );
  }
}

class CalibrationSessionRequest {
  const CalibrationSessionRequest({
    required this.sessionId,
    required this.profileId,
    required this.layoutId,
    required this.profileDisplayName,
    required this.layoutDisplayName,
    required this.packageNameHints,
    required this.keys,
    this.targetPackageName,
    this.previousCalibration,
  });

  final String sessionId;
  final String profileId;
  final String layoutId;
  final String profileDisplayName;
  final String layoutDisplayName;
  final List<String> packageNameHints;
  final List<KeyDefinition> keys;
  final String? targetPackageName;
  final Calibration? previousCalibration;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sessionId': sessionId,
      'profileId': profileId,
      'layoutId': layoutId,
      'profileDisplayName': profileDisplayName,
      'layoutDisplayName': layoutDisplayName,
      'packageNameHints': packageNameHints,
      'keys': <Map<String, Object?>>[
        for (final key in keys)
          <String, Object?>{
            'keyId': key.id,
            'normX': key.normX,
            'normY': key.normY,
          },
      ],
      if (targetPackageName != null) 'targetPackageName': targetPackageName,
      if (previousCalibration != null)
        'previousCalibration': previousCalibration!.toJson(),
    };
  }
}

abstract class CalibrationPlatform {
  Future<CalibrationPlatformState> getState();

  Future<List<LaunchableCalibrationTarget>> findLaunchableTargets(
    List<String> packageNameHints,
  );

  Future<void> openAccessibilitySettings();

  Future<CalibrationSessionResult> startSession(
    CalibrationSessionRequest request,
  );

  Future<void> cancelSession();

  Future<CalibrationSessionResult?> consumePendingResult();
}

class MethodChannelCalibrationPlatform implements CalibrationPlatform {
  const MethodChannelCalibrationPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const String channelName =
      'dev.happyme531.clxmidiplayer.ng/calibration';

  final MethodChannel channel;

  @override
  Future<CalibrationPlatformState> getState() async {
    final result = await _mapCall('getState');
    return CalibrationPlatformState.fromMap(result);
  }

  @override
  Future<List<LaunchableCalibrationTarget>> findLaunchableTargets(
    List<String> packageNameHints,
  ) async {
    final result = await channel.invokeListMethod<Object?>(
      'findLaunchableTargets',
      <String, Object?>{'packageNameHints': packageNameHints},
    );
    return <LaunchableCalibrationTarget>[
      for (final item in result ?? const <Object?>[])
        if (item is Map)
          LaunchableCalibrationTarget.fromMap(Map<Object?, Object?>.from(item)),
    ];
  }

  @override
  Future<void> openAccessibilitySettings() =>
      channel.invokeMethod<void>('openAccessibilitySettings');

  @override
  Future<CalibrationSessionResult> startSession(
    CalibrationSessionRequest request,
  ) async {
    return CalibrationSessionResult.fromMap(
      await _mapCall('startSession', request.toMap()),
    );
  }

  @override
  Future<void> cancelSession() => channel.invokeMethod<void>('cancelSession');

  @override
  Future<CalibrationSessionResult?> consumePendingResult() async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'consumePendingResult',
    );
    return result == null ? null : CalibrationSessionResult.fromMap(result);
  }

  Future<Map<Object?, Object?>> _mapCall(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: '$method returned no result.',
      );
    }
    return result;
  }
}
