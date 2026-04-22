import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

abstract class PreviewSynthEngine {
  Future<void> initialize();

  Future<void> playTone({
    required int pitch,
    required Duration duration,
    double volume = 0.18,
  });

  Future<void> startTone({
    required Object token,
    required int pitch,
    double volume = 0.18,
  });

  Future<void> stopTone(Object token);

  Future<void> stopAll();

  Future<void> dispose();
}

class SoloudPreviewSynthEngine implements PreviewSynthEngine {
  static const int _sampleRate = 44100;
  static const int _bufferSize = 1024;
  static const int _maxActiveVoices = 48;
  static const Duration _releaseDuration = Duration(milliseconds: 72);
  static const Duration _cleanupSlack = Duration(milliseconds: 40);
  static const WaveForm _waveform = WaveForm.triangle;

  final SoLoud _soloud = SoLoud.instance;
  final Map<int, AudioSource> _sourcesByPitch = <int, AudioSource>{};
  final Map<int, Future<AudioSource>> _sourceFuturesByPitch =
      <int, Future<AudioSource>>{};
  final Map<Object, SoundHandle> _heldHandles = <Object, SoundHandle>{};
  final Set<SoundHandle> _activeHandles = <SoundHandle>{};
  final Map<SoundHandle, Timer> _cleanupTimers = <SoundHandle, Timer>{};

  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initializeFuture ??= _doInitialize();
    await _initializeFuture;
  }

  Future<void> _doInitialize() async {
    await _soloud.init(
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
      channels: Channels.stereo,
    );
    _soloud.setMaxActiveVoiceCount(_maxActiveVoices);
    _initialized = true;
  }

  @override
  Future<void> playTone({
    required int pitch,
    required Duration duration,
    double volume = 0.18,
  }) async {
    await initialize();
    if (_disposed) return;

    final source = await _sourceForPitch(pitch);
    if (_disposed) return;

    final handle = _soloud.play(
      source,
      volume: _clampVolume(volume, pitch: pitch),
    );
    _trackHandle(handle);
    _soloud.scheduleStop(handle, _effectiveDuration(duration));
    _scheduleCleanup(handle, _effectiveDuration(duration) + _cleanupSlack);
  }

  @override
  Future<void> startTone({
    required Object token,
    required int pitch,
    double volume = 0.18,
  }) async {
    await initialize();
    if (_disposed) return;

    await stopTone(token);
    if (_disposed) return;

    final source = await _sourceForPitch(pitch);
    if (_disposed) return;

    final handle = _soloud.play(
      source,
      volume: _clampVolume(volume, pitch: pitch),
    );
    _trackHandle(handle);
    _heldHandles[token] = handle;
  }

  @override
  Future<void> stopTone(Object token) async {
    final handle = _heldHandles.remove(token);
    if (handle == null) {
      return;
    }
    _releaseHandle(handle);
  }

  @override
  Future<void> stopAll() async {
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    _cleanupTimers.clear();

    final handles = _activeHandles.toList(growable: false);
    _heldHandles.clear();
    _activeHandles.clear();

    for (final handle in handles) {
      try {
        await _soloud.stop(handle);
      } catch (_) {
        // The voice may already have ended by the time stopAll() runs.
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stopAll();

    final sources = _sourcesByPitch.values.toList(growable: false);
    _sourcesByPitch.clear();
    _sourceFuturesByPitch.clear();

    if (_soloud.isInitialized) {
      for (final source in sources) {
        try {
          await _soloud.disposeSource(source);
        } catch (_) {
          // Ignore already disposed sources during shutdown.
        }
      }
      _soloud.deinit();
    }

    _initialized = false;
    _initializeFuture = null;
  }

  Future<AudioSource> _sourceForPitch(int pitch) {
    final existing = _sourcesByPitch[pitch];
    if (existing != null) {
      return Future<AudioSource>.value(existing);
    }
    final inFlight = _sourceFuturesByPitch[pitch];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _createSourceForPitch(pitch);
    _sourceFuturesByPitch[pitch] = future;
    return future;
  }

  Future<AudioSource> _createSourceForPitch(int pitch) async {
    try {
      final source = await _soloud.loadWaveform(_waveform, false, 1.0, 0.0);
      _soloud.setWaveformFreq(source, _midiPitchToFrequency(pitch));
      _sourcesByPitch[pitch] = source;
      return source;
    } finally {
      _sourceFuturesByPitch.remove(pitch);
    }
  }

  void _trackHandle(SoundHandle handle) {
    _cleanupTimers.remove(handle)?.cancel();
    _activeHandles.add(handle);
  }

  void _releaseHandle(SoundHandle handle) {
    _cleanupTimers.remove(handle)?.cancel();
    try {
      _soloud.fadeVolume(handle, 0, _releaseDuration);
      _soloud.scheduleStop(handle, _releaseDuration);
    } catch (_) {
      _activeHandles.remove(handle);
      return;
    }
    _scheduleCleanup(handle, _releaseDuration + _cleanupSlack);
  }

  void _scheduleCleanup(SoundHandle handle, Duration after) {
    _cleanupTimers.remove(handle)?.cancel();
    _cleanupTimers[handle] = Timer(after, () {
      _cleanupTimers.remove(handle);
      _activeHandles.remove(handle);
    });
  }

  Duration _effectiveDuration(Duration requested) {
    return requested < const Duration(milliseconds: 40)
        ? const Duration(milliseconds: 40)
        : requested;
  }

  double _clampVolume(double volume, {required int pitch}) {
    final compensation = _pitchCompensation(pitch);
    return (volume * compensation).clamp(0.0, 0.42);
  }

  double _pitchCompensation(int pitch) {
    if (pitch <= 40) return 1.65;
    if (pitch <= 48) return 1.45;
    if (pitch <= 57) return 1.28;
    if (pitch <= 69) return 1.12;
    if (pitch <= 81) return 1.0;
    return 0.94;
  }

  double _midiPitchToFrequency(int pitch) {
    return 440.0 * math.pow(2.0, (pitch - 69) / 12.0).toDouble();
  }
}
