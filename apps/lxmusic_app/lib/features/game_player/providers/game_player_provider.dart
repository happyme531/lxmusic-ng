import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_locator.dart';
import '../../calibration/providers/calibration_provider.dart';
import '../../library/models/music_file.dart';
import '../../library/providers/music_library_provider.dart';
import '../../workbench/providers/workbench_provider.dart';
import '../models/game_player_snapshot.dart';
import '../platform/accessibility_playback_platform.dart';
import '../services/game_playback_plan_service.dart';

const _gamePlayerStorageKey = 'game_player_state.v1';

final gamePlayerProvider =
    NotifierProvider<GamePlayerController, GamePlayerSnapshot>(
      GamePlayerController.new,
    );

class GamePlayerController extends Notifier<GamePlayerSnapshot> {
  Future<void>? _loadFuture;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch()..start();
  final Random _random = Random();
  AccessibilityPlaybackPlatform? _playbackPlatform;
  GamePlaybackPlanService? _planService;
  _GamePlayerCatalog? _catalog;
  PreparedGamePlayback? _preparedPlayback;
  String? _preparedInputKey;
  String? _contextKey;
  String? _activePlaybackId;
  String _queuePlaylistId = allSongsPlaylistId;
  String? _currentFileName;
  String? _lastSelectedFileName;
  List<String> _historyFileNames = <String>[];
  int _positionMs = 0;
  int _lastTickMs = 0;
  int _commandGeneration = 0;
  int _revision = 0;
  int? _planDurationMs;
  bool _isPlaying = false;
  bool _disposed = false;
  double _speed = 1;
  int _playbackModeIndex = 1;
  int _transpose = 0;
  int _timingOffsetMs = 0;
  int _touchDurationPercent = 100;
  GamePlayerDurationMode _durationMode = GamePlayerDurationMode.shortPress;
  String _playbackStatus = 'idle';
  String? _playbackError;
  int? _calibrationRevision;

