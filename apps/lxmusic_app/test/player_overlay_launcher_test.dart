import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/game_player/models/game_player_snapshot.dart';
import 'package:lxmusic_app/features/game_player/overlay/platform/player_overlay_platform.dart';
import 'package:lxmusic_app/features/game_player/overlay/widgets/player_overlay_launcher_button.dart';

void main() {
  testWidgets('launcher opens overlay when accessibility service is ready', (
    tester,
  ) async {
    final platform = _FakePlayerOverlayPlatform(
      const PlayerOverlayPlatformState(
        supported: true,
        accessibilityEnabled: true,
        serviceReady: true,
        overlayVisible: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerOverlayPlatformProvider.overrideWithValue(platform)],
        child: const MaterialApp(
          home: Scaffold(floatingActionButton: PlayerOverlayLauncherButton()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('player-overlay-launcher')));
    await tester.pump();
    await tester.pump();

    expect(platform.showCount, 1);
    expect(platform.lastRequest?.title, '暂无曲目');
    expect(platform.lastRequest?.durationMs, 1);
  });

  testWidgets('launcher explains and opens accessibility settings', (
    tester,
  ) async {
    final platform = _FakePlayerOverlayPlatform(
      const PlayerOverlayPlatformState(
        supported: true,
        accessibilityEnabled: false,
        serviceReady: false,
        overlayVisible: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerOverlayPlatformProvider.overrideWithValue(platform)],
        child: const MaterialApp(
          home: Scaffold(floatingActionButton: PlayerOverlayLauncherButton()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('player-overlay-launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('启用游戏内悬浮播放器'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '前往设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.openSettingsCount, 1);
    expect(platform.showCount, 0);
  });

  testWidgets('does not lose resumed launch while settings call is pending', (
    tester,
  ) async {
    final settingsCompleter = Completer<void>();
    final platform = _FakePlayerOverlayPlatform(
      const PlayerOverlayPlatformState(
        supported: true,
        accessibilityEnabled: false,
        serviceReady: false,
        overlayVisible: false,
      ),
    )..openSettingsCompleter = settingsCompleter;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerOverlayPlatformProvider.overrideWithValue(platform)],
        child: const MaterialApp(
          home: Scaffold(floatingActionButton: PlayerOverlayLauncherButton()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('player-overlay-launcher')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '前往设置'));
    await tester.pump();

    platform.state = const PlayerOverlayPlatformState(
      supported: true,
      accessibilityEnabled: true,
      serviceReady: true,
      overlayVisible: false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    settingsCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(platform.showCount, 1);
  });
}

class _FakePlayerOverlayPlatform implements PlayerOverlayPlatform {
  _FakePlayerOverlayPlatform(this.state);

  PlayerOverlayPlatformState state;
  Completer<void>? openSettingsCompleter;
  int showCount = 0;
  int openSettingsCount = 0;
  PlayerOverlayRequest? lastRequest;
  PlayerOverlayActionHandler? actionHandler;

  @override
  Future<PlayerOverlayPlatformState> getState() async => state;

  @override
  Future<PlayerOverlayCommandResult> showOverlay(
    PlayerOverlayRequest request,
  ) async {
    showCount++;
    lastRequest = request;
    return const PlayerOverlayCommandResult(success: true);
  }

  @override
  Future<void> hideOverlay() async {}

  @override
  Future<void> updateOverlay(GamePlayerSnapshot snapshot) async {}

  @override
  void setActionHandler(PlayerOverlayActionHandler? handler) {
    actionHandler = handler;
  }

  @override
  void dispose() {}

  @override
  Future<void> openAccessibilitySettings() async {
    openSettingsCount++;
    await openSettingsCompleter?.future;
  }
}
