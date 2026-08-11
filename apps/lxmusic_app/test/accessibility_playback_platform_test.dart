import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/game_player/platform/accessibility_playback_platform.dart';
import 'package:lxmusic_app/features/game_player/services/game_playback_plan_service.dart';
import 'package:lxmusic_app/features/workbench/models/song_config.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sends playback without requiring a target package', (
    tester,
  ) async {
    const channel = MethodChannel(
      MethodChannelAccessibilityPlaybackPlatform.channelName,
    );
    MethodCall? received;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      received = call;
      return <String, Object?>{
        'status': 'started',
        'playbackId': 'playback-1',
        'positionMs': 120,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final platform = MethodChannelAccessibilityPlaybackPlatform(
      channel: channel,
    );
    addTearDown(platform.dispose);
    final playback = PreparedGamePlayback(
      fileName: 'song.mid',
      cacheKey: 'cache',
      config: SongConfig(
        fileName: 'song.mid',
        profileId: 'profile',
        variantId: 'variant',
        layoutId: 'layout',
        steps: const <TransformStep>[],
      ),
      executablePlan: const ExecutablePlan(
        backendId: 'android-accessibility',
        totalDurationMs: 1000,
        actions: <ExecutableAction>[
          ExecutableAction(
            atMs: 100,
            durationMs: 0,
            kind: ExecutableActionKind.touchPoints,
            payload: <String, Object?>{
              'calibrated': true,
              'points': <Object?>[],
            },
          ),
        ],
      ),
      orientation: 'landscape',
      targetPackageName: null,
      physicalWidthPx: 2400,
      physicalHeightPx: 1080,
      displayRotation: 1,
      viewportPx: (left: 20, top: 0, right: 2380, bottom: 1080),
    );

    final result = await platform.start(
      playback: playback,
      playbackId: 'playback-1',
      positionMs: 120,
      speed: 1.25,
      timingOffsetMs: -35,
      tapDurationMs: 10,
    );

    expect(result.success, isTrue);
    expect(result.positionMs, 120);
    expect(received?.method, 'start');
    final arguments = Map<String, Object?>.from(received!.arguments as Map);
    expect(arguments, isNot(contains('targetPackageName')));
    expect(arguments['physicalWidthPx'], 2400);
    expect(arguments['physicalHeightPx'], 1080);
    expect(arguments['displayRotation'], 1);
    expect(arguments['viewportPx'], <double>[20, 0, 2380, 1080]);
    expect(arguments['timingOffsetMs'], -35);
    expect(arguments['tapDurationMs'], 10);
    expect((arguments['plan'] as Map)['backendId'], 'android-accessibility');
  });
}
