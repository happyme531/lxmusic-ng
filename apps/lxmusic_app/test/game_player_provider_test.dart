import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/game_player/models/game_player_snapshot.dart';
import 'package:lxmusic_app/features/game_player/platform/accessibility_playback_platform.dart';
import 'package:lxmusic_app/features/game_player/providers/game_player_provider.dart';
import 'package:lxmusic_app/features/game_player/services/game_playback_plan_service.dart';
import 'package:lxmusic_app/features/library/models/library_playlist.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/library/providers/music_library_provider.dart';
import 'package:lxmusic_app/features/workbench/models/song_config.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('playback cache key canonicalizes config map ordering', () {
    final first = _songConfig(
      fileName: 'a.mid',
      steps: const <TransformStep>[
        TransformStep(type: 'humanify', config: {'b': 2, 'a': 1}),
      ],
    );
    final second = _songConfig(
      fileName: 'a.mid',
      steps: const <TransformStep>[
        TransformStep(type: 'humanify', config: {'a': 1, 'b': 2}),
      ],
    );
    final file = MusicFile(
      path: '/music/a.mid',
      fileName: 'a.mid',
      formatId: 'midi',
      durationMs: 1000,
    );

    expect(
      gamePlaybackCacheKey(
        file: file,
        profile: _profile,
        variant: _variant,
        layout: _layout,
        config: first,
      ),
      gamePlaybackCacheKey(
        file: file,
        profile: _profile,
        variant: _variant,
        layout: _layout,
        config: second,
      ),
    );
  });

  test(
    'uses the real library for queue, favorites, history, and selection',
    () async {
      final library = MusicLibraryState(
        files: <MusicFile>[
          MusicFile(
            path: '/music/a.mid',
            fileName: 'a.mid',
            formatId: 'midi',
            durationMs: 1000,
          ),
          MusicFile(
            path: '/music/b.mid',
            fileName: 'b.mid',
            formatId: 'midi',
            durationMs: 2000,
          ),
        ],
        playlists: const <LibraryPlaylist>[
          LibraryPlaylist(
            id: favoritesPlaylistId,
            name: '收藏',
            musicFileNames: <String>['a.mid'],
            isBuiltinFavorite: true,
          ),
          LibraryPlaylist(
            id: 'practice',
            name: '练习',
            musicFileNames: <String>['b.mid'],
          ),
        ],
        currentPlaylistId: allSongsPlaylistId,
      );
      final playbackPlatform = _FakeAccessibilityPlaybackPlatform();
      final config = _songConfig(fileName: 'b.mid');
      final planService = _FakeGamePlaybackPlanService(config: config);
      final container = ProviderContainer(
        overrides: [
          musicLibraryProvider.overrideWith(
            () => _StaticMusicLibraryNotifier(library),
          ),
          accessibilityPlaybackPlatformProvider.overrideWithValue(
            playbackPlatform,
          ),
          gamePlaybackPlanServiceProvider.overrideWithValue(planService),
          songConfigProvider.overrideWith(
            () => _StaticSongConfigNotifier(config),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(musicLibraryProvider.future);
      container.read(selectedProfileProvider.notifier).select(_profile);
      container.read(selectedVariantProvider.notifier).select(_variant);
      container.read(selectedLayoutProvider.notifier).select(_layout);

      var snapshot = container.read(gamePlayerProvider);
      expect(snapshot.tracks.map((track) => track.fileName), [
        'a.mid',
        'b.mid',
      ]);
      expect(snapshot.favoriteFileNames, ['a.mid']);
      expect(snapshot.currentFileName, 'a.mid');

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{
          'type': 'selectPlaylist',
          'playlistId': 'practice',
        },
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'selectTrack', 'fileName': 'b.mid'},
      );

      snapshot = container.read(gamePlayerProvider);
      expect(snapshot.queueFileNames, ['b.mid']);
      expect(snapshot.currentFileName, 'b.mid');
      expect(snapshot.historyFileNames.first, 'b.mid');
      expect(container.read(selectedFileProvider)?.fileName, 'b.mid');

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      snapshot = container.read(gamePlayerProvider);
      expect(snapshot.positionMs, greaterThan(0));
      expect(snapshot.isPlaying, isTrue);
      expect(playbackPlatform.startPositions, [0]);
      expect(snapshot.durationMs, 2500);

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'seek', 'positionMs': 2200},
      );
      snapshot = container.read(gamePlayerProvider);
      expect(playbackPlatform.pauseCalls, 1);
      expect(playbackPlatform.startPositions, [0, 2200]);
      expect(snapshot.positionMs, 2200);
      expect(snapshot.isPlaying, isTrue);

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{
          'type': 'setTimingOffset',
          'timingOffsetMs': 75,
        },
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{
          'type': 'setTouchDuration',
          'touchDurationPercent': 50,
        },
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{
          'type': 'setDurationMode',
          'durationMode': 'repeatedTap',
        },
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'setTranspose', 'transpose': 3},
      );
      snapshot = container.read(gamePlayerProvider);
      expect(playbackPlatform.timingOffsets.last, 75);
      expect(playbackPlatform.tapDurations.last, 6);
      expect(planService.transposes, [0, 0, 3]);
      expect(planService.durationModes, <GamePlayerDurationMode>[
        GamePlayerDurationMode.shortPress,
        GamePlayerDurationMode.repeatedTap,
        GamePlayerDurationMode.repeatedTap,
      ]);
      expect(snapshot.transpose, 3);
      expect(snapshot.timingOffsetMs, 75);
      expect(snapshot.touchDurationPercent, 50);
      expect(snapshot.durationMode, GamePlayerDurationMode.repeatedTap);
    },
  );

  test(
    'does not reuse a prepared plan after the current config changes',
    () async {
      final config = _songConfig(fileName: 'a.mid');
      final planService = _FakeGamePlaybackPlanService(config: config);
      final playbackPlatform = _FakeAccessibilityPlaybackPlatform();
      final container = _playerContainer(
        planService: planService,
        playbackPlatform: playbackPlatform,
        config: config,
      );
      addTearDown(container.dispose);
      await _selectTestTarget(container);
      await container.read(songConfigProvider.future);

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );
      final firstCacheKey = playbackPlatform.startedCacheKeys.single;

      // SongConfig is intentionally mutable. Even if an editor mutates the same
      // object instance, the immutable cache key captured by the old prepared
      // plan must no longer match its current serialized contents.
      config.speed = 1.25;

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );

      expect(planService.transposes, <int>[0, 0]);
      expect(playbackPlatform.startedCacheKeys.last, isNot(firstCacheKey));
    },
  );

  test('retries when config changes while prepare is in flight', () async {
    final config = _songConfig(fileName: 'a.mid');
    final planService = _DelayedGamePlaybackPlanService(config);
    final playbackPlatform = _FakeAccessibilityPlaybackPlatform();
    final container = _playerContainer(
      planService: planService,
      playbackPlatform: playbackPlatform,
      config: config,
    );
    addTearDown(container.dispose);
    await _selectTestTarget(container);
    await container.read(songConfigProvider.future);

    final start = container
        .read(gamePlayerProvider.notifier)
        .handleOverlayAction(const <String, Object?>{'type': 'togglePlayback'});
    await _waitFor(() => planService.callCount == 1);

    config.speed = 1.25;
    planService.complete(0);
    await _waitFor(() => planService.callCount == 2);
    expect(playbackPlatform.startPositions, isEmpty);

    planService.complete(1);
    await start;
    expect(planService.transposes, <int>[0, 0]);
    expect(playbackPlatform.startPositions, <int>[0]);
    expect(
      playbackPlatform.startedCacheKeys.single,
      gamePlaybackCacheKey(
        file: container.read(musicLibraryProvider).requireValue.files.single,
        profile: _profile,
        variant: _variant,
        layout: _layout,
        config: config,
      ),
    );
  });

  test(
    'rebase actions cancel an in-flight prepare and only start the new plan',
    () async {
      final scenarios = <Map<String, Object?>>[
        const <String, Object?>{'type': 'seek', 'positionMs': 700},
        const <String, Object?>{'type': 'setSpeed', 'speed': 1.5},
        const <String, Object?>{'type': 'setTranspose', 'transpose': 3},
        const <String, Object?>{
          'type': 'setTimingOffset',
          'timingOffsetMs': 75,
        },
        const <String, Object?>{
          'type': 'setTouchDuration',
          'touchDurationPercent': 50,
        },
      ];

      for (final action in scenarios) {
        final config = _songConfig(fileName: 'a.mid');
        final planService = _DelayedGamePlaybackPlanService(config);
        final playbackPlatform = _FakeAccessibilityPlaybackPlatform();
        final container = _playerContainer(
          planService: planService,
          playbackPlatform: playbackPlatform,
          config: config,
        );
        await _selectTestTarget(container);
        await container.read(songConfigProvider.future);

        final initialStart = container
            .read(gamePlayerProvider.notifier)
            .handleOverlayAction(const <String, Object?>{
              'type': 'togglePlayback',
            });
        await _waitFor(() => planService.callCount == 1);

        final rebasedStart = container
            .read(gamePlayerProvider.notifier)
            .handleOverlayAction(action);
        await _waitFor(() => planService.callCount == 2);

        planService.complete(0);
        await initialStart;
        expect(
          playbackPlatform.startPositions,
          isEmpty,
          reason: '${action['type']} let the stale prepare start playback',
        );

        planService.complete(1);
        await rebasedStart;
        expect(
          playbackPlatform.startPositions,
          hasLength(1),
          reason: '${action['type']} did not start the replacement plan',
        );
        switch (action['type']) {
          case 'seek':
            expect(playbackPlatform.startPositions.single, 700);
          case 'setSpeed':
            expect(playbackPlatform.speeds.single, 1.5);
          case 'setTranspose':
            expect(planService.transposes, <int>[0, 3]);
          case 'setTimingOffset':
            expect(playbackPlatform.timingOffsets.single, 75);
          case 'setTouchDuration':
            expect(playbackPlatform.tapDurations.single, 6);
        }
        container.dispose();
      }
    },
  );

  test(
    'keeps the last planned duration while a same-song plan is invalid',
    () async {
      final config = _songConfig(fileName: 'a.mid');
      final planService = _FakeGamePlaybackPlanService(config: config);
      final playbackPlatform = _FakeAccessibilityPlaybackPlatform()
        ..pausePositionMs = 1400;
      final container = _playerContainer(
        planService: planService,
        playbackPlatform: playbackPlatform,
        config: config,
      );
      addTearDown(container.dispose);
      await _selectTestTarget(container);
      await container.read(songConfigProvider.future);

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'seek', 'positionMs': 1400},
      );
      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'togglePlayback'},
      );

      await container.read(gamePlayerProvider.notifier).handleOverlayAction(
        const <String, Object?>{'type': 'setTranspose', 'transpose': 2},
      );
      var snapshot = container.read(gamePlayerProvider);
      expect(snapshot.positionMs, 1400);
      expect(snapshot.durationMs, 1500);

      container.read(selectedVariantProvider.notifier).select(_secondVariant);
      snapshot = container.read(gamePlayerProvider);
      expect(snapshot.positionMs, 1400);
      expect(snapshot.durationMs, 1500);
    },
  );
}

