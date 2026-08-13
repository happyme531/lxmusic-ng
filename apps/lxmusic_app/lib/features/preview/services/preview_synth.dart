import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

abstract class PreviewSynthEngine {
  Future<void> initialize();

  Future<void> prepare(Iterable<int> pitches);

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
  static const int _maxActiveVoices = 64;
  static const int _maxMusicalVoices = 32;
  static const double _masterHeadroom = 0.62;
  static const Duration _attackDuration = Duration(milliseconds: 6);
  static const Duration _automaticReleaseDuration = Duration(milliseconds: 28);
  static const Duration _manualReleaseDuration = Duration(milliseconds: 48);
  static const Duration _stopAllReleaseDuration = Duration(milliseconds: 20);
  static const Duration _voiceStealReleaseDuration = Duration(milliseconds: 12);
  static const Duration _rebalanceDuration = Duration(milliseconds: 12);
  static const Duration _cleanupSlack = Duration(milliseconds: 40);
  static const WaveForm _waveform = WaveForm.triangle;

  final SoLoud _soloud = SoLoud.instance;
  final Map<int, AudioSource> _sourcesByPitch = <int, AudioSource>{};
  final Map<int, Future<AudioSource>> _sourceFuturesByPitch =
      <int, Future<AudioSource>>{};
  final Map<Object, SoundHandle> _heldHandles = <Object, SoundHandle>{};
  final Set<SoundHandle> _activeHandles = <SoundHandle>{};
  final Map<SoundHandle, double> _voiceBaseVolumes = <SoundHandle, double>{};
  final Map<SoundHandle, Timer> _releaseTimers = <SoundHandle, Timer>{};
  final Map<SoundHandle, Timer> _cleanupTimers = <SoundHandle, Timer>{};

