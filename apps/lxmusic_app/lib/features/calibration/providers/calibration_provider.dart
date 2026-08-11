import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../core/service_locator.dart';
import '../platform/calibration_platform.dart';

typedef CalibrationStatusTarget = ({String profileId, String layoutId});

final calibrationDeviceIdProvider = FutureProvider<String>((ref) async {
  final platform = ref.watch(calibrationPlatformProvider);
  return (await platform.getState()).deviceId;
});

final calibrationStatusProvider = FutureProvider.autoDispose
    .family<bool, CalibrationStatusTarget>((ref, target) async {
      final repository = ref.watch(calibrationRepositoryProvider);
      final deviceId = await ref.watch(calibrationDeviceIdProvider.future);
      return repository.load(
            CalibrationKey(
              profileId: target.profileId,
              layoutId: target.layoutId,
              deviceId: deviceId,
            ),
          ) !=
          null;
    });

class CalibrationManagerState {
  const CalibrationManagerState({required this.platform, this.lastResult});

  final CalibrationPlatformState platform;
  final CalibrationSessionResult? lastResult;
}

final calibrationManagerProvider =
    AsyncNotifierProvider<CalibrationManager, CalibrationManagerState>(
      CalibrationManager.new,
    );

class CalibrationManager extends AsyncNotifier<CalibrationManagerState> {
  @override
  Future<CalibrationManagerState> build() => _load(consumePending: true);

  Future<CalibrationSessionResult?> refresh() async {
    final next = await AsyncValue.guard(() => _load(consumePending: true));
    state = next;
    return next.value?.lastResult;
  }

  Future<List<LaunchableCalibrationTarget>> findTargets(GameProfile profile) {
    return ref
        .read(calibrationPlatformProvider)
        .findLaunchableTargets(profile.packageNameHints);
  }

  Future<CalibrationSessionResult> startSession({
    required GameProfile profile,
    required KeyLayout layout,
    String? targetPackageName,
    CalibrationLaunchOrigin launchOrigin = CalibrationLaunchOrigin.mainApp,
  }) async {
    final platform = ref.read(calibrationPlatformProvider);
    final platformState = await platform.getState();
    if (!platformState.canCalibrate) {
      return const CalibrationSessionResult(
        status: CalibrationSessionStatus.error,
        errorCode: 'platform_unsupported',
        message: '当前平台不支持 Android 悬浮层校准。',
      );
    }
    if (!platformState.accessibilityEnabled) {
      return const CalibrationSessionResult(
        status: CalibrationSessionStatus.error,
        errorCode: 'accessibility_disabled',
        message: '请先启用 LxMusic-NG 无障碍服务。',
      );
    }
    final previous = ref
        .read(calibrationRepositoryProvider)
        .load(
          CalibrationKey(
            profileId: profile.id,
            layoutId: layout.id,
            deviceId: platformState.deviceId,
          ),
        );
    final layoutBinding = profile.layoutById(layout.id);
    final result = await platform.startSession(
      CalibrationSessionRequest(
        sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
        profileId: profile.id,
        layoutId: layout.id,
        profileDisplayName: profile.displayName,
        layoutDisplayName: layoutBinding?.displayName ?? layout.id,
        packageNameHints: profile.packageNameHints,
        keys: layout.keys,
        launchOrigin: launchOrigin,
        targetPackageName: targetPackageName,
        previousCalibration: previous,
      ),
    );
    state = AsyncData(
      CalibrationManagerState(platform: platformState, lastResult: result),
    );
    return result;
  }

  Future<void> openAccessibilitySettings() {
    return ref.read(calibrationPlatformProvider).openAccessibilitySettings();
  }

  Future<CalibrationManagerState> _load({bool consumePending = false}) async {
    final platform = ref.read(calibrationPlatformProvider);
    CalibrationSessionResult? pending;
    if (consumePending) {
      pending = await platform.consumePendingResult();
      if (pending?.status == CalibrationSessionStatus.saved &&
          pending?.calibration != null) {
        await ref
            .read(calibrationRepositoryProvider)
            .save(pending!.calibration!);
        ref.invalidate(calibrationStatusProvider);
      }
    }
    return CalibrationManagerState(
      platform: await platform.getState(),
      lastResult: pending,
    );
  }
}