SongConfig _songConfig({
  required String fileName,
  List<TransformStep> steps = const <TransformStep>[],
}) => SongConfig(
  fileName: fileName,
  profileId: _profile.id,
  variantId: _variant.id,
  layoutId: _layout.id,
  steps: steps,
);

ProviderContainer _playerContainer({
  required GamePlaybackPlanService planService,
  required _FakeAccessibilityPlaybackPlatform playbackPlatform,
  required SongConfig config,
}) {
  return ProviderContainer(
    overrides: [
      musicLibraryProvider.overrideWith(
        () => _StaticMusicLibraryNotifier(
          MusicLibraryState(
            files: <MusicFile>[
              MusicFile(
                path: '/music/a.mid',
                fileName: 'a.mid',
                formatId: 'midi',
                durationMs: 1000,
              ),
            ],
            playlists: const <LibraryPlaylist>[
              LibraryPlaylist(
                id: favoritesPlaylistId,
                name: '收藏',
                musicFileNames: <String>[],
                isBuiltinFavorite: true,
              ),
            ],
            currentPlaylistId: allSongsPlaylistId,
          ),
        ),
      ),
      accessibilityPlaybackPlatformProvider.overrideWithValue(playbackPlatform),
      gamePlaybackPlanServiceProvider.overrideWithValue(planService),
      songConfigProvider.overrideWith(() => _StaticSongConfigNotifier(config)),
    ],
  );
}