  Bus? _mixBus;
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
    _mixBus = _createMixBus();
    _initialized = true;
  }

  Bus? _createMixBus() {
    Bus? bus;
    try {
      bus = _soloud.createMixingBus(name: 'preview');
      final limiter = bus.filters.limiterFilter;
      limiter.activate();
      limiter.threshold().value = -6;
      limiter.outputCeiling().value = -1;
      limiter.kneeWidth().value = 3;
      limiter.attackTime().value = 1;
      limiter.releaseTime().value = 80;
      bus.playOnEngine();
      return bus;
    } catch (_) {
      try {
        bus?.dispose();
      } catch (_) {
        // Headroom and voice balancing still protect the direct output path.
      }
      return null;
    }
  }

  @override
  Future<void> prepare(Iterable<int> pitches) async {
    await initialize();
    if (_disposed) return;
    await Future.wait(pitches.toSet().map(_sourceForPitch));
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

    final handle = _startHandle(
      source,
      baseVolume: _clampVolume(volume, pitch: pitch),
    );
    final effectiveDuration = _effectiveDuration(duration);
    final releaseDuration = _releaseDurationFor(effectiveDuration);
    _scheduleRelease(
      handle,
      after: effectiveDuration - releaseDuration,
      releaseDuration: releaseDuration,
    );
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

    final handle = _startHandle(
      source,
      baseVolume: _clampVolume(volume, pitch: pitch),
    );
    _heldHandles[token] = handle;
  }

  @override
  Future<void> stopTone(Object token) async {
    final handle = _heldHandles.remove(token);
    if (handle == null) {
      return;
    }
    _releaseHandle(handle, releaseDuration: _manualReleaseDuration);
  }

  @override
  Future<void> stopAll() async {
    for (final timer in _releaseTimers.values) {
      timer.cancel();
    }
    _releaseTimers.clear();
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    _cleanupTimers.clear();

    final handles = _activeHandles.toList(growable: false);
    _heldHandles.clear();
    _voiceBaseVolumes.clear();
    _activeHandles.clear();

    for (final handle in handles) {
      try {
        _soloud.fadeVolume(handle, 0, _stopAllReleaseDuration);
        _soloud.scheduleStop(handle, _stopAllReleaseDuration);
      } catch (_) {
        // The voice may already have ended by the time stopAll() runs.
      }
    }
    if (handles.isNotEmpty) {
      await Future<void>.delayed(_stopAllReleaseDuration);
      await Future.wait(handles.map(_stopSafely));
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
      try {
        _mixBus?.dispose();
      } catch (_) {
        // Ignore an already disposed bus during shutdown.
      }
      _mixBus = null;
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

  SoundHandle _startHandle(AudioSource source, {required double baseVolume}) {
    _makeRoomForVoice();
    final handle =
        _mixBus?.play(source, volume: 0) ?? _soloud.play(source, volume: 0);
    _trackHandle(handle, baseVolume: baseVolume);
    _rebalanceVoices(newHandle: handle);
    return handle;
  }

  void _trackHandle(SoundHandle handle, {required double baseVolume}) {
    _releaseTimers.remove(handle)?.cancel();
    _cleanupTimers.remove(handle)?.cancel();
    _activeHandles.add(handle);
    _voiceBaseVolumes[handle] = baseVolume;
  }

  void _makeRoomForVoice() {
    if (_voiceBaseVolumes.length < _maxMusicalVoices) {
      return;
    }
    _releaseHandle(
      _voiceBaseVolumes.keys.first,
      releaseDuration: _voiceStealReleaseDuration,
    );
  }

  void _releaseHandle(SoundHandle handle, {required Duration releaseDuration}) {
    _releaseTimers.remove(handle)?.cancel();
    _cleanupTimers.remove(handle)?.cancel();
    _heldHandles.removeWhere((_, heldHandle) => heldHandle == handle);
    final wasBalancedVoice = _voiceBaseVolumes.remove(handle) != null;
    if (wasBalancedVoice) {
      _rebalanceVoices();
    }
    try {
      _soloud.fadeVolume(handle, 0, releaseDuration);
      _soloud.scheduleStop(handle, releaseDuration);
    } catch (_) {
      _activeHandles.remove(handle);
      return;
    }
    _scheduleCleanup(handle, releaseDuration + _cleanupSlack);
  }

  void _scheduleRelease(
    SoundHandle handle, {
    required Duration after,
    required Duration releaseDuration,
  }) {
    _releaseTimers.remove(handle)?.cancel();
    _releaseTimers[handle] = Timer(after, () {
      _releaseTimers.remove(handle);
      _releaseHandle(handle, releaseDuration: releaseDuration);
    });
  }

  void _scheduleCleanup(SoundHandle handle, Duration after) {
    _cleanupTimers.remove(handle)?.cancel();
    _cleanupTimers[handle] = Timer(after, () {
      _cleanupTimers.remove(handle);
      _activeHandles.remove(handle);
      _voiceBaseVolumes.remove(handle);
      _heldHandles.removeWhere((_, heldHandle) => heldHandle == handle);
    });
  }

  void _rebalanceVoices({SoundHandle? newHandle}) {
    final voiceCount = _voiceBaseVolumes.length;
    if (voiceCount == 0) {
      return;
    }
    final gain = _polyphonyGain(voiceCount);
    final staleHandles = <SoundHandle>[];
    for (final entry in _voiceBaseVolumes.entries) {
      try {
        _soloud.fadeVolume(
          entry.key,
          entry.value * gain,
          entry.key == newHandle ? _attackDuration : _rebalanceDuration,
        );
      } catch (_) {
        staleHandles.add(entry.key);
      }
    }
    for (final handle in staleHandles) {
      _voiceBaseVolumes.remove(handle);
      _activeHandles.remove(handle);
      _releaseTimers.remove(handle)?.cancel();
      _cleanupTimers.remove(handle)?.cancel();
      _heldHandles.removeWhere((_, heldHandle) => heldHandle == handle);
    }
  }

  double _polyphonyGain(int voiceCount) {
    if (voiceCount <= 4) {
      return 1;
    }
    return math.sqrt(4 / voiceCount).clamp(0.35, 1.0);
  }

  Duration _releaseDurationFor(Duration totalDuration) {
    final adaptiveMilliseconds = math.max(
      10,
      totalDuration.inMilliseconds ~/ 3,
    );
    return Duration(
      milliseconds: math.min(
        _automaticReleaseDuration.inMilliseconds,
        adaptiveMilliseconds,
      ),
    );
  }

  Future<void> _stopSafely(SoundHandle handle) async {
    try {
      await _soloud.stop(handle);
    } catch (_) {
      // The scheduled stop may already have completed.
    }
  }

  Duration _effectiveDuration(Duration requested) {
    return requested < const Duration(milliseconds: 40)
        ? const Duration(milliseconds: 40)
        : requested;
  }

  double _clampVolume(double volume, {required int pitch}) {
    final compensation = _pitchCompensation(pitch);
    return (volume * compensation * _masterHeadroom).clamp(0.0, 0.28);
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
