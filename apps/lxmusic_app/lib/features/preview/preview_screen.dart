import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_preview/layout_key_label_formatter.dart';
import 'models/preview_models.dart';
import 'providers/preview_provider.dart';
import 'services/preview_synth.dart';

const _semanticPointPreviewDurationMs = 120;

@visibleForTesting
Set<String> activeSemanticKeyIdsAt(
  SemanticPlan plan,
  int nowMs, {
  int fallbackDurationMs = _semanticPointPreviewDurationMs,
}) {
  final active = <String>{};
  for (final action in plan.actions) {
    if (nowMs < action.atMs) {
      continue;
    }
    for (final keyId in action.keyIds) {
      final keyDurationMs = action.durationMsForKey(keyId);
      final effectiveDurationMs = keyDurationMs != null && keyDurationMs > 0
          ? keyDurationMs
          : fallbackDurationMs;
      if (nowMs < action.atMs + effectiveDurationMs) {
        active.add(keyId);
      }
    }
  }
  return active;
}

@visibleForTesting
int semanticPreviewTotalDurationMs(
  SemanticPlan plan, {
  int fallbackDurationMs = _semanticPointPreviewDurationMs,
}) {
  var totalDurationMs = plan.totalDurationMs;
  for (final action in plan.actions) {
    for (final keyId in action.keyIds) {
      final keyDurationMs = action.durationMsForKey(keyId);
      final effectiveDurationMs = keyDurationMs != null && keyDurationMs > 0
          ? keyDurationMs
          : fallbackDurationMs;
      totalDurationMs = math.max(
        totalDurationMs,
        action.atMs + effectiveDurationMs,
      );
    }
  }
  return totalDurationMs;
}

@visibleForTesting
int previewTotalDurationMs(
  SemanticPlan plan,
  Iterable<PreviewLaneNote> laneNotes,
) {
  var totalDurationMs = semanticPreviewTotalDurationMs(plan);
  for (final note in laneNotes) {
    totalDurationMs = math.max(totalDurationMs, note.startMs + note.durationMs);
  }
  return totalDurationMs;
}