Future<void> _selectTestTarget(ProviderContainer container) async {
  await container.read(musicLibraryProvider.future);
  container
      .read(selectedFileProvider.notifier)
      .select(container.read(musicLibraryProvider).requireValue.files.single);
  container.read(selectedProfileProvider.notifier).select(_profile);
  container.read(selectedVariantProvider.notifier).select(_variant);
  container.read(selectedLayoutProvider.notifier).select(_layout);
  container.read(gamePlayerProvider);
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition was not reached in time');
}

const _variant = InstrumentVariant(
  id: 'piano',
  displayName: '钢琴',
  noteDurationMode: NoteDurationMode.none,
);

const _secondVariant = InstrumentVariant(
  id: 'second-piano',
  displayName: '第二钢琴',
  noteDurationMode: NoteDurationMode.none,
);

const _layout = KeyLayout(
  id: 'layout',
  algorithm: LayoutAlgorithm.explicit,
  keys: <KeyDefinition>[],
  pitchToKeyId: <int, String>{},
);

const _profile = GameProfile(
  id: 'game',
  displayName: '测试游戏',
  packageNameHints: <String>['example'],
  layouts: <LayoutBinding>[LayoutBinding(layoutId: 'layout')],
  variants: <InstrumentVariant>[_variant],
  sameKeyMinIntervalMs: 8,
);