  @override
  GamePlayerSnapshot build() {
    _disposed = false;
    final library = ref.watch(musicLibraryProvider).value;
    final selectedFile = ref.watch(selectedFileProvider);
    final profile = ref.watch(selectedProfileProvider);
    final variant = ref.watch(selectedVariantProvider);
    final layout = ref.watch(selectedLayoutProvider);
    final calibrationRevision = ref.watch(calibrationRevisionProvider);

    if (_calibrationRevision != null &&
        _calibrationRevision != calibrationRevision) {
      _invalidatePreparedPlan();
    }
    _calibrationRevision = calibrationRevision;

    final AccessibilityPlaybackPlatform platform =
        _playbackPlatform ?? ref.read(accessibilityPlaybackPlatformProvider);
    _playbackPlatform = platform;
    platform.setEventHandler(_handlePlaybackEvent);
    if (_lastTickMs == 0) {
      _lastTickMs = _clock.elapsedMilliseconds;
    }
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
      _ticker = null;
      platform.setEventHandler(null);
    });

    _loadFuture ??= _loadPersistedState();
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _advanceClock(),
    );

    final nextContextKey = <String?>[
      selectedFile?.path,
      profile?.id,
      variant?.id,
      layout?.id,
    ].join('|');
    if (_contextKey != null && _contextKey != nextContextKey) {
      _invalidatePreparedPlan();
      if (_isPlaying || _playbackStatus == 'preparing') {
        _commandGeneration += 1;
        _isPlaying = false;
        _playbackStatus = 'paused';
        unawaited(_safePlatformStop());
      }
    }
    _contextKey = nextContextKey;

    if (selectedFile != null &&
        selectedFile.fileName != _lastSelectedFileName) {
      _lastSelectedFileName = selectedFile.fileName;
      _currentFileName = selectedFile.fileName;
      _positionMs = 0;
      _invalidatePreparedPlan(clearDuration: true);
      _remember(selectedFile.fileName);
    }
    return _compose(
      library,
      selectedFile,
      profileLabel: _targetDisplayLabel(profile, variant, layout),
    );
  }

  Future<Map<String, Object?>> handleOverlayAction(
    Map<String, Object?> action,
  ) async {
    final actionType = action['type'] ?? 'unknown';
    final commandId = action['commandId'];
    final watch = Stopwatch()..start();
    _logPlayerAction(
      'phase=controller_enter type=$actionType command_id=$commandId',
    );
    await _loadFuture;
    _logPlayerAction(
      'phase=state_loaded type=$actionType command_id=$commandId '
      'elapsed_ms=${watch.elapsedMilliseconds}',
    );
    _syncClock();
    final deadlineUnixMs = (action['deadlineUnixMs'] as num?)?.toInt();
    if (_deadlineExpired(deadlineUnixMs)) {
      if (_isPlaying) {
        try {
          await _playbackPlatform!.pause();
        } catch (_) {
          await _safePlatformStop();
        }
      }
      _setPlaybackFailure('操作已超时，未执行自动点击。');
      return state.toOverlayActionMap();
    }
    switch (action['type']) {
      case 'togglePlayback':
        if (_isPlaying || _playbackStatus == 'preparing') {
          await _pauseExecution();
        } else {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'stop':
        await _stopExecution(resetPosition: true);
      case 'previous':
        await _selectRelativeAndMaybeResume(-1, deadlineUnixMs: deadlineUnixMs);
      case 'next':
        await _selectRelativeAndMaybeResume(1, deadlineUnixMs: deadlineUnixMs);
      case 'seek':
      case 'position':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        final durationMs = _effectiveDurationMs;
        _positionMs = ((action['positionMs'] as num?)?.toInt() ?? _positionMs)
            .clamp(0, max(0, durationMs));
        _markClock();
        _playbackError = null;
        _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'setSpeed':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        _speed = ((action['speed'] as num?)?.toDouble() ?? _speed).clamp(
          0.5,
          2,
        );
        _markClock();
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'setTranspose':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        _transpose = ((action['transpose'] as num?)?.toInt() ?? _transpose)
            .clamp(-24, 24);
        _invalidatePreparedPlan();
        _playbackError = null;
        _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'setTimingOffset':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        _timingOffsetMs =
            ((action['timingOffsetMs'] as num?)?.toInt() ?? _timingOffsetMs)
                .clamp(-200, 200);
        _playbackError = null;
        _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'setTouchDuration':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        _touchDurationPercent =
            ((action['touchDurationPercent'] as num?)?.toInt() ??
                    _touchDurationPercent)
                .clamp(40, 120);
        _playbackError = null;
        _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'setDurationMode':
        final resume = _hasActiveOrPendingExecution;
        if (resume) await _pauseForRebase();
        _durationMode = GamePlayerDurationMode.values.firstWhere(
          (mode) => mode.name == action['durationMode'],
          orElse: () => _durationMode,
        );
        _invalidatePreparedPlan();
        _playbackError = null;
        _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
        if (resume) {
          await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
        }
      case 'prepareTargetSelection':
        if (_hasActiveOrPendingExecution) {
          _logPlayerAction(
            'phase=target_prepare_pause_start command_id=$commandId '
            'status=$_playbackStatus',
          );
          await _pauseExecution();
          _logPlayerAction(
            'phase=target_prepare_pause_done command_id=$commandId '
            'elapsed_ms=${watch.elapsedMilliseconds}',
          );
        }
      case 'selectTarget':
        _logPlayerAction(
          'phase=target_select_start command_id=$commandId '
          'profile=${action['profileId']} variant=${action['variantId']} '
          'layout=${action['layoutId']}',
        );
        await _selectTarget(action);
        _logPlayerAction(
          'phase=target_select_done command_id=$commandId '
          'elapsed_ms=${watch.elapsedMilliseconds}',
        );
      case 'cyclePlaybackMode':
        _playbackModeIndex = (_playbackModeIndex + 1) % 4;
      case 'selectPlaylist':
        final id = action['playlistId'] as String?;
        if (id != null && state.playlists.any((item) => item.id == id)) {
          _queuePlaylistId = id;
        }
      case 'selectTrack':
        final fileName = action['fileName'] as String?;
        if (fileName != null) {
          await _selectFileAndMaybeResume(
            fileName,
            deadlineUnixMs: deadlineUnixMs,
          );
        }
      case 'toggleFavorite':
        final fileName = action['fileName'] as String? ?? _currentFileName;
        if (fileName != null) {
          await ref
              .read(musicLibraryProvider.notifier)
              .toggleFavorite(fileName);
        }
    }
    _publish();
    unawaited(_persist());
    _logPlayerAction(
      'phase=controller_reply type=$actionType command_id=$commandId '
      'elapsed_ms=${watch.elapsedMilliseconds}',
    );
    return state.toOverlayActionMap();
  }

  Future<void> _selectTarget(Map<String, Object?> action) async {
    final profileId = action['profileId'] as String?;
    final variantId = action['variantId'] as String?;
    final layoutId = action['layoutId'] as String?;
    if (profileId == null || variantId == null || layoutId == null) {
      throw StateError('键位配置选择不完整。');
    }
    final profile = ref.read(profileRepositoryProvider).load(profileId);
    final variant = profile.variantById(variantId);
    if (variant == null) {
      throw StateError('所选乐器不属于当前游戏。');
    }
    if (profile.layoutById(layoutId) == null) {
      throw StateError('所选键位不属于当前游戏。');
    }
    final layout = ref.read(layoutRepositoryProvider).load(layoutId);

    _syncClock();
    _commandGeneration += 1;
    _isPlaying = false;
    _activePlaybackId = null;
    _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
    _playbackError = null;
    _invalidatePreparedPlan();
    _contextKey = <String?>[
      ref.read(selectedFileProvider)?.path,
      profile.id,
      variant.id,
      layout.id,
    ].join('|');
    ref.read(selectedProfileProvider.notifier).select(profile);
    ref.read(selectedVariantProvider.notifier).select(variant);
    ref.read(selectedLayoutProvider.notifier).select(layout);
    unawaited(() async {
      final timestamp = await ref
          .read(targetSelectionPersistenceProvider)
          .markProfileUsedNow(profile.id);
      ref
          .read(persistedProfileUsageProvider.notifier)
          .markUsed(profile.id, timestamp);
    }());
  }

  Future<void> _startCurrentExecution({int? deadlineUnixMs}) async {
    if (_deadlineExpired(deadlineUnixMs)) {
      _setPlaybackFailure('操作已超时，未执行自动点击。');
      return;
    }
    final file =
        _libraryFile(_currentFileName ?? '') ?? ref.read(selectedFileProvider);
    final profile = ref.read(selectedProfileProvider);
    final variant = ref.read(selectedVariantProvider);
    final layout = ref.read(selectedLayoutProvider);
    if (file == null) {
      _setPlaybackFailure('曲库中没有可演奏的曲目。');
      return;
    }
    if (profile == null || variant == null || layout == null) {
      _setPlaybackFailure('请先选择游戏、乐器和键位布局。');
      return;
    }

    final token = ++_commandGeneration;
    _isPlaying = false;
    _playbackStatus = 'preparing';
    _playbackError = null;
    _publish();

    final inputKey = <String>[
      file.path,
      profile.id,
      variant.id,
      layout.id,
      _transpose.toString(),
      _durationMode.name,
    ].join('|');
    _planService ??= ref.read(gamePlaybackPlanServiceProvider);
    late PreparedGamePlayback prepared;
    var remainingConfigRetries = 1;
    while (true) {
      final currentConfigCacheKey = _currentConfigCacheKey(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
      );
      try {
        prepared =
            _preparedPlayback != null &&
                _preparedInputKey == inputKey &&
                currentConfigCacheKey != null &&
                _preparedPlayback!.cacheKey == currentConfigCacheKey
            ? _preparedPlayback!
            : await _planService!.prepare(
                file: file,
                profile: profile,
                variant: variant,
                layout: layout,
                additionalPitchOffset: _transpose,
                durationMode: _durationMode,
              );
      } catch (error) {
        if (token != _commandGeneration || _disposed) return;
        _setPlaybackFailure(_readableError(error));
        return;
      }
      if (token != _commandGeneration || _disposed) return;
      if (_deadlineExpired(deadlineUnixMs)) {
        _setPlaybackFailure('演奏计划准备超时，已取消自动点击。');
        return;
      }

      final liveConfigCacheKey = _currentConfigCacheKey(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
      );
      if (liveConfigCacheKey == null ||
          prepared.cacheKey == liveConfigCacheKey) {
        break;
      }
      _invalidatePreparedPlan();
      if (remainingConfigRetries == 0) {
        _setPlaybackFailure('曲目配置在准备期间持续变化，请重试播放。');
        return;
      }
      remainingConfigRetries -= 1;
    }

    _preparedPlayback = prepared;
    _preparedInputKey = inputKey;
    _planDurationMs = prepared.executablePlan.totalDurationMs;
    _positionMs = _positionMs.clamp(0, max(0, _effectiveDurationMs));
    final playbackId = '${DateTime.now().microsecondsSinceEpoch}:$token';
    _activePlaybackId = playbackId;

    try {
      final result = await _playbackPlatform!.start(
        playback: prepared,
        playbackId: playbackId,
        positionMs: _positionMs,
        speed: _speed,
        timingOffsetMs: _timingOffsetMs,
        tapDurationMs: (prepared.tapDurationMs * _touchDurationPercent / 100)
            .round(),
      );
      if (token != _commandGeneration || _disposed) return;
      if (_deadlineExpired(deadlineUnixMs)) {
        await _safePlatformStop();
        _setPlaybackFailure('启动演奏超时，已停止自动点击。');
        return;
      }
      if (!result.success) {
        _setPlaybackFailure(
          result.message ?? '无障碍执行器启动失败。',
          errorCode: result.errorCode,
        );
        return;
      }
      _positionMs = result.positionMs ?? _positionMs;
      _isPlaying = true;
      _playbackStatus = 'playing';
      _playbackError = null;
      _markClock();
      _publish();
    } catch (error) {
      if (token != _commandGeneration || _disposed) return;
      _setPlaybackFailure(_readableError(error));
    }
  }

  Future<void> _pauseExecution() async {
    final token = ++_commandGeneration;
    if (_playbackStatus == 'preparing' && !_isPlaying) {
      _isPlaying = false;
      _playbackStatus = _positionMs == 0 ? 'idle' : 'paused';
      _playbackError = null;
      _publish();
      return;
    }
    try {
      final result = await _playbackPlatform!.pause();
      if (token != _commandGeneration || _disposed) return;
      if (!result.success) {
        _setPlaybackFailure(result.message ?? '暂停演奏失败。');
        return;
      }
      _positionMs = (result.positionMs ?? _positionMs).clamp(
        0,
        max(0, _effectiveDurationMs),
      );
      _isPlaying = false;
      _playbackStatus = 'paused';
      _playbackError = null;
      _markClock();
      _publish();
    } catch (error) {
      if (token != _commandGeneration || _disposed) return;
      _setPlaybackFailure(_readableError(error));
    }
  }

  Future<void> _pauseForRebase() async {
    _syncClock();
    final token = ++_commandGeneration;
    try {
      final result = await _playbackPlatform!.pause();
      if (token != _commandGeneration || _disposed) return;
      if (result.positionMs != null) _positionMs = result.positionMs!;
    } catch (_) {
      // A following start replaces the native generation. Keep the last local
      // position so the requested seek/speed operation can still be applied.
    }
    _isPlaying = false;
    _playbackStatus = 'paused';
    _markClock();
  }

  Future<void> _stopExecution({required bool resetPosition}) async {
    final token = ++_commandGeneration;
    _isPlaying = false;
    _playbackStatus = 'stopping';
    _publish();
    try {
      final result = await _playbackPlatform!.stop();
      if (token != _commandGeneration || _disposed) return;
      if (!result.success) {
        _setPlaybackFailure(result.message ?? '停止演奏失败。');
        return;
      }
      if (resetPosition) _positionMs = 0;
      _activePlaybackId = null;
      _playbackStatus = 'idle';
      _playbackError = null;
      _markClock();
      _publish();
    } catch (error) {
      if (token != _commandGeneration || _disposed) return;
      _setPlaybackFailure(_readableError(error));
    }
  }

  Future<void> _selectRelativeAndMaybeResume(
    int delta, {
    int? deadlineUnixMs,
  }) async {
    final resume = _isPlaying;
    await _stopForTrackChange();
    _selectRelative(delta);
    if (resume) {
      await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
    }
  }

  Future<void> _selectFileAndMaybeResume(
    String fileName, {
    int? deadlineUnixMs,
  }) async {
    if (_libraryFile(fileName) == null) return;
    final resume = _isPlaying;
    await _stopForTrackChange();
    _selectFile(fileName);
    if (resume) {
      await _startCurrentExecution(deadlineUnixMs: deadlineUnixMs);
    }
  }

  Future<void> _stopForTrackChange() async {
    _commandGeneration += 1;
    _isPlaying = false;
    try {
      await _playbackPlatform!.stop();
    } catch (_) {
      // Selecting a new plan will replace the native generation. Errors are
      // surfaced if that subsequent start fails.
    }
    _activePlaybackId = null;
    _playbackStatus = 'idle';
    _playbackError = null;
  }

  void _selectRelative(int delta) {
    final queue = state.queueFileNames;
    if (queue.isEmpty) return;
    final current = queue.indexOf(_currentFileName ?? '');
    final index = current < 0
        ? (delta < 0 ? queue.length - 1 : 0)
        : (current + delta) % queue.length;
    _selectFile(queue[index]);
  }

  void _selectFile(String fileName) {
    final file = _libraryFile(fileName);
    if (file == null) return;
    _currentFileName = fileName;
    _lastSelectedFileName = fileName;
    _positionMs = 0;
    _markClock();
    _invalidatePreparedPlan(clearDuration: true);
    _remember(fileName);
    _contextKey = <String?>[
      file.path,
      ref.read(selectedProfileProvider)?.id,
      ref.read(selectedVariantProvider)?.id,
      ref.read(selectedLayoutProvider)?.id,
    ].join('|');
    ref.read(selectedFileProvider.notifier).select(file);
  }

  MusicFile? _libraryFile(String fileName) {
    final cached = _catalog?.filesByName[fileName];
    if (cached != null) return cached;
    final files = ref.read(musicLibraryProvider).value?.files;
    if (files == null) return null;
    for (final file in files) {
      if (file.fileName == fileName) return file;
    }
    return null;
  }

  void _remember(String fileName) {
    _historyFileNames.remove(fileName);
    _historyFileNames.insert(0, fileName);
    if (_historyFileNames.length > 50) _historyFileNames.removeLast();
  }

  void _advanceClock() {
    if (!_isPlaying) {
      _markClock();
      return;
    }
    _syncClock();
    _publish();
  }

  void _syncClock() {
    final nowMs = _clock.elapsedMilliseconds;
    final elapsed = nowMs - _lastTickMs;
    _lastTickMs = nowMs;
    if (!_isPlaying || elapsed <= 0) return;
    final durationMs = _effectiveDurationMs;
    if (durationMs <= 0) return;
    _positionMs = min(durationMs, _positionMs + (elapsed * _speed).round());
  }

  void _markClock() {
    _lastTickMs = _clock.elapsedMilliseconds;
  }

  int get _effectiveDurationMs {
    final preparedDuration = _planDurationMs;
    if (preparedDuration != null) return preparedDuration;
    return _libraryFile(_currentFileName ?? '')?.durationMs ?? 0;
  }

  String? _currentConfigCacheKey({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
  }) {
    final config = ref.read(songConfigProvider).value;
    if (config == null ||
        config.fileName != file.fileName ||
        config.profileId != profile.id ||
        config.variantId != variant.id ||
        config.layoutId != layout.id) {
      return null;
    }
    return gamePlaybackCacheKey(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
      config: config,
      additionalPitchOffset: _transpose,
      durationMode: _durationMode,
    );
  }

  bool get _hasActiveOrPendingExecution =>
      _isPlaying || _playbackStatus == 'preparing';

  Future<void> _handlePlaybackEvent(Map<String, Object?> event) async {
    if (_disposed || event['playbackId'] != _activePlaybackId) return;
    switch (event['type']) {
      case 'completed':
        _positionMs = _effectiveDurationMs;
        _isPlaying = false;
        _playbackStatus = 'completed';
        _markClock();
        _publish();
        await _continueAfterCompletion();
      case 'error':
        _isPlaying = false;
        _positionMs = ((event['positionMs'] as num?)?.toInt() ?? _positionMs)
            .clamp(0, max(0, _effectiveDurationMs));
        _playbackStatus = 'error';
        _playbackError = event['message'] as String? ?? '无障碍执行器停止了演奏。';
        _markClock();
        _publish();
      case 'paused':
      case 'stopped':
        _isPlaying = false;
        _positionMs = (event['positionMs'] as num?)?.toInt() ?? _positionMs;
        _playbackStatus = event['type'] as String;
        _markClock();
        _publish();
    }
    unawaited(_persist());
  }

  Future<void> _continueAfterCompletion() async {
    switch (_playbackModeIndex) {
      case 0:
        final queue = state.queueFileNames;
        final index = queue.indexOf(_currentFileName ?? '');
        if (index < 0 || index + 1 >= queue.length) return;
        _selectFile(queue[index + 1]);
      case 1:
        final queue = state.queueFileNames;
        if (queue.isEmpty) return;
        final index = queue.indexOf(_currentFileName ?? '');
        _selectFile(queue[index < 0 ? 0 : (index + 1) % queue.length]);
      case 2:
        _positionMs = 0;
      case 3:
        final queue = state.queueFileNames;
        if (queue.isEmpty) return;
        _selectFile(queue[_random.nextInt(queue.length)]);
    }
    await _startCurrentExecution();
  }

  void _invalidatePreparedPlan({bool clearDuration = false}) {
    _preparedPlayback = null;
    _preparedInputKey = null;
    if (clearDuration) _planDurationMs = null;
  }

  void _setPlaybackFailure(String message, {String? errorCode}) {
    _isPlaying = false;
    _playbackStatus = 'error';
    _playbackError = errorCode == null ? message : '$message ($errorCode)';
    _markClock();
    _publish();
  }

  String _readableError(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|PlatformException):\s*'), '')
        .trim();
  }

  bool _deadlineExpired(int? deadlineUnixMs) {
    return deadlineUnixMs != null &&
        DateTime.now().millisecondsSinceEpoch > deadlineUnixMs;
  }

  Future<void> _safePlatformStop() async {
    try {
      await _playbackPlatform?.stop();
    } catch (_) {
      // Context changes are already reflected as paused locally. A later play
      // performs a full native start and replaces any stale generation.
    }
  }

  void _publish() {
    if (_disposed) return;
    _revision += 1;
    final profile = ref.read(selectedProfileProvider);
    final variant = ref.read(selectedVariantProvider);
    final layout = ref.read(selectedLayoutProvider);
    state = _compose(
      ref.read(musicLibraryProvider).value,
      ref.read(selectedFileProvider),
      profileLabel: _targetDisplayLabel(profile, variant, layout),
    );
  }

  String? _targetDisplayLabel(
    GameProfile? profile,
    InstrumentVariant? variant,
    KeyLayout? layout,
  ) {
    if (profile == null) return null;
    final parts = <String>[
      profile.displayName,
      if (variant != null) variant.displayName,
      if (layout != null)
        profile.layoutById(layout.id)?.displayName ??
            (layout.metadata['displayName'] as String?) ??
            layout.id,
    ];
    return parts.join(' / ');
  }

  GamePlayerSnapshot _compose(
    MusicLibraryState? library,
    MusicFile? selectedFile, {
    String? profileLabel,
  }) {
    var catalog = _catalog;
    if (catalog == null || !catalog.matches(library, selectedFile)) {
      catalog = _GamePlayerCatalog(library, selectedFile, catalog);
      _catalog = catalog;
    }
    final knownNames = catalog.knownNames;
    final playlists = catalog.playlists;
    if (!playlists.any((item) => item.id == _queuePlaylistId)) {
      final librarySelection = library?.currentPlaylistId;
      _queuePlaylistId = playlists.any((item) => item.id == librarySelection)
          ? librarySelection!
          : allSongsPlaylistId;
    }
    final queue = playlists
        .firstWhere((item) => item.id == _queuePlaylistId)
        .fileNames;
    if (!knownNames.contains(_currentFileName)) {
      _currentFileName = knownNames.contains(selectedFile?.fileName)
          ? selectedFile!.fileName
          : queue.firstOrNull ?? catalog.files.firstOrNull?.fileName;
      _positionMs = 0;
      _invalidatePreparedPlan(clearDuration: true);
    }
    _historyFileNames = _historyFileNames
        .where(knownNames.contains)
        .toList(growable: true);
    if (_currentFileName case final current?) _remember(current);
    final rawDurationMs =
        catalog.filesByName[_currentFileName]?.durationMs ?? 0;
    final durationMs = _planDurationMs ?? rawDurationMs;
    _positionMs = _positionMs.clamp(0, durationMs > 0 ? durationMs : 0);

    return GamePlayerSnapshot(
      tracks: catalog.tracks,
      playlists: playlists,
      queuePlaylistId: _queuePlaylistId,
      queueFileNames: queue,
      favoriteFileNames: catalog.favoriteFileNames,
      historyFileNames: List<String>.of(_historyFileNames),
      currentFileName: _currentFileName,
      currentTrackIndex: catalog.trackIndexes[_currentFileName] ?? -1,
      positionMs: _positionMs,
      isPlaying: _isPlaying,
      speed: _speed,
      playbackModeIndex: _playbackModeIndex,
      profileLabel: profileLabel,
      playbackDurationMs: _planDurationMs,
      playbackStatus: _playbackStatus,
      playbackError: _playbackError,
      revision: _revision,
      transpose: _transpose,
      timingOffsetMs: _timingOffsetMs,
      touchDurationPercent: _touchDurationPercent,
      durationMode: _durationMode,
    );
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_gamePlayerStorageKey);
    if (raw != null) {
      try {
        final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
        _queuePlaylistId =
            json['queuePlaylistId'] as String? ?? _queuePlaylistId;
        _currentFileName = json['currentFileName'] as String?;
        _historyFileNames = (json['historyFileNames'] as List? ?? const [])
            .whereType<String>()
            .toList();
        _positionMs = (json['positionMs'] as num?)?.toInt() ?? 0;
        _speed = ((json['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 2);
        _playbackModeIndex =
            ((json['playbackModeIndex'] as num?)?.toInt() ?? 1) % 4;
        _transpose = ((json['transpose'] as num?)?.toInt() ?? 0).clamp(-24, 24);
        _timingOffsetMs = ((json['timingOffsetMs'] as num?)?.toInt() ?? 0)
            .clamp(-200, 200);
        _touchDurationPercent =
            ((json['touchDurationPercent'] as num?)?.toInt() ?? 100).clamp(
              40,
              120,
            );
        _durationMode = GamePlayerDurationMode.values.firstWhere(
          (mode) => mode.name == json['durationMode'],
          orElse: () => GamePlayerDurationMode.shortPress,
        );
      } catch (_) {
        // Ignore a stale player snapshot and rebuild it from the library.
      }
    }
    if (_disposed) return;
    _publish();
    _markClock();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _gamePlayerStorageKey,
      jsonEncode(<String, Object?>{
        'queuePlaylistId': _queuePlaylistId,
        'currentFileName': _currentFileName,
        'historyFileNames': _historyFileNames,
        'positionMs': _positionMs,
        'speed': _speed,
        'playbackModeIndex': _playbackModeIndex,
        'transpose': _transpose,
        'timingOffsetMs': _timingOffsetMs,
        'touchDurationPercent': _touchDurationPercent,
        'durationMode': _durationMode.name,
      }),
    );
  }
}