class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key});

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  static const _playTick = Duration(milliseconds: 16);
  static const _manualHighlightDuration = Duration(milliseconds: 140);
  static const _prefsBottomFractionKey = 'preview.bottom_fraction';
  static const _prefsKeyboardInsetKey = 'preview.keyboard_inset';

  final PreviewSynthEngine _synth = SoloudPreviewSynthEngine();
  final List<Timer> _scheduledNoteTimers = <Timer>[];
  final Map<String, DateTime> _manualHighlights = <String, DateTime>{};
  final Set<String> _heldManualKeyIds = <String>{};

  SharedPreferences? _prefs;
  Timer? _ticker;
  DateTime? _playStartedAt;
  String? _sessionKey;
  int _playbackOriginMs = 0;
  int _positionMs = 0;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  double _speed = 1.0;
  double _laneZoomY = 1.0;
  double _keyboardZoom = 1.0;
  double _bottomPanelFraction = 0.28;
  double _keyboardSideInsetFraction = 0.08;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLayoutPrefs());
  }

  @override
  void dispose() {
    _cancelPlayback(resetClock: true);
    unawaited(_exitFullscreen());
    unawaited(_synth.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(previewSessionProvider);
    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: const Text('预览'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      );
                    },
                    child: TextButton.icon(
                      key: const ValueKey('preview-fullscreen-action'),
                      onPressed: () => unawaited(_toggleFullscreen()),
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('全屏'),
                    ),
                  ),
                ),
              ],
            ),
      body: sessionAsync.when(
        data: (session) {
          if (session == null) {
            _cancelPlayback(resetClock: true);
            return const _PreviewEmptyState(
              title: '先选歌曲和目标配置',
              message: '从曲库选歌后设置当前配置，或者直接在工作台里进入预览。',
            );
          }
          _syncSession(session);
          final geometry = ref.watch(previewGeometryProvider(session.layout));
          final laneNotes = ref.watch(previewLaneNotesProvider(session));
          final totalDurationMs = previewTotalDurationMs(
            session.semanticPlan,
            laneNotes,
          );
          final activeKeyIds = _activeKeyIdsFor(
            session: session,
            nowMs: _positionMs,
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final outerPadding = _isFullscreen
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(16);
              final contentWidth = math.max(
                320.0,
                constraints.maxWidth - outerPadding.horizontal,
              );
              final keyboardInsetPx = _isFullscreen
                  ? (contentWidth * _keyboardSideInsetFraction).clamp(
                      0.0,
                      200.0,
                    )
                  : 0.0;
              final fullscreenHeaderHeight = 84.0;
              final compactSpacing = 8.0;
              final keyboardHeight = _isFullscreen
                  ? (constraints.maxHeight *
                            _bottomPanelFraction.clamp(0.18, 0.62))
                        .toDouble()
                  : 164.0;

              return Padding(
                padding: outerPadding,
                child: Column(
                  children: [
                    _PreviewHeader(
                      compact: _isFullscreen,
                      session: session,
                      totalDurationMs: totalDurationMs,
                      positionMs: _positionMs,
                      isPlaying: _isPlaying,
                      isFullscreen: _isFullscreen,
                      speed: _speed,
                      laneZoomY: _laneZoomY,
                      keyboardZoom: _keyboardZoom,
                      audioError: _audioError,
                      onSeek: (value) => _seekTo(
                        session: session,
                        laneNotes: laneNotes,
                        value: value,
                      ),
                      onTogglePlayback: () => _togglePlayback(
                        session: session,
                        laneNotes: laneNotes,
                      ),
                      onStop: () => _stopPlayback(resetToStart: true),
                      onSpeedChanged: (value) => _setSpeed(
                        session: session,
                        laneNotes: laneNotes,
                        value: value,
                      ),
                      onLaneZoomChanged: (value) {
                        setState(() {
                          _laneZoomY = value;
                        });
                      },
                      onKeyboardZoomChanged: (value) {
                        setState(() {
                          _keyboardZoom = value;
                        });
                      },
                      onToggleFullscreen: _toggleFullscreen,
                    ),
                    SizedBox(height: _isFullscreen ? compactSpacing : 16),
                    Expanded(
                      child: _PreviewWaterfall(
                        geometry: geometry,
                        notes: laneNotes,
                        currentPositionMs: _positionMs,
                        zoomY: _laneZoomY,
                        activeKeyIds: activeKeyIds,
                      ),
                    ),
                    if (_isFullscreen)
                      _ResizeDivider(
                        label: '拖动调节底栏高度',
                        onVerticalDragUpdate: (delta) {
                          final availableHeight = math.max(
                            320.0,
                            constraints.maxHeight -
                                fullscreenHeaderHeight -
                                compactSpacing,
                          );
                          setState(() {
                            _bottomPanelFraction =
                                (_bottomPanelFraction - delta / availableHeight)
                                    .clamp(0.18, 0.62);
                          });
                          unawaited(_persistLayoutPrefs());
                        },
                      )
                    else
                      const SizedBox(height: 16),
                    SizedBox(
                      height: keyboardHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: keyboardInsetPx,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: _PreviewKeyboard(
                                geometry: geometry,
                                activeKeyIds: activeKeyIds,
                                keyboardZoom: _keyboardZoom,
                                onPress: _handleKeyboardPress,
                                onRelease: _handleKeyboardRelease,
                              ),
                            ),
                            if (_isFullscreen)
                              Positioned(
                                left: -10,
                                top: 12,
                                bottom: 12,
                                child: _SideInsetHandle(
                                  alignment: Alignment.centerLeft,
                                  onHorizontalDragUpdate: (delta) {
                                    setState(() {
                                      _keyboardSideInsetFraction =
                                          (_keyboardSideInsetFraction +
                                                  delta / contentWidth)
                                              .clamp(0.0, 0.22);
                                    });
                                    unawaited(_persistLayoutPrefs());
                                  },
                                ),
                              ),
                            if (_isFullscreen)
                              Positioned(
                                right: -10,
                                top: 12,
                                bottom: 12,
                                child: _SideInsetHandle(
                                  alignment: Alignment.centerRight,
                                  onHorizontalDragUpdate: (delta) {
                                    setState(() {
                                      _keyboardSideInsetFraction =
                                          (_keyboardSideInsetFraction -
                                                  delta / contentWidth)
                                              .clamp(0.0, 0.22);
                                    });
                                    unawaited(_persistLayoutPrefs());
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            _PreviewEmptyState(title: '预览数据加载失败', message: '$error'),
      ),
    );
  }

  void _syncSession(PreviewSessionData session) {
    if (_sessionKey == session.sessionKey) {
      return;
    }
    _sessionKey = session.sessionKey;
    _cancelPlayback(resetClock: true);
    _positionMs = 0;
    _audioError = null;
  }

  Future<void> _loadLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _bottomPanelFraction =
          prefs.getDouble(_prefsBottomFractionKey)?.clamp(0.18, 0.62) ?? 0.28;
      _keyboardSideInsetFraction =
          prefs.getDouble(_prefsKeyboardInsetKey)?.clamp(0.0, 0.22) ?? 0.08;
    });
  }

  Future<void> _persistLayoutPrefs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= prefs;
    await prefs.setDouble(_prefsBottomFractionKey, _bottomPanelFraction);
    await prefs.setDouble(_prefsKeyboardInsetKey, _keyboardSideInsetFraction);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    setState(() {
      _isFullscreen = next;
    });
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _exitFullscreen();
    }
  }

  Future<void> _exitFullscreen() async {
    if (!_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }
    if (mounted) {
      setState(() {
        _isFullscreen = false;
      });
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _togglePlayback({
    required PreviewSessionData session,
    required List<PreviewLaneNote> laneNotes,
  }) async {
    if (_isPlaying) {
      _pausePlayback();
      return;
    }
    await _startPlayback(session: session, laneNotes: laneNotes);
  }

  Future<void> _startPlayback({
    required PreviewSessionData session,
    required List<PreviewLaneNote> laneNotes,
  }) async {
    try {
      await _synth.initialize();
      _audioError = null;
    } catch (error) {
      setState(() {
        _audioError = '音频初始化失败: $error';
      });
      return;
    }
    _cancelPlayback(resetClock: false);
    setState(() {
      _isPlaying = true;
      _playbackOriginMs = _positionMs;
      _playStartedAt = DateTime.now();
    });
    _scheduleNotes(laneNotes, fromPositionMs: _positionMs);
    final totalDurationMs = previewTotalDurationMs(
      session.semanticPlan,
      laneNotes,
    );
    _ticker = Timer.periodic(_playTick, (_) {
      if (!mounted || _playStartedAt == null) {
        return;
      }
      _pruneManualHighlights();
      final elapsedMs = DateTime.now()
          .difference(_playStartedAt!)
          .inMilliseconds;
      final nextPosition = _playbackOriginMs + (elapsedMs * _speed).round();
      if (nextPosition >= totalDurationMs) {
        setState(() {
          _positionMs = totalDurationMs;
        });
        _stopPlayback(resetToStart: false);
        return;
      }
      setState(() {
        _positionMs = nextPosition;
      });
    });
  }

  void _pausePlayback() {
    if (!_isPlaying) return;
    final now = _currentPlaybackPosition();
    _cancelPlayback(resetClock: false);
    setState(() {
      _positionMs = now;
      _isPlaying = false;
    });
  }

  void _stopPlayback({required bool resetToStart}) {
    _cancelPlayback(resetClock: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _isPlaying = false;
      if (resetToStart) {
        _positionMs = 0;
      }
    });
  }

  void _cancelPlayback({required bool resetClock}) {
    _ticker?.cancel();
    _ticker = null;
    for (final timer in _scheduledNoteTimers) {
      timer.cancel();
    }
    _scheduledNoteTimers.clear();
    unawaited(_synth.stopAll());
    if (resetClock) {
      _playStartedAt = null;
      _playbackOriginMs = _positionMs;
    }
    _isPlaying = false;
  }

  void _seekTo({
    required PreviewSessionData session,
    required List<PreviewLaneNote> laneNotes,
    required double value,
  }) {
    final totalDurationMs = previewTotalDurationMs(
      session.semanticPlan,
      laneNotes,
    );
    final nextPosition = value.round().clamp(0, totalDurationMs);
    if (!_isPlaying) {
      setState(() {
        _positionMs = nextPosition;
      });
      return;
    }
    _cancelPlayback(resetClock: false);
    setState(() {
      _positionMs = nextPosition;
    });
    unawaited(_startPlayback(session: session, laneNotes: laneNotes));
  }

  void _setSpeed({
    required PreviewSessionData session,
    required List<PreviewLaneNote> laneNotes,
    required double value,
  }) {
    if ((_speed - value).abs() < 0.001) return;
    final wasPlaying = _isPlaying;
    final currentPosition = _currentPlaybackPosition();
    _cancelPlayback(resetClock: false);
    setState(() {
      _speed = value;
      _positionMs = currentPosition;
    });
    if (wasPlaying) {
      unawaited(_startPlayback(session: session, laneNotes: laneNotes));
    }
  }

  Future<void> _handleKeyboardPress(PreviewKeyboardKey key) async {
    setState(() {
      _heldManualKeyIds.add(key.key.id);
    });
    final pitch = key.key.pitch;
    if (pitch == null) {
      return;
    }
    try {
      await _synth.startTone(token: key.key.id, pitch: pitch, volume: 0.2);
      if (!mounted) return;
      setState(() {
        _audioError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _audioError = '音频播放失败: $error';
      });
    }
  }

  Future<void> _handleKeyboardRelease(PreviewKeyboardKey key) async {
    setState(() {
      _heldManualKeyIds.remove(key.key.id);
      _manualHighlights[key.key.id] = DateTime.now().add(
        _manualHighlightDuration,
      );
    });
    try {
      await _synth.stopTone(key.key.id);
      if (!mounted) return;
      setState(() {
        _audioError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _audioError = '音频播放失败: $error';
      });
    }
  }

  void _scheduleNotes(
    List<PreviewLaneNote> laneNotes, {
    required int fromPositionMs,
  }) {
    for (final note in laneNotes) {
      if (note.startMs < fromPositionMs) {
        continue;
      }
      final delayMs = ((note.startMs - fromPositionMs) / _speed).round();
      final timer = Timer(
        Duration(milliseconds: math.max(0, delayMs)),
        () async {
          try {
            await _synth.playTone(
              pitch: note.pitch,
              duration: Duration(
                milliseconds: math.max(60, (note.durationMs / _speed).round()),
              ),
              volume: _volumeForVelocity(note.velocity),
            );
          } catch (error) {
            if (!mounted) return;
            setState(() {
              _audioError = '音频播放失败: $error';
            });
          }
        },
      );
      _scheduledNoteTimers.add(timer);
    }
  }

  Set<String> _activeKeyIdsFor({
    required PreviewSessionData session,
    required int nowMs,
  }) {
    final active = activeSemanticKeyIdsAt(session.semanticPlan, nowMs);
    _pruneManualHighlights();
    active.addAll(_manualHighlights.keys);
    active.addAll(_heldManualKeyIds);
    return active;
  }

  void _pruneManualHighlights() {
    final now = DateTime.now();
    _manualHighlights.removeWhere((_, expiresAt) => expiresAt.isBefore(now));
  }

  int _currentPlaybackPosition() {
    if (!_isPlaying || _playStartedAt == null) {
      return _positionMs;
    }
    final elapsedMs = DateTime.now().difference(_playStartedAt!).inMilliseconds;
    return _playbackOriginMs + (elapsedMs * _speed).round();
  }

  double _volumeForVelocity(int velocity) {
    final normalized = velocity.clamp(1, 127) / 127.0;
    return (0.10 + normalized * 0.18).clamp(0.10, 0.28);
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.compact,
    required this.session,
    required this.totalDurationMs,
    required this.positionMs,
    required this.isPlaying,
    required this.isFullscreen,
    required this.speed,
    required this.laneZoomY,
    required this.keyboardZoom,
    required this.audioError,
    required this.onSeek,
    required this.onTogglePlayback,
    required this.onStop,
    required this.onSpeedChanged,
    required this.onLaneZoomChanged,
    required this.onKeyboardZoomChanged,
    required this.onToggleFullscreen,
  });

  final bool compact;
  final PreviewSessionData session;
  final int totalDurationMs;
  final int positionMs;
  final bool isPlaying;
  final bool isFullscreen;
  final double speed;
  final double laneZoomY;
  final double keyboardZoom;
  final String? audioError;
  final ValueChanged<double> onSeek;
  final VoidCallback onTogglePlayback;
  final VoidCallback onStop;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onLaneZoomChanged;
  final ValueChanged<double> onKeyboardZoomChanged;
  final Future<void> Function() onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final totalMs = math.max(1, totalDurationMs);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    if (compact) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isFullscreen ? '退出全屏' : '全屏',
                    onPressed: () => unawaited(onToggleFullscreen()),
                    icon: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: positionMs.clamp(0, totalMs).toDouble(),
                  max: totalMs.toDouble(),
                  onChanged: onSeek,
                ),
              ),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onTogglePlayback,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(isPlaying ? '暂停' : '播放'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '停止',
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment<double>(value: 0.75, label: Text('0.75x')),
                      ButtonSegment<double>(value: 1.0, label: Text('1x')),
                      ButtonSegment<double>(value: 1.5, label: Text('1.5x')),
                    ],
                    selected: <double>{speed},
                    onSelectionChanged: (selection) =>
                        onSpeedChanged(selection.first),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatTime(positionMs)} / ${_formatTime(totalMs)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              if (audioError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    audioError!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.file.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${session.profile.displayName} / ${session.variant.displayName} / ${session.profile.layoutById(session.layout.id)?.displayName ?? session.layout.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
            const SizedBox(height: 4),
            Text(
              '底栏高度与边距可在全屏模式下拖动调节',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
            const SizedBox(height: 12),
            Slider(
              value: positionMs.clamp(0, totalMs).toDouble(),
              max: totalMs.toDouble(),
              onChanged: onSeek,
            ),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onTogglePlayback,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isPlaying ? '暂停' : '播放'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '停止',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                ),
                const Spacer(),
                Text(
                  '${_formatTime(positionMs)} / ${_formatTime(totalMs)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ValuePill(
                  label: '音符',
                  value: '${session.transformedScore.totalNoteCount}',
                ),
                _ValuePill(
                  label: '按键动作',
                  value: '${session.semanticPlan.actions.length}',
                ),
                _ValuePill(label: '速度', value: '${speed.toStringAsFixed(2)}x'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(width: 140, child: Text('播放速度', style: labelStyle)),
                Expanded(
                  child: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment<double>(value: 0.75, label: Text('0.75x')),
                      ButtonSegment<double>(value: 1.0, label: Text('1.0x')),
                      ButtonSegment<double>(value: 1.25, label: Text('1.25x')),
                      ButtonSegment<double>(value: 1.5, label: Text('1.5x')),
                    ],
                    selected: <double>{speed},
                    onSelectionChanged: (selection) =>
                        onSpeedChanged(selection.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SliderRow(
              label: '瀑布纵向缩放',
              value: laneZoomY,
              min: 0.6,
              max: 2.4,
              onChanged: onLaneZoomChanged,
            ),
            _SliderRow(
              label: '琴键缩放',
              value: keyboardZoom,
              min: 0.8,
              max: 1.8,
              onChanged: onKeyboardZoomChanged,
            ),
            if (audioError != null) ...[
              const SizedBox(height: 10),
              Text(
                audioError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final remain = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(width: 44, child: Text(value.toStringAsFixed(1))),
      ],
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResizeDivider extends StatelessWidget {
  const _ResizeDivider({
    required this.label,
    required this.onVerticalDragUpdate,
  });

  final String label;
  final ValueChanged<double> onVerticalDragUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) =>
            onVerticalDragUpdate(details.delta.dy),
        child: SizedBox(
          height: 18,
          child: Row(
            children: [
              Expanded(
                child: Divider(color: scheme.outlineVariant, thickness: 1),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: scheme.outlineVariant, thickness: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideInsetHandle extends StatelessWidget {
  const _SideInsetHandle({
    required this.alignment,
    required this.onHorizontalDragUpdate,
  });

  final Alignment alignment;
  final ValueChanged<double> onHorizontalDragUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            onHorizontalDragUpdate(details.delta.dx),
        child: Container(
          width: 20,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
          ),
          alignment: alignment,
          child: Icon(
            alignment == Alignment.centerLeft
                ? Icons.drag_indicator
                : Icons.drag_indicator,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PreviewWaterfall extends StatelessWidget {
  const _PreviewWaterfall({
    required this.geometry,
    required this.notes,
    required this.currentPositionMs,
    required this.zoomY,
    required this.activeKeyIds,
  });

  final PreviewLayoutGeometry geometry;
  final List<PreviewLaneNote> notes;
  final int currentPositionMs;
  final double zoomY;
  final Set<String> activeKeyIds;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (geometry.laneCount == 0) {
            return const Center(child: Text('当前布局没有可预览的按键'));
          }
          final visibleFutureMs = (6200 / zoomY).round();
          const visiblePastMs = 700;
          final pixelsPerMs =
              constraints.maxHeight / (visibleFutureMs + visiblePastMs);
          final playheadY = constraints.maxHeight - 28;
          final laneWidth = constraints.maxWidth / geometry.laneCount;
          final visibleNotes = notes.where((note) {
            final endMs = note.startMs + note.durationMs;
            return endMs >= currentPositionMs - visiblePastMs &&
                note.startMs <= currentPositionMs + visibleFutureMs;
          });

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LaneGridPainter(
                      laneCount: geometry.laneCount,
                      activeKeyIds: activeKeyIds,
                      orderedKeys: geometry.laneKeys,
                    ),
                  ),
                ),
                for (final note in visibleNotes)
                  _WaterfallNoteWidget(
                    note: note,
                    laneWidth: laneWidth,
                    laneCenterX: geometry.laneCenter(
                      geometry.laneIndexByKeyId[note.keyId] ?? 0,
                    ),
                    width: constraints.maxWidth,
                    playheadY: playheadY,
                    currentPositionMs: currentPositionMs,
                    pixelsPerMs: pixelsPerMs,
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: playheadY,
                  child: Container(
                    height: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WaterfallNoteWidget extends StatelessWidget {
  const _WaterfallNoteWidget({
    required this.note,
    required this.laneWidth,
    required this.laneCenterX,
    required this.width,
    required this.playheadY,
    required this.currentPositionMs,
    required this.pixelsPerMs,
  });

  final PreviewLaneNote note;
  final double laneWidth;
  final double laneCenterX;
  final double width;
  final double playheadY;
  final int currentPositionMs;
  final double pixelsPerMs;

  @override
  Widget build(BuildContext context) {
    final laneIndexCenter = laneCenterX * width;
    final noteWidth = math.max(8.0, laneWidth * 0.62);
    final top =
        playheadY -
        ((note.startMs + note.durationMs - currentPositionMs) * pixelsPerMs);
    final height = math.max(
      note.isPoint ? 10.0 : 12.0,
      note.isPoint ? 10.0 : note.durationMs * pixelsPerMs,
    );
    final y = note.isPoint
        ? playheadY - ((note.startMs - currentPositionMs) * pixelsPerMs) - 6
        : top;

    return Positioned(
      left: laneIndexCenter - noteWidth / 2,
      top: y,
      width: noteWidth,
      height: note.isPoint ? 12 : height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: note.isPoint
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(note.isPoint ? 999 : 8),
          border: Border.all(
            color: note.isPoint
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaneGridPainter extends CustomPainter {
  _LaneGridPainter({
    required this.laneCount,
    required this.activeKeyIds,
    required this.orderedKeys,
  });

  final int laneCount;
  final Set<String> activeKeyIds;
  final List<PreviewKeyboardKey> orderedKeys;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final activePaint = Paint()..color = Colors.white.withValues(alpha: 0.08);

    for (var index = 0; index < laneCount; index++) {
      final left = size.width * index / laneCount;
      canvas.drawLine(Offset(left, 0), Offset(left, size.height), linePaint);
      if (activeKeyIds.contains(orderedKeys[index].key.id)) {
        canvas.drawRect(
          Rect.fromLTWH(left, 0, size.width / laneCount, size.height),
          activePaint,
        );
      }
    }
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, size.height),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LaneGridPainter oldDelegate) {
    return laneCount != oldDelegate.laneCount ||
        activeKeyIds.length != oldDelegate.activeKeyIds.length ||
        !setEquals(activeKeyIds, oldDelegate.activeKeyIds);
  }
}

class _PreviewKeyboard extends StatelessWidget {
  const _PreviewKeyboard({
    required this.geometry,
    required this.activeKeyIds,
    required this.keyboardZoom,
    required this.onPress,
    required this.onRelease,
  });

  final PreviewLayoutGeometry geometry;
  final Set<String> activeKeyIds;
  final double keyboardZoom;
  final ValueChanged<PreviewKeyboardKey> onPress;
  final ValueChanged<PreviewKeyboardKey> onRelease;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (geometry.keyboardKeys.isEmpty) {
            return const Center(child: Text('没有可用琴键'));
          }
          final metrics = _KeyboardLayoutMetrics.fromKeys(
            geometry.keyboardKeys,
          );
          final keySize =
              (metrics.keySizeFor(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ) *
                      keyboardZoom)
                  .clamp(24.0, 64.0)
                  .toDouble();
          final horizontalPadding = keySize * 0.9;
          final verticalPadding = keySize * 0.9;
          final innerWidth = math.max(
            1.0,
            constraints.maxWidth - horizontalPadding * 2,
          );
          final innerHeight = math.max(
            1.0,
            constraints.maxHeight - verticalPadding * 2,
          );

          return Stack(
            children: [
              for (final key in geometry.keyboardKeys)
                Positioned(
                  left:
                      horizontalPadding + key.normX * innerWidth - keySize / 2,
                  top: verticalPadding + key.normY * innerHeight - keySize / 2,
                  width: keySize,
                  height: keySize,
                  child: _KeyboardKeyButton(
                    keyDefinition: key,
                    active: activeKeyIds.contains(key.id),
                    onPress: () => onPress(
                      PreviewKeyboardKey(
                        key: key,
                        laneIndex: geometry.laneIndexByKeyId[key.id] ?? -1,
                      ),
                    ),
                    onRelease: () => onRelease(
                      PreviewKeyboardKey(
                        key: key,
                        laneIndex: geometry.laneIndexByKeyId[key.id] ?? -1,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KeyboardKeyButton extends StatelessWidget {
  const _KeyboardKeyButton({
    required this.keyDefinition,
    required this.active,
    required this.onPress,
    required this.onRelease,
  });

  final KeyDefinition keyDefinition;
  final bool active;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pitch = keyDefinition.pitch;
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPress(),
        onTapUp: (_) => onRelease(),
        onTapCancel: onRelease,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
              width: active ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: active ? 0.12 : 0.04),
                blurRadius: active ? 16 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                keyDefinition.id,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
              if (pitch != null)
                Text(
                  LayoutKeyLabelFormatter.format(
                    pitch: pitch,
                    mode: LayoutLabelMode.numbered,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontSize: 10,
                    color: active
                        ? scheme.onPrimary.withValues(alpha: 0.88)
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewEmptyState extends StatelessWidget {
  const _PreviewEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardLayoutMetrics {
  _KeyboardLayoutMetrics._({required this.columnCount, required this.rowCount});

  final int columnCount;
  final int rowCount;

  factory _KeyboardLayoutMetrics.fromKeys(List<KeyDefinition> keys) {
    return _KeyboardLayoutMetrics._(
      columnCount: _clusterCount(keys.map((key) => key.normX)),
      rowCount: _clusterCount(keys.map((key) => key.normY)),
    );
  }

  double keySizeFor({required double width, required double height}) {
    final columns = math.max(1, columnCount);
    final rows = math.max(1, rowCount);
    final widthSize = width / (columns + 1.8);
    final heightSize = height / (rows + 1.8);
    return math.min(widthSize, heightSize);
  }

  static int _clusterCount(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return 1;
    }
    var count = 1;
    var anchor = sorted.first;
    for (final value in sorted.skip(1)) {
      if ((value - anchor).abs() > 0.035) {
        count += 1;
        anchor = value;
      }
    }
    return count;
  }
}