class _FakeGamePlaybackPlanService implements GamePlaybackPlanService {
  _FakeGamePlaybackPlanService({this.config});

  final List<int> transposes = <int>[];
  final List<GamePlayerDurationMode> durationModes = <GamePlayerDurationMode>[];
  final SongConfig? config;

  @override
  Future<PreparedGamePlayback> prepare({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    int additionalPitchOffset = 0,
    GamePlayerDurationMode durationMode = GamePlayerDurationMode.shortPress,
  }) async {
    transposes.add(additionalPitchOffset);
    durationModes.add(durationMode);
    final resolvedConfig =
        config ??
        SongConfig(
          fileName: file.fileName,
          profileId: profile.id,
          variantId: variant.id,
          layoutId: layout.id,
          steps: const <TransformStep>[],
        );
    return PreparedGamePlayback(
      fileName: file.fileName,
      cacheKey: gamePlaybackCacheKey(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
        config: resolvedConfig,
        additionalPitchOffset: additionalPitchOffset,
        durationMode: durationMode,
      ),
      config: resolvedConfig,
      executablePlan: ExecutablePlan(
        backendId: 'android-accessibility',
        actions: const <ExecutableAction>[],
        totalDurationMs: file.durationMs + 500,
      ),
      orientation: 'landscape',
      targetPackageName: 'com.example.game',
      physicalWidthPx: 2400,
      physicalHeightPx: 1080,
      displayRotation: 1,
      viewportPx: (left: 0, top: 0, right: 2400, bottom: 1080),
    );
  }
}

class _DelayedGamePlaybackPlanService implements GamePlaybackPlanService {
  _DelayedGamePlaybackPlanService(this.config);

