import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/calibration/platform/calibration_platform.dart';
import 'package:lxmusic_app/features/game_player/models/game_player_snapshot.dart';
import 'package:lxmusic_app/features/game_player/overlay/models/player_overlay_state.dart';
import 'package:lxmusic_app/features/game_player/overlay/player_overlay_app.dart';
import 'package:lxmusic_app/features/game_player/overlay/platform/player_overlay_bridge.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/widgets/current_target_action.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets('switches between compact, quick controls, and speed editor', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-compact')),
      findsOneWidget,
    );
    expect(find.text('测试曲目'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('player-overlay-more')));
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-quick-controls')),
      findsOneWidget,
    );
    expect(find.text('播放'), findsNothing);
    expect(find.text('演奏'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(bridge.sizes.last, const PlayerOverlayWindowSize(420, 251));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('player-overlay-more')));
    await _setSurfaceSize(tester, 420, 82);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-speed')));
    await _setSurfaceSize(tester, 420, 217);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-speed-editor')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-overlay-speed-1.50')));
    await tester.pump();
    expect(find.textContaining('180 BPM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-overlay-speed-reset')));
    await tester.pump();
    expect(find.text('1.00×  ·  120 BPM'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('player-overlay-speed-slider')),
          )
          .value,
      closeTo(0.5, 0.0001),
    );
    await tester.tap(find.byKey(const ValueKey('player-overlay-speed')));
    await _setSurfaceSize(tester, 420, 82);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-compact')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows performance settings and closes from display controls', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-more')));
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-key-config-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-overlay-key-config-calibrate')),
      findsOneWidget,
    );
    for (final mode in <String>['自动演奏', '点击演奏', '可视化跟弹', 'MIDI串流']) {
      expect(find.text(mode), findsOneWidget);
    }
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-performance-mode-1')),
    );
    await tester.pump();
    expect(find.text('点击演奏模式敬请期待'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-action-octave')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-octave-editor')),
      findsOneWidget,
    );
    for (final label in <String>['低二八度', '低一八度', '原调', '高一八度', '高二八度']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-octave-plus-24')),
    );
    await tester.pump();
    expect(
      bridge.actions,
      contains(
        predicate<Map<String, Object?>>(
          (action) =>
              action['type'] == 'setTranspose' && action['transpose'] == 24,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('player-overlay-submenu-back')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-quick-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('player-overlay-compact')), findsNothing);
    expect(bridge.sizes.last, const PlayerOverlayWindowSize(420, 251));
    expect(find.text('音域调整'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-action-duration-mode')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-duration-editor')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-duration-mode-repeatedTap')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-duration-description')),
      findsOneWidget,
    );
    expect(find.textContaining('把长音拆成连续点击'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-duration-mode-longPress')),
    );
    await tester.pump();
    expect(find.textContaining('按音符真实时长'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('显示'));
    await tester.pump();
    expect(find.text('位置锁定'), findsNothing);
    expect(find.text('副标题显示'), findsOneWidget);
    expect(find.text('敬请期待'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('player-overlay-action-display-mode')),
          )
          .onTap,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-action-resize')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-resize-handle')),
      findsOneWidget,
    );
    expect(bridge.resizeModes, <bool>[true]);
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-action-resize')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-resize-handle')),
      findsNothing,
    );
    expect(bridge.resizeModes, <bool>[true, false]);
    await tester.tap(find.byKey(const ValueKey('player-overlay-action-close')));
    await tester.pump();

    expect(bridge.closeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title, speed, and settings entries toggle independently', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('player-overlay-song-picker')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-overlay-more')));
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-quick-controls')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-overlay-speed')));
    await _setSurfaceSize(tester, 420, 217);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-speed-editor')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-overlay-speed')));
    await _setSurfaceSize(tester, 420, 82);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-compact')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reuses target picker and can launch calibration from overlay', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakePlayerOverlayBridge();
    final calibrationPlatform = _FakeCalibrationPlatform();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(loadTestYamlAssetBundle()),
          sharedPreferencesProvider.overrideWithValue(preferences),
          calibrationPlatformProvider.overrideWithValue(calibrationPlatform),
          calibrationRepositoryProvider.overrideWithValue(
            _MemoryCalibrationRepository(),
          ),
          persistedTargetSelectionProvider.overrideWithValue(
            const PersistedTargetSelection(
              profileId: 'generic_demo',
              variantId: 'default',
              layoutId: 'generic_3x7_demo',
            ),
          ),
          initialPersistedProfileUsageProvider.overrideWithValue(
            const PersistedProfileUsage(<String, int>{}),
          ),
        ],
        child: PlayerOverlayApp(bridge: bridge),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-more')));
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('演奏'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('player-overlay-key-config-switch')),
    );
    await _setSurfaceSize(tester, 440, 300);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('player-overlay-target-picker')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CurrentTargetPickerSheet>(
            find.byType(CurrentTargetPickerSheet),
          )
          .compact,
      isTrue,
    );
    expect(bridge.sizes.last, const PlayerOverlayWindowSize(440, 300));
    expect(find.byKey(const ValueKey('target-filter-profile')), findsOneWidget);
    expect(find.text('LxMusic-NG Demo / 默认 / 3x7 Demo'), findsOneWidget);
    expect(bridge.actions.first['type'], 'prepareTargetSelection');
    expect(bridge.targetPickerActiveStates, <bool>[true]);

    await tester.tap(find.widgetWithText(ListTile, 'LxMusic-NG Demo'));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('默认'));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('3x7 Demo'));
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump(const Duration(milliseconds: 300));

    final selectAction = bridge.actions.lastWhere(
      (action) => action['type'] == 'selectTarget',
    );
    expect(selectAction['profileId'], 'generic_demo');
    expect(selectAction['variantId'], 'default');
    expect(selectAction['layoutId'], 'generic_3x7_demo');
    expect(bridge.targetPickerActiveStates, <bool>[true, false]);

    await tester.pump();
    final calibrationButton = find.byKey(
      const ValueKey('player-overlay-key-config-calibrate'),
    );
    expect(
      tester.widget<ButtonStyleButton>(calibrationButton).onPressed,
      isNotNull,
    );
    await tester.tap(calibrationButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      bridge.actions.map((action) => action['type']),
      contains('calibrationStartCurrentTarget'),
    );
    await _setSurfaceSize(tester, 420, 251);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-quick-controls')),
      findsOneWidget,
    );
    expect(bridge.targetPickerActiveStates, <bool>[true, false]);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('collapses to mini with one combined drag and expand handle', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-drag-handle')));
    await _setSurfaceSize(tester, 104, 58);
    await tester.pump();

    expect(find.byKey(const ValueKey('player-overlay-mini')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player-overlay-mini-play')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-overlay-mini-expand')),
      findsOneWidget,
    );
    expect(find.text('1.25×'), findsNothing);
    expect(bridge.sizes.last, const PlayerOverlayWindowSize(104, 58));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sends one seek only after compact progress drag ends', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();

    final progress = find.byKey(const ValueKey('player-overlay-progress'));
    final bounds = tester.getRect(progress);
    expect(bounds.height, greaterThanOrEqualTo(28));
    final gesture = await tester.startGesture(
      Offset(bounds.left + bounds.width * 0.2, bounds.center.dy),
    );
    await gesture.moveTo(
      Offset(bounds.left + bounds.width * 0.8, bounds.center.dy),
    );
    await tester.pump();

    expect(find.text('2:24'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('2:24'), findsOneWidget);
    expect(bridge.actions.where((action) => action['type'] == 'seek'), isEmpty);

    await gesture.up();
    await tester.pump();
    final seekActions = bridge.actions
        .where((action) => action['type'] == 'seek')
        .toList(growable: false);
    expect(seekActions, hasLength(1));
    expect(seekActions.single['positionMs'], 144000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores an older command response that completes last', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge()
      ..initialSession = _snapshot(fileName: '初始.mid').toMap()
      ..deferActions = true;
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    expect(find.text('初始'), findsOneWidget);

    final play = find.byKey(const ValueKey('player-overlay-play'));
    await tester.tap(play);
    await tester.pump();
    await tester.tap(play);
    await tester.pump();

    expect(bridge.actionCompleters, hasLength(2));
    expect(bridge.actions.map((action) => action['type']), <Object?>[
      'togglePlayback',
      'togglePlayback',
    ]);
    expect(bridge.actions.map((action) => action['commandId']), <Object?>[
      1,
      2,
    ]);

    bridge.completeAction(
      1,
      _snapshot(fileName: '新响应.mid', revision: 1).toMap(),
    );
    await tester.pump();
    expect(find.text('新响应'), findsOneWidget);

    bridge.completeAction(
      0,
      _snapshot(fileName: '旧响应.mid', revision: 1).toMap(),
    );
    await tester.pump();
    expect(find.text('新响应'), findsOneWidget);
    expect(find.text('旧响应'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song picker switches queue, favorites, history, and playlists', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge()
      ..initialSession = _songPickerSnapshot().toMap();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await tester.pump(const Duration(milliseconds: 350));
    await _setSurfaceSize(tester, 420, 82);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-compact')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('返回播放器'), findsNothing);
    expect(
      find.byKey(const ValueKey('player-overlay-song-picker-favorite')),
      findsNothing,
    );
    for (final tab in <String>['playlists', 'queue', 'favorites', 'history']) {
      expect(
        find.byKey(ValueKey('player-overlay-picker-tab-$tab')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-picker-tab-favorites')),
    );
    await tester.pump();
    expect(find.textContaining('还没有收藏的曲目'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-picker-tab-history')),
    );
    await tester.pump();
    expect(find.text('测试曲目'), findsAtLeastNWidgets(1));

    await tester.tap(
      find.byKey(const ValueKey('player-overlay-picker-tab-playlists')),
    );
    await tester.pump();
    expect(find.text('所有曲目'), findsAtLeastNWidgets(1));
    expect(find.text('中文曲目'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-overlay-playlist-2')));
    await tester.pump();
    expect(find.text('中文曲目'), findsOneWidget);
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('大鱼'), findsOneWidget);
    expect(find.text('Canon in D'), findsNothing);

    final mode = find.byKey(
      const ValueKey('player-overlay-song-picker-playback-mode'),
    );
    expect(mode, findsOneWidget);
    expect(find.text('列表循环'), findsOneWidget);

    await tester.tap(mode);
    await tester.pump();
    expect(find.text('单曲循环'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'double tapping the title toggles favorite without opening list',
    (tester) async {
      final bridge = _FakePlayerOverlayBridge();
      await _setSurfaceSize(tester, 420, 82);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
      await tester.pump();
      final title = find.byKey(const ValueKey('player-overlay-title'));
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(title);
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-overlay-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player-overlay-song-picker')),
        findsNothing,
      );

      await tester.tap(title);
      await _setSurfaceSize(tester, 420, 309);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(
        find.byKey(const ValueKey('player-overlay-picker-tab-favorites')),
      );
      await tester.pump();
      expect(find.text('测试曲目'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reflects native edge docking and undocking commands', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    await bridge.emit(<String, Object?>{
      'command': 'dockToEdge',
      'side': 'left',
    });
    await _setSurfaceSize(tester, 44, 58);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-edge-docked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-overlay-edge-progress')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await bridge.emit(<String, Object?>{'command': 'undockToPrevious'});
    await _setSurfaceSize(tester, 420, 82);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-overlay-compact')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the expanded picker after temporary edge docking', (
    tester,
  ) async {
    final bridge = _FakePlayerOverlayBridge();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('player-overlay-song-picker')),
      findsOneWidget,
    );

    await bridge.emit(<String, Object?>{
      'command': 'dockToEdge',
      'side': 'right',
    });
    await _setSurfaceSize(tester, 44, 58);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-edge-docked')),
      findsOneWidget,
    );

    await bridge.emit(<String, Object?>{'command': 'undockToPrevious'});
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-overlay-song-picker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a real snapshot and forwards selected track actions', (
    tester,
  ) async {
    final snapshot = GamePlayerSnapshot(
      tracks: const <GamePlayerTrack>[
        GamePlayerTrack(
          fileName: '卡农.mid',
          path: '/music/卡农.mid',
          formatId: 'midi',
          durationMs: 210000,
        ),
        GamePlayerTrack(
          fileName: 'Flower Dance.mid',
          path: '/music/Flower Dance.mid',
          formatId: 'midi',
          durationMs: 180000,
        ),
      ],
      playlists: const <GamePlayerPlaylistSnapshot>[
        GamePlayerPlaylistSnapshot(
          id: 'all',
          name: '所有曲目',
          fileNames: <String>['卡农.mid', 'Flower Dance.mid'],
        ),
      ],
      queuePlaylistId: 'all',
      queueFileNames: const <String>['卡农.mid', 'Flower Dance.mid'],
      favoriteFileNames: const <String>['卡农.mid'],
      historyFileNames: const <String>['卡农.mid'],
      currentFileName: '卡农.mid',
      positionMs: 30000,
      isPlaying: false,
      speed: 1,
      playbackModeIndex: 1,
    );
    final bridge = _FakePlayerOverlayBridge()
      ..initialSession = snapshot.toMap();
    await _setSurfaceSize(tester, 420, 82);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(PlayerOverlayApp(bridge: bridge));
    await tester.pump();

    expect(find.text('卡农'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-overlay-title')));
    await _setSurfaceSize(tester, 420, 309);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('player-overlay-song-queue-1')));
    await tester.pump();

    expect(
      bridge.actions,
      contains(
        predicate<Map<String, Object?>>(
          (action) =>
              action['type'] == 'selectTrack' &&
              action['fileName'] == 'Flower Dance.mid',
        ),
      ),
    );
  });
}

Future<void> _setSurfaceSize(
  WidgetTester tester,
  double width,
  double height,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
}

GamePlayerSnapshot _snapshot({required String fileName, int revision = 0}) {
  return GamePlayerSnapshot(
    tracks: <GamePlayerTrack>[
      GamePlayerTrack(
        fileName: fileName,
        path: '/music/$fileName',
        formatId: 'midi',
        durationMs: 180000,
      ),
    ],
    playlists: <GamePlayerPlaylistSnapshot>[
      GamePlayerPlaylistSnapshot(
        id: 'all',
        name: '所有曲目',
        fileNames: <String>[fileName],
      ),
    ],
    queuePlaylistId: 'all',
    queueFileNames: <String>[fileName],
    favoriteFileNames: const <String>[],
    historyFileNames: <String>[fileName],
    currentFileName: fileName,
    positionMs: 30000,
    isPlaying: false,
    speed: 1,
    playbackModeIndex: 1,
    revision: revision,
  );
}

GamePlayerSnapshot _songPickerSnapshot() {
  const tracks = <GamePlayerTrack>[
    GamePlayerTrack(
      fileName: '测试曲目.mid',
      path: '/music/测试曲目.mid',
      formatId: 'midi',
      durationMs: 180000,
    ),
    GamePlayerTrack(
      fileName: '夜空中最亮的星.mid',
      path: '/music/夜空中最亮的星.mid',
      formatId: 'midi',
      durationMs: 248000,
    ),
    GamePlayerTrack(
      fileName: '大鱼.mid',
      path: '/music/大鱼.mid',
      formatId: 'midi',
      durationMs: 312000,
    ),
    GamePlayerTrack(
      fileName: 'Canon in D.mid',
      path: '/music/Canon in D.mid',
      formatId: 'midi',
      durationMs: 271000,
    ),
  ];
  return const GamePlayerSnapshot(
    tracks: tracks,
    playlists: <GamePlayerPlaylistSnapshot>[
      GamePlayerPlaylistSnapshot(
        id: 'all',
        name: '所有曲目',
        fileNames: <String>[
          '测试曲目.mid',
          '夜空中最亮的星.mid',
          '大鱼.mid',
          'Canon in D.mid',
        ],
      ),
      GamePlayerPlaylistSnapshot(
        id: 'practice',
        name: '钢琴练习',
        fileNames: <String>['测试曲目.mid', 'Canon in D.mid'],
      ),
      GamePlayerPlaylistSnapshot(
        id: 'chinese',
        name: '中文曲目',
        fileNames: <String>['夜空中最亮的星.mid', '大鱼.mid'],
      ),
    ],
    queuePlaylistId: 'all',
    queueFileNames: <String>[
      '测试曲目.mid',
      '夜空中最亮的星.mid',
      '大鱼.mid',
      'Canon in D.mid',
    ],
    favoriteFileNames: <String>[],
    historyFileNames: <String>['测试曲目.mid'],
    currentFileName: '测试曲目.mid',
    positionMs: 30000,
    isPlaying: false,
    speed: 1,
    playbackModeIndex: 1,
    revision: 0,
  );
}

class _FakePlayerOverlayBridge implements PlayerOverlayBridge {
  final List<PlayerOverlayWindowSize> sizes = <PlayerOverlayWindowSize>[];
  final List<Map<String, Object?>> actions = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> actionCompleters =
      <Completer<Map<String, Object?>>>[];
  int closeCount = 0;
  bool deferActions = false;
  final List<bool> targetPickerActiveStates = <bool>[];
  final List<bool> resizeModes = <bool>[];
  PlayerOverlaySessionHandler? sessionHandler;
  Map<String, Object?>? initialSession;

  void completeAction(int index, Map<String, Object?> snapshot) {
    actionCompleters[index].complete(snapshot);
  }

  @override
  Future<Map<String, Object?>> loadInitialSession() async {
    return initialSession ??
        <String, Object?>{
          'title': '测试曲目',
          'durationMs': 180000,
          'profileLabel': '光遇 · 15 键',
        };
  }

  @override
  void setSessionHandler(PlayerOverlaySessionHandler? handler) {
    sessionHandler = handler;
  }

  Future<void> emit(Map<String, Object?> session) async {
    await sessionHandler?.call(session);
  }

  @override
  Future<void> resize(
    PlayerOverlayWindowSize size, {
    bool animate = true,
  }) async {
    sizes.add(size);
  }

  @override
  Future<void> moveBy(double deltaX, double deltaY) async {}

  @override
  Future<void> setResizeMode(bool enabled) async {
    resizeModes.add(enabled);
  }

  @override
  Future<void> setTargetPickerActive(bool active) async {
    targetPickerActiveStates.add(active);
  }

  @override
  Future<Map<String, Object?>> sendAction(Map<String, Object?> action) async {
    actions.add(action);
    if (deferActions) {
      final completer = Completer<Map<String, Object?>>();
      actionCompleters.add(completer);
      return completer.future;
    }
    return const <String, Object?>{};
  }

  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  void dispose() {}
}

class _FakeCalibrationPlatform implements CalibrationPlatform {
  final List<CalibrationSessionRequest> startRequests =
      <CalibrationSessionRequest>[];

  @override
  Future<CalibrationPlatformState> getState() async {
    return const CalibrationPlatformState(
      supported: true,
      accessibilityEnabled: true,
      apiLevel: 36,
      deviceId: 'android-test',
      deviceDisplayName: 'Android Test',
      viewportWidthPx: 1080,
      viewportHeightPx: 1920,
      density: 1,
      displayRotation: 0,
    );
  }

  @override
  Future<List<LaunchableCalibrationTarget>> findLaunchableTargets(
    List<String> packageNameHints,
  ) async {
    return const <LaunchableCalibrationTarget>[
      LaunchableCalibrationTarget(packageName: 'test.game', label: '测试游戏'),
    ];
  }

  @override
  Future<CalibrationSessionResult> startSession(
    CalibrationSessionRequest request,
  ) async {
    startRequests.add(request);
    return CalibrationSessionResult(
      status: CalibrationSessionStatus.started,
      sessionId: request.sessionId,
    );
  }

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> cancelSession() async {}

  @override
  Future<CalibrationSessionResult?> consumePendingResult() async => null;
}

class _MemoryCalibrationRepository implements MutableCalibrationRepository {
  final Map<CalibrationKey, Calibration> _calibrations =
      <CalibrationKey, Calibration>{};

  @override
  Future<void> delete(CalibrationKey key) async {
    _calibrations.remove(key);
  }

  @override
  List<Calibration> list() => _calibrations.values.toList(growable: false);

  @override
  Calibration? load(CalibrationKey key) => _calibrations[key];

  @override
  Future<void> save(Calibration calibration) async {
    _calibrations[calibration.key] = calibration;
  }
}