void _logPlayerAction(String message) {
  developer.log(
    '[OVERLAY_ACTION] side=main $message',
    name: 'lxmusic.overlay.action',
  );
}

class _GamePlayerCatalog {
  _GamePlayerCatalog(
    MusicLibraryState? library,
    MusicFile? selectedFile,
    _GamePlayerCatalog? previous,
  ) : _sourceFiles = library?.files,
      _sourcePlaylists = library?.playlists,
      _fallbackFile = library == null ? selectedFile : null {
    final canReuseTracks =
        previous != null &&
        identical(previous._sourceFiles, _sourceFiles) &&
        identical(previous._fallbackFile, _fallbackFile);
    if (canReuseTracks) {
      files = previous.files;
      filesByName = previous.filesByName;
      knownNames = previous.knownNames;
      tracks = previous.tracks;
      trackIndexes = previous.trackIndexes;
      allFileNames = previous.allFileNames;
    } else {
      files = List<MusicFile>.unmodifiable(
        library?.files ?? <MusicFile>[?selectedFile],
      );
      filesByName = Map<String, MusicFile>.unmodifiable(<String, MusicFile>{
        for (final file in files) file.fileName: file,
      });
      knownNames = Set<String>.unmodifiable(filesByName.keys);
      tracks = List<GamePlayerTrack>.unmodifiable(
        files.map(
          (file) => GamePlayerTrack(
            fileName: file.fileName,
            path: file.path,
            formatId: file.formatId,
            durationMs: file.durationMs,
          ),
        ),
      );
      trackIndexes = Map<String, int>.unmodifiable(<String, int>{
        for (var index = 0; index < tracks.length; index++)
          tracks[index].fileName: index,
      });
      allFileNames = List<String>.unmodifiable(
        files.map((file) => file.fileName),
      );
    }

    _sourceVisiblePlaylists = <Object>[
      for (final playlist in library?.playlists ?? const [])
        if (!playlist.isBuiltinFavorite) playlist,
    ];
    if (canReuseTracks &&
        previous != null &&
        _sameObjects(
          previous._sourceVisiblePlaylists,
          _sourceVisiblePlaylists,
        )) {
      playlists = previous.playlists;
    } else {
      playlists = List<GamePlayerPlaylistSnapshot>.unmodifiable(
        <GamePlayerPlaylistSnapshot>[
          GamePlayerPlaylistSnapshot(
            id: allSongsPlaylistId,
            name: '所有曲目',
            fileNames: allFileNames,
          ),
          for (final playlist in library?.playlists ?? const [])
            if (!playlist.isBuiltinFavorite)
              GamePlayerPlaylistSnapshot(
                id: playlist.id,
                name: playlist.name,
                fileNames: List<String>.unmodifiable(
                  playlist.musicFileNames.where(knownNames.contains),
                ),
              ),
        ],
      );
    }

    favoriteFileNames =
        previous != null &&
            identical(previous._sourcePlaylists, _sourcePlaylists)
        ? previous.favoriteFileNames
        : List<String>.unmodifiable(
            library?.playlists
                    .where((playlist) => playlist.isBuiltinFavorite)
                    .expand((playlist) => playlist.musicFileNames)
                    .where(knownNames.contains) ??
                const <String>[],
          );
  }

  final Object? _sourceFiles;
  final Object? _sourcePlaylists;
  final MusicFile? _fallbackFile;
  late final List<Object> _sourceVisiblePlaylists;
  late final List<MusicFile> files;
  late final Map<String, MusicFile> filesByName;
  late final Set<String> knownNames;
  late final List<GamePlayerTrack> tracks;
  late final Map<String, int> trackIndexes;
  late final List<String> allFileNames;
  late final List<GamePlayerPlaylistSnapshot> playlists;
  late final List<String> favoriteFileNames;

  bool matches(MusicLibraryState? library, MusicFile? selectedFile) {
    if (library != null) {
      return identical(_sourceFiles, library.files) &&
          identical(_sourcePlaylists, library.playlists);
    }
    return _sourceFiles == null &&
        _sourcePlaylists == null &&
        identical(_fallbackFile, selectedFile);
  }

  static bool _sameObjects(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!identical(a[index], b[index])) return false;
    }
    return true;
  }
}