  final SongConfig config;
  final List<int> transposes = <int>[];
  final List<Completer<PreparedGamePlayback>> _completers =
      <Completer<PreparedGamePlayback>>[];
  final List<
    ({
      MusicFile file,
      GameProfile profile,
      InstrumentVariant variant,
      KeyLayout layout,
      int transpose,
      String cacheKey,
    })
  >
  _calls = [];

  int get callCount => _calls.length;

  @override
  Future<PreparedGamePlayback> prepare({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    int additionalPitchOffset = 0,
    GamePlayerDurationMode durationMode = GamePlayerDurationMode.shortPress,
  }) {
    transposes.add(additionalPitchOffset);
    _calls.add((
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
      transpose: additionalPitchOffset,
      cacheKey: gamePlaybackCacheKey(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
        config: config,
        additionalPitchOffset: additionalPitchOffset,
        durationMode: durationMode,
      ),
    ));
    final completer = Completer<PreparedGamePlayback>();
    _completers.add(completer);
    return completer.future;
  }

  void complete(int index) {
    final call = _calls[index];
    _completers[index].complete(
      PreparedGamePlayback(
        fileName: call.file.fileName,
        cacheKey: call.cacheKey,
        config: config,
        executablePlan: ExecutablePlan(
          backendId: 'android-accessibility',
          actions: const <ExecutableAction>[],
          totalDurationMs: call.file.durationMs + 500,
        ),
        orientation: 'landscape',
        targetPackageName: 'com.example.game',
        physicalWidthPx: 2400,
        physicalHeightPx: 1080,
        displayRotation: 1,
        viewportPx: (left: 0, top: 0, right: 2400, bottom: 1080),
      ),
    );
  }
}

class _FakeAccessibilityPlaybackPlatform
    implements AccessibilityPlaybackPlatform {
  AccessibilityPlaybackEventHandler? handler;
  final List<int> startPositions = <int>[];
  final List<String> startedCacheKeys = <String>[];
  final List<double> speeds = <double>[];
  final List<int> timingOffsets = <int>[];
  final List<int> tapDurations = <int>[];
  int pauseCalls = 0;
  int pausePositionMs = 0;

  @override
  Future<AccessibilityPlaybackResult> start({
    required PreparedGamePlayback playback,
    required String playbackId,
    required int positionMs,
    required double speed,
    required int timingOffsetMs,
    required int tapDurationMs,
  }) async {
    startPositions.add(positionMs);
    startedCacheKeys.add(playback.cacheKey);
    speeds.add(speed);
    timingOffsets.add(timingOffsetMs);
    tapDurations.add(tapDurationMs);
    return AccessibilityPlaybackResult(
      success: true,
      status: 'started',
      playbackId: playbackId,
      positionMs: positionMs,
    );
  }

  @override
  Future<AccessibilityPlaybackResult> getState() async =>
      const AccessibilityPlaybackResult(success: true, status: 'stopped');

  @override
  Future<AccessibilityPlaybackResult> pause() async {
    pauseCalls += 1;
    return AccessibilityPlaybackResult(
      success: true,
      status: 'paused',
      positionMs: pausePositionMs,
    );
  }

  @override
  Future<AccessibilityPlaybackResult> stop() async =>
      const AccessibilityPlaybackResult(success: true, status: 'stopped');

  @override
  void setEventHandler(AccessibilityPlaybackEventHandler? handler) {
    this.handler = handler;
  }

  @override
  void dispose() {}
}

class _StaticMusicLibraryNotifier extends MusicLibraryNotifier {
  _StaticMusicLibraryNotifier(this._state);

  final MusicLibraryState _state;

  @override
  Future<MusicLibraryState> build() async => _state;
}

class _StaticSongConfigNotifier extends SongConfigNotifier {
  _StaticSongConfigNotifier(this._config);

  final SongConfig _config;

  @override
  Future<SongConfig?> build() async => _config;
}
