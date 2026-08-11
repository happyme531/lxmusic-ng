import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/calibration/platform/calibration_platform.dart';
import 'package:lxmusic_app/features/game_player/overlay/models/player_overlay_state.dart';
import 'package:lxmusic_app/features/game_player/overlay/platform/player_overlay_bridge.dart';
import 'package:lxmusic_app/features/game_player/overlay/platform/player_overlay_calibration_platform.dart';

void main() {
  test(
    'calibration platform maps every operation through overlay bridge',
    () async {
      final bridge = _CalibrationBridge();
      final platform = PlayerOverlayCalibrationPlatform(bridge);

      final state = await platform.getState();
      expect(state.canCalibrate, isTrue);
      expect(state.deviceId, 'overlay-device');

      final targets = await platform.findLaunchableTargets(<String>[
        'game.hint',
      ]);
      expect(targets.single.packageName, 'game.package');

      final started = await platform.startSession(
        const CalibrationSessionRequest(
          sessionId: 'session-1',
          profileId: 'profile-1',
          layoutId: 'layout-1',
          profileDisplayName: '游戏',
          layoutDisplayName: '键位',
          packageNameHints: <String>['game.hint'],
          keys: [],
          targetPackageName: 'game.package',
        ),
      );
      expect(started.status, CalibrationSessionStatus.started);

      await platform.openAccessibilitySettings();
      await platform.cancelSession();
      expect(await platform.consumePendingResult(), isNull);

      expect(bridge.actions.map((action) => action['type']), <Object?>[
        'calibrationGetState',
        'calibrationFindTargets',
        'calibrationStartSession',
        'calibrationOpenAccessibilitySettings',
        'calibrationCancelSession',
        'calibrationConsumePendingResult',
      ]);
      expect(bridge.actions[1]['packageNameHints'], <String>['game.hint']);
      expect(bridge.actions[2]['profileId'], 'profile-1');
      expect(bridge.actions[2]['layoutId'], 'layout-1');
      expect(bridge.actions[2]['launchOrigin'], 'playerOverlay');
      expect(bridge.actions[2]['targetPackageName'], 'game.package');
    },
  );
}

class _CalibrationBridge implements PlayerOverlayBridge {
  final List<Map<String, Object?>> actions = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> sendAction(Map<String, Object?> action) async {
    actions.add(action);
    return switch (action['type']) {
      'calibrationGetState' => <String, Object?>{
        'supported': true,
        'accessibilityEnabled': true,
        'apiLevel': 36,
        'deviceId': 'overlay-device',
        'deviceDisplayName': 'Overlay Device',
        'viewportWidthPx': 1080,
        'viewportHeightPx': 2400,
        'density': 3,
        'displayRotation': 0,
        'orientationLockSupported': true,
      },
      'calibrationFindTargets' => <String, Object?>{
        'targets': <Map<String, Object?>>[
          <String, Object?>{'packageName': 'game.package', 'label': '测试游戏'},
        ],
      },
      'calibrationStartSession' => <String, Object?>{
        'status': 'started',
        'sessionId': 'session-1',
      },
      'calibrationConsumePendingResult' => const <String, Object?>{
        'hasResult': false,
      },
      _ => const <String, Object?>{'status': 'ok'},
    };
  }

  @override
  Future<Map<String, Object?>> loadInitialSession() async =>
      const <String, Object?>{};

  @override
  void setSessionHandler(PlayerOverlaySessionHandler? handler) {}

  @override
  Future<void> resize(
    PlayerOverlayWindowSize size, {
    bool animate = true,
  }) async {}

  @override
  Future<void> moveBy(double deltaX, double deltaY) async {}

  @override
  Future<void> setResizeMode(bool enabled) async {}

  @override
  Future<void> setTextInputActive(bool active) async {}

  @override
  Future<void> setTargetPickerActive(bool active) async {}

  @override
  Future<void> close() async {}

  @override
  void dispose() {}
}
