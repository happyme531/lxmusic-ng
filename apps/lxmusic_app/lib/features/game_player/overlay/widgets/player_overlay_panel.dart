import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../calibration/calibration_launcher.dart';
import '../../../calibration/platform/calibration_platform.dart';
import '../../../calibration/providers/calibration_provider.dart';
import '../../../workbench/providers/workbench_provider.dart';
import '../../../workbench/widgets/current_target_action.dart';
import '../../models/game_player_snapshot.dart';
import '../models/player_overlay_state.dart';
import '../platform/player_overlay_bridge.dart';

const _panelColor = Color(0xF223272C);
const _panelBorder = Color(0x2EFFFFFF);
const _accent = Color(0xFF63D3BC);
const _danger = Color(0xFFFF858C);
const _muted = Color(0xFFAEB5BD);

enum _SongPickerTab { playlists, queue, favorites, history }

enum _PerformanceEditor { octave, duration }

class PlayerOverlayPanel extends StatefulWidget {
  const PlayerOverlayPanel({required this.bridge, super.key});

  final PlayerOverlayBridge bridge;

  @override
  State<PlayerOverlayPanel> createState() => _PlayerOverlayPanelState();
}

class _PlayerOverlayPanelState extends State<PlayerOverlayPanel> {
  static const _speedPresets = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

  PlayerOverlayPanelState _panelState = PlayerOverlayPanelState.compact;
  PlayerOverlayPanelState _panelStateBeforeDock =
      PlayerOverlayPanelState.compact;
  PlayerOverlayDockSide _dockedSide = PlayerOverlayDockSide.right;
  PlayerOverlayQuickTab _quickTab = PlayerOverlayQuickTab.performance;
  _PerformanceEditor? _performanceEditor;
  _SongPickerTab _songPickerTab = _SongPickerTab.queue;
  Timer? _ticker;
  Timer? _speedCommandDebounce;
  DateTime _lastTick = DateTime.now();
  String _title = '暂无曲目';
  String _profileLabel = '未选择键位';
  String _playbackStatus = 'idle';
  String? _playbackError;
  String? _lastPresentedPlaybackError;
  int _positionMs = 0;
  int _durationMs = 1;
  bool _isPlaying = false;
  bool _autoCollapse = false;
  bool _resizeMode = false;
  bool _isScrubbing = false;
  bool _startingCalibration = false;
  double _speed = 1;
  int _playbackModeIndex = 1;
  int _transpose = 0;
  GamePlayerDurationMode _durationMode = GamePlayerDurationMode.shortPress;
  int _transitionEpoch = 0;
  int _sessionGeneration = 0;
  int _sessionRevision = -1;
  int _nextCommandId = 0;
  int _lastAppliedCommandId = 0;
  List<GamePlayerTrack> _tracks = <GamePlayerTrack>[];
  Map<String, GamePlayerTrack> _tracksByFileName = <String, GamePlayerTrack>{};
  List<GamePlayerPlaylistSnapshot> _playlists = <GamePlayerPlaylistSnapshot>[];
  String _queuePlaylistId = 'all';
  List<String> _queueFileNames = <String>[];
  List<GamePlayerTrack> _queueSongs = <GamePlayerTrack>[];
  Set<String> _favoriteFileNames = <String>{};
  List<GamePlayerTrack> _favoriteSongs = <GamePlayerTrack>[];
  List<String> _historyFileNames = <String>[];
  List<GamePlayerTrack> _historySongs = <GamePlayerTrack>[];
  String? _currentFileName;

  static const _playbackModes = <String>['顺序播放', '列表循环', '单曲循环', '随机播放'];

  @override
  void initState() {
    super.initState();
    widget.bridge.setSessionHandler(_applySession);
    unawaited(_loadInitialSession(++_sessionGeneration));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_consumePendingCalibrationResult());
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant PlayerOverlayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bridge == widget.bridge) return;
    _transitionEpoch++;
    final generation = ++_sessionGeneration;
    oldWidget.bridge.dispose();
    widget.bridge.setSessionHandler(_applySession);
    unawaited(_loadInitialSession(generation));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _speedCommandDebounce?.cancel();
    widget.bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: _panelBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 210),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.97,
                          end: 1,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) {
                    return currentChild ?? const SizedBox.shrink();
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_panelState),
                    child: switch (_panelState) {
                      PlayerOverlayPanelState.mini => _buildMini(),
                      PlayerOverlayPanelState.edgeDocked => _buildEdgeDocked(),
                      PlayerOverlayPanelState.compact => _buildCompact(),
                      PlayerOverlayPanelState.quickControls =>
                        _buildQuickControls(),
                      PlayerOverlayPanelState.speedEditor =>
                        _buildSpeedEditor(),
                      PlayerOverlayPanelState.songPicker => _buildSongPicker(),
                      PlayerOverlayPanelState.targetPicker =>
                        _buildTargetPicker(),
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_resizeMode &&
              _panelState == PlayerOverlayPanelState.quickControls)
            Positioned(
              right: 4,
              bottom: 4,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('player-overlay-resize-handle'),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomRight: Radius.circular(15),
                    ),
                  ),
                  child: const Icon(
                    Icons.south_east_rounded,
                    size: 21,
                    color: Color(0xFF143B34),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMini() {
    return Align(
      key: const ValueKey('player-overlay-mini'),
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 98,
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 53,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: 42,
                    child: CircularProgressIndicator(
                      value: _progress,
                      strokeWidth: 2.4,
                      color: _accent,
                      backgroundColor: const Color(0x24FFFFFF),
                    ),
                  ),
                  _OverlayIconButton(
                    key: const ValueKey('player-overlay-mini-play'),
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: _isPlaying ? '暂停' : '播放',
                    onPressed: _togglePlayback,
                    onLongPress: _stopAndReset,
                    foreground: Colors.white,
                    size: 46,
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 30, color: const Color(0x24FFFFFF)),
            Expanded(
              child: _DragHandle(
                enabled: true,
                compact: true,
                onPanUpdate: _moveWindow,
                onTap: () =>
                    unawaited(_setPanelState(PlayerOverlayPanelState.compact)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeDocked() {
    final dockedLeft = _dockedSide == PlayerOverlayDockSide.left;
    return SizedBox.expand(
      key: const ValueKey('player-overlay-edge-docked'),
      child: GestureDetector(
        key: const ValueKey('player-overlay-edge-expand'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_setPanelState(_panelStateBeforeDock)),
        onPanUpdate: _moveWindow,
        child: Semantics(
          button: true,
          label: '播放进度，点按展开',
          child: Align(
            alignment: dockedLeft
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: SizedBox(
              width: 29,
              height: double.infinity,
              child: Center(
                child: _VerticalProgressBar(
                  key: const ValueKey('player-overlay-edge-progress'),
                  value: _progress,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompact() {
    return Align(
      key: const ValueKey('player-overlay-compact'),
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 76,
        child: _CompactHeader(
          title: _title,
          subtitle: _currentSubtitle,
          positionLabel: _formatDuration(_positionMs),
          durationLabel: _formatDuration(_durationMs),
          progress: _progress,
          isPlaying: _isPlaying,
          isFavorite: _isFavorite,
          speed: _speed,
          onMove: _moveWindow,
          onCollapse: () =>
              unawaited(_setPanelState(PlayerOverlayPanelState.mini)),
          onSeek: _seekToProgress,
          onSeekStart: _startScrubbing,
          onSeekEnd: _endScrubbing,
          onTitlePressed: _toggleSongPicker,
          onTitleDoublePressed: _toggleFavorite,
          onPrevious: _previousSong,
          onTogglePlayback: _togglePlayback,
          onStop: _stopAndReset,
          onNext: _nextSong,
          onSpeedPressed: _toggleSpeedEditor,
          onMorePressed: _toggleSettingsPanel,
        ),
      ),
    );
  }

  Widget _buildQuickControls() {
    return Column(
      key: const ValueKey('player-overlay-quick-controls'),
      children: [
        _expandedHeader(settingsExpanded: true),
        const _PanelDivider(),
        SizedBox(
          height: 34,
          child: Row(
            children: [
              for (final tab in PlayerOverlayQuickTab.values)
                Expanded(
                  child: _OverlayTab(
                    label: switch (tab) {
                      PlayerOverlayQuickTab.performance => '演奏',
                      PlayerOverlayQuickTab.display => '显示',
                    },
                    selected: _quickTab == tab,
                    onPressed: () => setState(() {
                      _quickTab = tab;
                      _performanceEditor = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 7),
            child: switch (_quickTab) {
              PlayerOverlayQuickTab.performance => _buildPerformanceSettings(),
              PlayerOverlayQuickTab.display => _buildDisplaySettings(),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceSettings() {
    return switch (_performanceEditor) {
      _PerformanceEditor.octave => _buildOctaveEditor(),
      _PerformanceEditor.duration => _buildDurationEditor(),
      null => _buildPerformanceOverview(),
    };
  }

  Widget _buildPerformanceOverview() {
    return Consumer(
      builder: (context, ref, _) => Column(
        children: [
          SizedBox(
            height: 36,
            child: _KeyConfigRow(
              profileLabel: _profileLabel,
              calibrationLabel: '重校',
              calibrationEnabled: !_startingCalibration,
              onSwitch: () => unawaited(_openTargetPicker()),
              onCalibrate: () => unawaited(_recalibrateCurrentTarget(ref)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: _PerformanceModeSelector(onUnavailable: _showComingSoon),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    data: _QuickActionData(
                      key: 'octave',
                      icon: Icons.swap_vert_rounded,
                      title: '音域调整',
                      value: _octaveLabel,
                      active: _transpose != 0,
                      onPressed: () => setState(
                        () => _performanceEditor = _PerformanceEditor.octave,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _QuickAction(
                    data: _QuickActionData(
                      key: 'duration-mode',
                      icon: Icons.touch_app_rounded,
                      title: '时长模式',
                      value: _durationModeLabel,
                      active:
                          _durationMode != GamePlayerDurationMode.shortPress,
                      onPressed: () => setState(
                        () => _performanceEditor = _PerformanceEditor.duration,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOctaveEditor() {
    return Column(
      key: const ValueKey('player-overlay-octave-editor'),
      children: [
        _SettingSubmenuHeader(
          title: '音域调整',
          onBack: () => setState(() => _performanceEditor = null),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OctaveChoice(
                  key: const ValueKey('player-overlay-octave-minus-24'),
                  label: '低二八度',
                  selected: _transpose == -24,
                  onPressed: () => _setTranspose(-24),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OctaveChoice(
                  key: const ValueKey('player-overlay-octave-minus-12'),
                  label: '低一八度',
                  selected: _transpose == -12,
                  onPressed: () => _setTranspose(-12),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OctaveChoice(
                  key: const ValueKey('player-overlay-octave-zero'),
                  label: '原调',
                  selected: _transpose == 0,
                  onPressed: () => _setTranspose(0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OctaveChoice(
                  key: const ValueKey('player-overlay-octave-plus-12'),
                  label: '高一八度',
                  selected: _transpose == 12,
                  onPressed: () => _setTranspose(12),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OctaveChoice(
                  key: const ValueKey('player-overlay-octave-plus-24'),
                  label: '高二八度',
                  selected: _transpose == 24,
                  onPressed: () => _setTranspose(24),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationEditor() {
    return Column(
      key: const ValueKey('player-overlay-duration-editor'),
      children: [
        _SettingSubmenuHeader(
          title: '时长模式',
          onBack: () => setState(() => _performanceEditor = null),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 31,
          child: _DurationModeSelector(
            selected: _durationMode,
            onSelected: _setDurationMode,
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: Container(
            key: const ValueKey('player-overlay-duration-description'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0x10FFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(_durationModeIcon, size: 18, color: _accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _durationModeDescription,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 9,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData get _durationModeIcon => switch (_durationMode) {
    GamePlayerDurationMode.shortPress => Icons.touch_app_rounded,
    GamePlayerDurationMode.repeatedTap => Icons.ads_click_rounded,
    GamePlayerDurationMode.longPress => Icons.pan_tool_alt_rounded,
  };

  String get _durationModeDescription => switch (_durationMode) {
    GamePlayerDurationMode.shortPress => '每个音符触发一次固定短按，兼容性最好。',
    GamePlayerDurationMode.repeatedTap => '把长音拆成连续点击，模拟持续发声。',
    GamePlayerDurationMode.longPress => '按音符真实时长持续触摸；停止可能需要等待当前手势结束。',
  };

  Widget _buildDisplaySettings() {
    final actions = <_QuickActionData>[
      _QuickActionData(
        key: 'display-mode',
        icon: Icons.lyrics_outlined,
        title: '副标题显示',
        value: '敬请期待',
        onPressed: null,
      ),
      _QuickActionData(
        key: 'auto-collapse',
        icon: Icons.unfold_less_rounded,
        title: '自动收起',
        value: _autoCollapse ? '播放后 2 秒' : '关闭',
        active: _autoCollapse,
        onPressed: () => setState(() => _autoCollapse = !_autoCollapse),
      ),
      _QuickActionData(
        key: 'resize',
        icon: Icons.aspect_ratio_rounded,
        title: '调整大小',
        value: _resizeMode ? '拖动右下角' : '点按进入',
        active: _resizeMode,
        onPressed: () => unawaited(_toggleResizeMode()),
      ),
      _QuickActionData(
        key: 'close',
        icon: Icons.close_rounded,
        title: '关闭悬浮窗',
        value: '返回主应用可重新打开',
        danger: true,
        onPressed: () => unawaited(widget.bridge.close()),
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          Expanded(
            child: Row(
              children: [
                Expanded(child: _QuickAction(data: actions[row * 2])),
                const SizedBox(width: 6),
                Expanded(child: _QuickAction(data: actions[row * 2 + 1])),
              ],
            ),
          ),
          if (row == 0) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildTargetPicker() {
    return Material(
      color: Colors.transparent,
      child: Consumer(
        builder: (context, ref, _) {
          return CurrentTargetPickerSheet(
            key: const ValueKey('player-overlay-target-picker'),
            initialProfile: ref.watch(selectedProfileProvider),
            initialVariant: ref.watch(selectedVariantProvider),
            initialLayout: ref.watch(selectedLayoutProvider),
            allowLayoutPreview: false,
            compact: true,
            onSelected: _selectTarget,
            onDismiss: () => unawaited(
              _setPanelState(PlayerOverlayPanelState.quickControls),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpeedEditor() {
    return Column(
      key: const ValueKey('player-overlay-speed-editor'),
      children: [
        _expandedHeader(settingsExpanded: false),
        const _PanelDivider(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final preset in _speedPresets)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _SpeedPreset(
                            speed: preset,
                            selected: (_speed - preset).abs() < 0.001,
                            onPressed: () => _setSpeed(preset),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 45,
                  child: Row(
                    children: [
                      _OverlayIconButton(
                        key: const ValueKey('player-overlay-speed-minus'),
                        icon: Icons.remove_rounded,
                        tooltip: '减速',
                        onPressed: () => _setSpeed(_speed - 0.05),
                        size: 38,
                      ),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('player-overlay-speed-slider'),
                          min: 0,
                          max: 1,
                          divisions: 30,
                          value: _speedSliderPosition,
                          onChanged: (position) =>
                              _setSpeed(_speedForSliderPosition(position)),
                        ),
                      ),
                      _OverlayIconButton(
                        key: const ValueKey('player-overlay-speed-plus'),
                        icon: Icons.add_rounded,
                        tooltip: '加速',
                        onPressed: () => _setSpeed(_speed + 0.05),
                        size: 38,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 38),
                      Expanded(
                        child: Text(
                          '${_speed.toStringAsFixed(2)}×  ·  '
                          '${(120 * _speed).round()} BPM',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('player-overlay-speed-reset'),
                        onPressed: () => _setSpeed(1),
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSongPicker() {
    return Column(
      key: const ValueKey('player-overlay-song-picker'),
      children: [
        _expandedHeader(settingsExpanded: false),
        const _PanelDivider(),
        SizedBox(
          height: 34,
          child: Row(
            children: [
              for (final tab in _SongPickerTab.values)
                Expanded(
                  child: _PickerTab(
                    key: ValueKey('player-overlay-picker-tab-${tab.name}'),
                    label: switch (tab) {
                      _SongPickerTab.playlists => '播放列表',
                      _SongPickerTab.queue => '当前队列',
                      _SongPickerTab.favorites => '收藏',
                      _SongPickerTab.history => '历史',
                    },
                    selected: _songPickerTab == tab,
                    onPressed: () => setState(() => _songPickerTab = tab),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildSongPickerBody()),
        const _PanelDivider(),
        SizedBox(
          height: 38,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.queue_music_rounded,
                      size: 17,
                      color: _muted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _activePlaylistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 22, color: const Color(0x24FFFFFF)),
              Expanded(
                child: InkWell(
                  key: const ValueKey(
                    'player-overlay-song-picker-playback-mode',
                  ),
                  onTap: _cyclePlaybackMode,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_playbackModeIcon, size: 17, color: _accent),
                      const SizedBox(width: 6),
                      Text(
                        _playbackModes[_playbackModeIndex],
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongPickerBody() {
    if (_songPickerTab == _SongPickerTab.playlists) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemCount: _playlists.length,
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          final selected = playlist.id == _queuePlaylistId;
          return InkWell(
            key: ValueKey('player-overlay-playlist-$index'),
            onTap: () => _selectPlaylist(index),
            child: SizedBox(
              height: 42,
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Icon(
                      selected
                          ? Icons.queue_music_rounded
                          : Icons.library_music_outlined,
                      size: 18,
                      color: selected ? _accent : _muted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? _accent : Colors.white,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '${playlist.fileNames.length} 首',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final songs = _songsForPickerTab;
    if (songs.isEmpty) {
      return Center(
        key: const ValueKey('player-overlay-song-picker-empty'),
        child: Text(
          _songPickerTab == _SongPickerTab.favorites
              ? '还没有收藏的曲目\n双击歌名即可收藏'
              : '还没有播放记录',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 11, height: 1.5),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final selected = song.fileName == _currentFileName;
        return InkWell(
          key: ValueKey('player-overlay-song-${_songPickerTab.name}-$index'),
          onTap: () => _selectSong(song),
          child: SizedBox(
            height: 37,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Icon(
                    selected
                        ? Icons.play_arrow_rounded
                        : Icons.music_note_rounded,
                    size: 18,
                    color: selected ? _accent : _muted,
                  ),
                ),
                Expanded(
                  child: Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _accent : Colors.white,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    _formatDuration(song.durationMs),
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _expandedHeader({required bool settingsExpanded}) {
    return SizedBox(
      height: 76,
      child: _CompactHeader(
        title: _title,
        subtitle: _currentSubtitle,
        positionLabel: _formatDuration(_positionMs),
        durationLabel: _formatDuration(_durationMs),
        progress: _progress,
        isPlaying: _isPlaying,
        isFavorite: _isFavorite,
        speed: _speed,
        onMove: _moveWindow,
        onCollapse: () =>
            unawaited(_setPanelState(PlayerOverlayPanelState.mini)),
        onSeek: _seekToProgress,
        onSeekStart: _startScrubbing,
        onSeekEnd: _endScrubbing,
        onTitlePressed: _toggleSongPicker,
        onTitleDoublePressed: _toggleFavorite,
        onPrevious: _previousSong,
        onTogglePlayback: _togglePlayback,
        onStop: _stopAndReset,
        onNext: _nextSong,
        onSpeedPressed: _toggleSpeedEditor,
        onMorePressed: _toggleSettingsPanel,
        expanded: settingsExpanded,
      ),
    );
  }

  bool get _isFavorite =>
      _currentFileName != null && _favoriteFileNames.contains(_currentFileName);

  String get _activePlaylistName {
    for (final playlist in _playlists) {
      if (playlist.id == _queuePlaylistId) return playlist.name;
    }
    return '所有曲目';
  }

  GamePlayerTrack? _trackByFileName(String? fileName) {
    if (fileName == null) return null;
    return _tracksByFileName[fileName];
  }

  List<GamePlayerTrack> _tracksForNames(Iterable<String> fileNames) =>
      <GamePlayerTrack>[
        for (final fileName in fileNames) ?_trackByFileName(fileName),
      ];

  List<GamePlayerTrack> get _songsForPickerTab => switch (_songPickerTab) {
    _SongPickerTab.playlists => const <GamePlayerTrack>[],
    _SongPickerTab.queue => _queueSongs,
    _SongPickerTab.favorites => _favoriteSongs,
    _SongPickerTab.history => _historySongs,
  };

  void _indexTracks() {
    _tracksByFileName = <String, GamePlayerTrack>{
      for (final track in _tracks) track.fileName: track,
    };
  }

  void _refreshSongLists() {
    _queueSongs = _tracksForNames(_queueFileNames);
    _favoriteSongs = _tracksForNames(_favoriteFileNames);
    _historySongs = _tracksForNames(_historyFileNames);
  }

  String get _currentSubtitle {
    if (_playbackStatus == 'preparing') return '正在准备演奏计划…';
    return _profileLabel;
  }

  Future<void> _consumePendingCalibrationResult() async {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final managerState = await container.read(
        calibrationManagerProvider.future,
      );
      if (!mounted || managerState.lastResult == null) return;
      final result = managerState.lastResult!;
      final message = switch (result.status) {
        CalibrationSessionStatus.saved => '键位校准已保存，可以直接开始演奏。',
        CalibrationSessionStatus.cancelled => '键位校准已取消。',
        CalibrationSessionStatus.error =>
          result.message ?? '键位校准失败：${result.errorCode ?? 'unknown'}',
        CalibrationSessionStatus.started => null,
      };
      if (message != null) {
        _showOverlayMessage(
          message,
          isError: result.status == CalibrationSessionStatus.error,
        );
      }
    } on Object catch (error) {
      if (mounted) _showOverlayMessage('读取键位校准结果失败：$error', isError: true);
    }
  }

  void _presentPlaybackError(String? message) {
    final normalized = message?.trim();
    if (normalized == null || normalized.isEmpty) {
      _lastPresentedPlaybackError = null;
      return;
    }
    if (_lastPresentedPlaybackError == normalized) return;
    _lastPresentedPlaybackError = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lastPresentedPlaybackError == normalized) {
        _showOverlayMessage(normalized, isError: true);
      }
    });
  }

  void _showOverlayMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2400),
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: isError
              ? const Color(0xF2A63C48)
              : const Color(0xF235675E),
          content: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      );
  }

  double get _progress {
    if (_durationMs <= 0) return 0;
    return (_positionMs / _durationMs).clamp(0, 1);
  }

  Future<void> _loadInitialSession(int generation) async {
    try {
      final session = await widget.bridge.loadInitialSession();
      if (!mounted || generation != _sessionGeneration) return;
      await _applySession(session);
    } catch (_) {
      // Keep the preview defaults if the host is unavailable during startup.
    }
  }

  Future<void> _applySession(Map<String, Object?> session) async {
    if (!mounted) return;
    switch (session['command']) {
      case 'collapseToMini':
        await _setPanelState(PlayerOverlayPanelState.mini);
        return;
      case 'expandFromMini':
        await _setPanelState(PlayerOverlayPanelState.compact);
        return;
      case 'dockToEdge':
        await _deactivateTargetPicker();
        final side = session['side'] == 'left'
            ? PlayerOverlayDockSide.left
            : PlayerOverlayDockSide.right;
        setState(() {
          _transitionEpoch++;
          if (_panelState != PlayerOverlayPanelState.edgeDocked) {
            _panelStateBeforeDock = _panelState;
          }
          _dockedSide = side;
          _panelState = PlayerOverlayPanelState.edgeDocked;
        });
        return;
      case 'undockToMini':
        await _deactivateTargetPicker();
        setState(() {
          _transitionEpoch++;
          _panelState = PlayerOverlayPanelState.mini;
        });
        return;
      case 'undockToPrevious':
        setState(() {
          _transitionEpoch++;
          _panelState = _panelStateBeforeDock;
        });
        return;
    }
    if (session['partial'] == true) {
      _applyPartialSession(session);
      return;
    }
    if (session['version'] == 1 || session['tracks'] is List) {
      final snapshot = GamePlayerSnapshot.fromMap(session);
      if (snapshot.revision < _sessionRevision) return;
      _sessionRevision = snapshot.revision;
      setState(() {
        _tracks = List<GamePlayerTrack>.of(snapshot.tracks);
        _indexTracks();
        _playlists = List<GamePlayerPlaylistSnapshot>.of(snapshot.playlists);
        _queuePlaylistId = snapshot.queuePlaylistId;
        _queueFileNames = List<String>.of(snapshot.queueFileNames);
        _favoriteFileNames = snapshot.favoriteFileNames.toSet();
        _historyFileNames = List<String>.of(snapshot.historyFileNames);
        _refreshSongLists();
        _currentFileName = snapshot.currentFileName;
        final track = _trackByFileName(_currentFileName);
        _title = track?.displayName ?? '暂无曲目';
        _durationMs = snapshot.durationMs.clamp(1, 1 << 31);
        _positionMs = snapshot.positionMs.clamp(0, _durationMs);
        _isPlaying = snapshot.isPlaying;
        _playbackStatus = snapshot.playbackStatus;
        _playbackError = snapshot.playbackError;
        _speed = snapshot.speed;
        _playbackModeIndex = snapshot.playbackModeIndex;
        _transpose = snapshot.transpose;
        _durationMode = snapshot.durationMode;
        final profile = snapshot.profileLabel?.trim();
        _profileLabel = profile == null || profile.isEmpty ? '未选择键位' : profile;
        _lastTick = DateTime.now();
      });
      _presentPlaybackError(snapshot.playbackError);
      return;
    }
    setState(() {
      final title = session['title'] as String?;
      if (title != null && title.trim().isNotEmpty) _title = title.trim();
      final duration = (session['durationMs'] as num?)?.toInt();
      if (duration != null && duration > 0) {
        _durationMs = duration;
        _positionMs = (_durationMs * 0.32).round();
      }
      final profile = session['profileLabel'] as String?;
      if (profile != null && profile.trim().isNotEmpty) {
        _profileLabel = profile.trim();
      }
      final legacyFileName = '$_title.mid';
      final legacyTrack = GamePlayerTrack(
        fileName: legacyFileName,
        path: '',
        formatId: 'midi',
        durationMs: _durationMs,
      );
      _tracks = <GamePlayerTrack>[
        legacyTrack,
        ..._tracks.where((track) => track.fileName != legacyFileName),
      ];
      _indexTracks();
      _currentFileName = legacyFileName;
      if (!_queueFileNames.contains(legacyFileName)) {
        _queueFileNames.insert(0, legacyFileName);
      }
      _rememberSong(legacyTrack);
      _refreshSongLists();
    });
  }

  void _applyPartialSession(Map<String, Object?> session) {
    final revision = (session['revision'] as num?)?.toInt();
    if (revision != null && revision < _sessionRevision) return;
    if (revision != null) _sessionRevision = revision;

    setState(() {
      var tracksChanged = false;
      var queueChanged = false;
      var favoritesChanged = false;
      var historyChanged = false;

      if (session['tracks'] case final List<Object?> rawTracks) {
        _tracks = rawTracks
            .whereType<Map>()
            .map(
              (track) =>
                  GamePlayerTrack.fromMap(Map<Object?, Object?>.from(track)),
            )
            .toList(growable: false);
        _indexTracks();
        tracksChanged = true;
      }
      if (session['playlists'] case final List<Object?> rawPlaylists) {
        _playlists = rawPlaylists
            .whereType<Map>()
            .map(
              (playlist) => GamePlayerPlaylistSnapshot.fromMap(
                Map<Object?, Object?>.from(playlist),
              ),
            )
            .toList(growable: false);
      }
      if (session['queuePlaylistId'] case final String playlistId) {
        _queuePlaylistId = playlistId;
      }
      if (session['queueFileNames'] case final List<Object?> fileNames) {
        _queueFileNames = fileNames.whereType<String>().toList(growable: false);
        queueChanged = true;
      }
      if (session['favoriteFileNames'] case final List<Object?> fileNames) {
        _favoriteFileNames = fileNames.whereType<String>().toSet();
        favoritesChanged = true;
      }
      if (session['historyFileNames'] case final List<Object?> fileNames) {
        _historyFileNames = fileNames.whereType<String>().toList(
          growable: true,
        );
        historyChanged = true;
      }
      if (session.containsKey('currentFileName')) {
        _currentFileName = session['currentFileName'] as String?;
      }
      final title = session['title'] as String?;
      if (title != null && title.trim().isNotEmpty) {
        _title = title.trim();
      } else if (session.containsKey('currentFileName')) {
        _title = _trackByFileName(_currentFileName)?.displayName ?? '暂无曲目';
      }
      final duration = (session['durationMs'] as num?)?.toInt();
      if (duration != null && duration > 0) _durationMs = duration;
      final position = (session['positionMs'] as num?)?.toInt();
      if (position != null) {
        _positionMs = position.clamp(0, _durationMs);
      }
      if (session['isPlaying'] case final bool isPlaying) {
        _isPlaying = isPlaying;
      }
      if (session['playbackStatus'] case final String playbackStatus) {
        _playbackStatus = playbackStatus;
      }
      if (session.containsKey('playbackError')) {
        _playbackError = session['playbackError'] as String?;
      }
      if (session['speed'] case final num speed) {
        _speed = speed.toDouble().clamp(0.5, 2);
      }
      if (session['playbackModeIndex'] case final num modeIndex) {
        _playbackModeIndex = modeIndex.toInt() % _playbackModes.length;
      }
      if (session['transpose'] case final num transpose) {
        _transpose = transpose.toInt().clamp(-24, 24);
      }
      if (session['durationMode'] case final String durationMode) {
        _durationMode = GamePlayerDurationMode.values.firstWhere(
          (mode) => mode.name == durationMode,
          orElse: () => _durationMode,
        );
      }
      if (session.containsKey('profileLabel')) {
        final profile = (session['profileLabel'] as String?)?.trim();
        _profileLabel = profile == null || profile.isEmpty ? '未选择键位' : profile;
      }

      if (tracksChanged) {
        _refreshSongLists();
      } else {
        if (queueChanged) _queueSongs = _tracksForNames(_queueFileNames);
        if (favoritesChanged) {
          _favoriteSongs = _tracksForNames(_favoriteFileNames);
        }
        if (historyChanged) {
          _historySongs = _tracksForNames(_historyFileNames);
        }
      }
      _lastTick = DateTime.now();
    });
    if (session.containsKey('playbackError')) {
      _presentPlaybackError(_playbackError);
    }
  }

  void _tick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    if (!mounted || !_isPlaying || _isScrubbing || elapsed <= 0) return;
    setState(() {
      _positionMs += (elapsed * _speed).round();
      if (_positionMs >= _durationMs) {
        _positionMs = _durationMs;
      }
    });
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
      _playbackError = null;
      _lastTick = DateTime.now();
    });
    _presentPlaybackError(null);
    _sendAction('togglePlayback');
  }

  void _stopAndReset() {
    setState(() {
      _isPlaying = false;
      _positionMs = 0;
    });
    _sendAction('stop');
  }

  void _previousSong() {
    _selectRelativeSong(-1);
    _sendAction('previous');
  }

  void _nextSong() {
    _selectRelativeSong(1);
    _sendAction('next');
  }

  void _selectRelativeSong(int delta) {
    final queue = _queueSongs;
    if (queue.isEmpty) return;
    final current = queue.indexWhere(
      (song) => song.fileName == _currentFileName,
    );
    final next = current < 0
        ? (delta < 0 ? queue.length - 1 : 0)
        : (current + delta) % queue.length;
    _selectSong(queue[next], collapsePicker: false, emitAction: false);
  }

  void _selectSong(
    GamePlayerTrack song, {
    bool collapsePicker = true,
    bool emitAction = true,
  }) {
    setState(() {
      _currentFileName = song.fileName;
      _title = song.displayName;
      _durationMs = song.durationMs;
      _positionMs = 0;
      _rememberSong(song);
    });
    if (collapsePicker) {
      unawaited(_setPanelState(PlayerOverlayPanelState.compact));
    }
    if (emitAction) {
      _sendAction('selectTrack', <String, Object?>{'fileName': song.fileName});
    }
  }

  void _selectPlaylist(int index) {
    final playlist = _playlists[index];
    setState(() {
      _queuePlaylistId = playlist.id;
      _queueFileNames = List<String>.of(playlist.fileNames);
      _queueSongs = _tracksForNames(_queueFileNames);
      _songPickerTab = _SongPickerTab.queue;
    });
    _sendAction('selectPlaylist', <String, Object?>{'playlistId': playlist.id});
  }

  void _rememberSong(GamePlayerTrack song) {
    _historyFileNames.remove(song.fileName);
    _historyFileNames.insert(0, song.fileName);
    if (_historyFileNames.length > 20) _historyFileNames.removeLast();
    _historySongs = _tracksForNames(_historyFileNames);
  }

  void _cyclePlaybackMode() {
    setState(() {
      _playbackModeIndex = (_playbackModeIndex + 1) % _playbackModes.length;
    });
    _sendAction('cyclePlaybackMode');
  }

  void _toggleFavorite() {
    final fileName = _currentFileName;
    if (fileName == null) return;
    setState(() {
      if (!_favoriteFileNames.add(fileName)) {
        _favoriteFileNames.remove(fileName);
      }
      _favoriteSongs = _tracksForNames(_favoriteFileNames);
    });
    _sendAction('toggleFavorite', <String, Object?>{'fileName': fileName});
  }

  IconData get _playbackModeIcon => switch (_playbackModeIndex) {
    0 => Icons.playlist_play_rounded,
    1 => Icons.repeat_rounded,
    2 => Icons.repeat_one_rounded,
    _ => Icons.shuffle_rounded,
  };

  Future<void> _toggleResizeMode() async {
    final enabled = !_resizeMode;
    setState(() => _resizeMode = enabled);
    try {
      await widget.bridge.setResizeMode(enabled);
    } on Object {
      if (mounted && _resizeMode == enabled) {
        setState(() => _resizeMode = !enabled);
      }
    }
  }

  void _setSpeed(double value) {
    setState(() => _speed = value.clamp(0.5, 2));
    _speedCommandDebounce?.cancel();
    _speedCommandDebounce = Timer(const Duration(milliseconds: 140), () {
      _sendAction('setSpeed', <String, Object?>{'speed': _speed});
    });
  }

  double get _speedSliderPosition {
    return (math.log(_speed.clamp(0.5, 2) / 0.5) / math.log(4)).clamp(0, 1);
  }

  double _speedForSliderPosition(double position) {
    return (0.5 * math.pow(4, position.clamp(0, 1))).toDouble();
  }

  void _seekToProgress(double progress) {
    setState(() {
      _positionMs = (_durationMs * progress.clamp(0, 1)).round();
      _lastTick = DateTime.now();
    });
  }

  void _sendAction(String type, [Map<String, Object?> payload = const {}]) {
    final commandId = ++_nextCommandId;
    unawaited(_dispatchAction(type, payload, commandId));
  }

  Future<Map<String, Object?>> _dispatchAction(
    String type,
    Map<String, Object?> payload,
    int commandId, {
    bool rethrowError = false,
  }) async {
    try {
      final snapshot = await widget.bridge.sendAction(<String, Object?>{
        'type': type,
        'commandId': commandId,
        ...payload,
      });
      if (!mounted || commandId < _lastAppliedCommandId) return snapshot;
      _lastAppliedCommandId = commandId;
      if (snapshot.isNotEmpty) await _applySession(snapshot);
      return snapshot;
    } catch (error) {
      if (!mounted || commandId < _lastAppliedCommandId) {
        if (rethrowError) rethrow;
        return const <String, Object?>{};
      }
      _lastAppliedCommandId = commandId;
      setState(() {
        _isPlaying = false;
        _playbackStatus = 'error';
        _playbackError = error.toString();
      });
      _presentPlaybackError(_playbackError);
      if (rethrowError) rethrow;
      return const <String, Object?>{};
    }
  }

  void _startScrubbing() {
    _isScrubbing = true;
    _lastTick = DateTime.now();
  }

  void _endScrubbing() {
    _isScrubbing = false;
    _lastTick = DateTime.now();
    _sendAction('seek', <String, Object?>{'positionMs': _positionMs});
  }

  void _toggleSongPicker() {
    if (_panelState == PlayerOverlayPanelState.songPicker) {
      unawaited(_setPanelState(PlayerOverlayPanelState.compact));
      return;
    }
    setState(() => _songPickerTab = _SongPickerTab.queue);
    unawaited(_setPanelState(PlayerOverlayPanelState.songPicker));
  }

  void _toggleSpeedEditor() {
    final next = _panelState == PlayerOverlayPanelState.speedEditor
        ? PlayerOverlayPanelState.compact
        : PlayerOverlayPanelState.speedEditor;
    unawaited(_setPanelState(next));
  }

  void _toggleSettingsPanel() {
    final next = _panelState == PlayerOverlayPanelState.quickControls
        ? PlayerOverlayPanelState.compact
        : PlayerOverlayPanelState.quickControls;
    if (next == PlayerOverlayPanelState.quickControls) {
      setState(() => _performanceEditor = null);
    }
    unawaited(_setPanelState(next));
  }

  void _setTranspose(int semitones) {
    final next = semitones.clamp(-24, 24);
    setState(() => _transpose = next);
    _sendAction('setTranspose', <String, Object?>{'transpose': next});
  }

  String get _octaveLabel => switch (_transpose) {
    -24 => '低二八度',
    -12 => '低一八度',
    12 => '高一八度',
    24 => '高二八度',
    _ => '原调',
  };

  void _setDurationMode(GamePlayerDurationMode next) {
    if (next == _durationMode) return;
    setState(() => _durationMode = next);
    _sendAction('setDurationMode', <String, Object?>{
      'durationMode': next.name,
    });
  }

  String get _durationModeLabel => switch (_durationMode) {
    GamePlayerDurationMode.shortPress => '短按',
    GamePlayerDurationMode.repeatedTap => '连点',
    GamePlayerDurationMode.longPress => '长按',
  };

  Future<void> _recalibrateCurrentTarget(WidgetRef ref) async {
    if (_startingCalibration) return;
    final profile = ref.read(selectedProfileProvider);
    final layout = ref.read(selectedLayoutProvider);
    if (profile == null || layout == null) return;
    setState(() => _startingCalibration = true);
    final result = await launchCalibration(
      context: context,
      ref: ref,
      profile: profile,
      layout: layout,
      launchOrigin: CalibrationLaunchOrigin.playerOverlay,
    );
    if (!mounted) return;
    if (result?.status == CalibrationSessionStatus.started) {
      await _setPanelState(PlayerOverlayPanelState.compact);
    }
    if (mounted) setState(() => _startingCalibration = false);
  }

  void _showComingSoon(String mode) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text('$mode模式敬请期待'),
        ),
      );
  }

  Future<void> _openTargetPicker() async {
    final commandId = ++_nextCommandId;
    try {
      await _dispatchAction(
        'prepareTargetSelection',
        const <String, Object?>{},
        commandId,
        rethrowError: true,
      );
      if (!mounted) return;
      await _setPanelState(PlayerOverlayPanelState.targetPicker);
    } catch (_) {
      // _dispatchAction exposes the failure in the panel playback status.
    }
  }

  Future<void> _selectTarget(
    GameProfile profile,
    InstrumentVariant variant,
    KeyLayout layout,
  ) async {
    final commandId = ++_nextCommandId;
    await _dispatchAction(
      'selectTarget',
      <String, Object?>{
        'profileId': profile.id,
        'variantId': variant.id,
        'layoutId': layout.id,
      },
      commandId,
      rethrowError: true,
    );
  }

  Future<void> _deactivateTargetPicker() async {
    if (_panelState != PlayerOverlayPanelState.targetPicker) return;
    try {
      await widget.bridge.setTargetPickerActive(false);
    } catch (_) {
      // The native window may already be closing.
    }
  }

  Future<void> _setPanelState(PlayerOverlayPanelState state) async {
    if (_panelState == state) return;
    if (_resizeMode && state != PlayerOverlayPanelState.quickControls) {
      setState(() => _resizeMode = false);
      try {
        await widget.bridge.setResizeMode(false);
      } catch (_) {
        // The native window may already be closing.
      }
    }
    final leavingTargetPicker =
        _panelState == PlayerOverlayPanelState.targetPicker &&
        state != PlayerOverlayPanelState.targetPicker;
    if (leavingTargetPicker) await _deactivateTargetPicker();
    final transition = ++_transitionEpoch;
    final currentSize = PlayerOverlayWindowSize.forState(_panelState);
    final targetSize = PlayerOverlayWindowSize.forState(state);
    final expands =
        targetSize.width * targetSize.height >
        currentSize.width * currentSize.height;

    if (!expands) setState(() => _panelState = state);
    var resizeSucceeded = false;
    try {
      await widget.bridge.resize(targetSize);
      resizeSucceeded = true;
    } catch (_) {
      // Keep the Flutter controls usable if the native host is disappearing.
    }
    if (!mounted ||
        transition != _transitionEpoch ||
        !expands ||
        !resizeSucceeded) {
      return;
    }
    setState(() => _panelState = state);
    if (state == PlayerOverlayPanelState.targetPicker) {
      try {
        await widget.bridge.setTargetPickerActive(true);
      } catch (_) {
        // Search still remains usable with a hardware keyboard if focus setup
        // is unavailable in a preview host.
      }
    }
  }

  void _moveWindow(DragUpdateDetails details) {
    unawaited(widget.bridge.moveBy(details.delta.dx, details.delta.dy));
  }

  static String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.title,
    required this.subtitle,
    required this.positionLabel,
    required this.durationLabel,
    required this.progress,
    required this.isPlaying,
    required this.isFavorite,
    required this.speed,
    required this.onMove,
    required this.onCollapse,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onTitlePressed,
    required this.onTitleDoublePressed,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onStop,
    required this.onNext,
    required this.onSpeedPressed,
    required this.onMorePressed,
    this.expanded = false,
  });

  final String title;
  final String subtitle;
  final String positionLabel;
  final String durationLabel;
  final double progress;
  final bool isPlaying;
  final bool isFavorite;
  final double speed;
  final ValueChanged<DragUpdateDetails> onMove;
  final VoidCallback onCollapse;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final VoidCallback onTitlePressed;
  final VoidCallback onTitleDoublePressed;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onStop;
  final VoidCallback onNext;
  final VoidCallback onSpeedPressed;
  final VoidCallback onMorePressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 45,
          child: Row(
            children: [
              _DragHandle(
                enabled: true,
                onPanUpdate: onMove,
                onTap: onCollapse,
              ),
              Expanded(
                child: InkWell(
                  key: const ValueKey('player-overlay-title'),
                  onTap: onTitlePressed,
                  onDoubleTap: onTitleDoublePressed,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 3),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  size: 10,
                                  color: _accent,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _OverlayIconButton(
                key: const ValueKey('player-overlay-previous'),
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                onPressed: onPrevious,
              ),
              _OverlayIconButton(
                key: const ValueKey('player-overlay-play'),
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: isPlaying ? '暂停' : '播放',
                onPressed: onTogglePlayback,
                onLongPress: onStop,
                foreground: const Color(0xFF163D36),
                background: _accent,
              ),
              _OverlayIconButton(
                key: const ValueKey('player-overlay-next'),
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                onPressed: onNext,
              ),
              SizedBox(
                width: 60,
                height: 38,
                child: InkWell(
                  key: const ValueKey('player-overlay-speed'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onSpeedPressed,
                  child: Center(
                    child: Text(
                      '${speed.toStringAsFixed(2)}×',
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              _OverlayIconButton(
                key: const ValueKey('player-overlay-more'),
                icon: expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.more_horiz_rounded,
                tooltip: expanded ? '收起' : '更多',
                onPressed: onMorePressed,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 0, 8, 3),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    positionLabel,
                    style: const TextStyle(color: _muted, fontSize: 8.5),
                  ),
                ),
                Expanded(
                  child: _OverlayProgressBar(
                    key: const ValueKey('player-overlay-progress'),
                    value: progress,
                    onChanged: onSeek,
                    onChangeStart: onSeekStart,
                    onChangeEnd: onSeekEnd,
                  ),
                ),
                SizedBox(
                  width: 33,
                  child: Text(
                    durationLabel,
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: _muted, fontSize: 8.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalProgressBar extends StatelessWidget {
  const _VerticalProgressBar({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0, 1).toDouble();
    return Container(
      width: 5,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0x30FFFFFF),
        borderRadius: BorderRadius.circular(3),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: progress,
        widthFactor: 1,
        alignment: Alignment.bottomCenter,
        child: const ColoredBox(color: _accent),
      ),
    );
  }
}

class _OverlayProgressBar extends StatelessWidget {
  const _OverlayProgressBar({
    required this.value,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeStart;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0, 1).toDouble();
    return Semantics(
      label: '播放进度',
      value: '${(progress * 100).round()}%',
      slider: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(double localX) {
            if (constraints.maxWidth <= 0) return;
            onChanged((localX / constraints.maxWidth).clamp(0, 1));
          }

          final thumbLeft = (progress * constraints.maxWidth - 5).clamp(
            0.0,
            (constraints.maxWidth - 10).clamp(0.0, double.infinity),
          );
          return SizedBox.expand(
            child: Listener(
              onPointerDown: (_) => onChangeStart(),
              onPointerUp: (_) => onChangeEnd(),
              onPointerCancel: (_) => onChangeEnd(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition.dx),
                onHorizontalDragStart: (details) =>
                    update(details.localPosition.dx),
                onHorizontalDragUpdate: (details) =>
                    update(details.localPosition.dx),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x28FFFFFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: (constraints.maxHeight - 10) / 2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.enabled,
    required this.onPanUpdate,
    this.onTap,
    this.compact = false,
  });

  final bool enabled;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('player-overlay-drag-handle'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanUpdate: enabled ? onPanUpdate : null,
      child: SizedBox(
        width: compact ? 44 : 27,
        height: double.infinity,
        child: compact && enabled
            ? const Column(
                key: ValueKey('player-overlay-mini-expand'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.drag_handle_rounded,
                    color: Color(0x88FFFFFF),
                    size: 17,
                  ),
                  Icon(Icons.open_in_full_rounded, color: _accent, size: 13),
                ],
              )
            : Icon(
                enabled ? Icons.drag_indicator_rounded : Icons.lock_rounded,
                color: enabled ? const Color(0x88FFFFFF) : _accent,
                size: compact ? 16 : 18,
              ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.onLongPress,
    this.foreground = Colors.white,
    this.background = Colors.transparent,
    this.size = 45,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Color foreground;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          onLongPress: onLongPress,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: background == Colors.transparent ? 30 : 35,
                child: Icon(icon, color: foreground, size: 21),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayTab extends StatelessWidget {
  const _OverlayTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? _accent : _muted,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: selected ? 22 : 0,
            height: 2,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyConfigRow extends StatelessWidget {
  const _KeyConfigRow({
    required this.profileLabel,
    required this.calibrationLabel,
    required this.calibrationEnabled,
    required this.onSwitch,
    required this.onCalibrate,
  });

  final String profileLabel;
  final String calibrationLabel;
  final bool calibrationEnabled;
  final VoidCallback onSwitch;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
    );
    return Material(
      color: const Color(0x10FFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 3),
        child: Row(
          children: [
            const Icon(Icons.piano_rounded, size: 17, color: _accent),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '键位配置',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    profileLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('player-overlay-key-config-switch'),
              style: buttonStyle,
              onPressed: onSwitch,
              child: const Text('切换'),
            ),
            TextButton(
              key: const ValueKey('player-overlay-key-config-calibrate'),
              style: buttonStyle,
              onPressed: calibrationEnabled ? onCalibrate : null,
              child: Text(calibrationLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceModeSelector extends StatelessWidget {
  const _PerformanceModeSelector({required this.onUnavailable});

  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) {
    const modes = <String>['自动演奏', '点击演奏', '可视化跟弹', 'MIDI串流'];
    return Material(
      color: const Color(0x10FFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var index = 0; index < modes.length; index++)
              Expanded(
                child: _PerformanceModeSegment(
                  key: ValueKey('player-overlay-performance-mode-$index'),
                  label: modes[index],
                  selected: index == 0,
                  onPressed: index == 0
                      ? null
                      : () => onUnavailable(modes[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceModeSegment extends StatelessWidget {
  const _PerformanceModeSegment({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF315F57) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: selected ? _accent : const Color(0x66FFFFFF),
              fontSize: 8.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingSubmenuHeader extends StatelessWidget {
  const _SettingSubmenuHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('player-overlay-submenu-back'),
        onTap: onBack,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              const SizedBox(
                width: 30,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 14,
                  color: _muted,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Text('返回', style: TextStyle(color: _muted, fontSize: 8.5)),
              const SizedBox(width: 7),
            ],
          ),
        ),
      ),
    );
  }
}

class _OctaveChoice extends StatelessWidget {
  const _OctaveChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x2633C6AA) : const Color(0x10FFFFFF),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: Center(
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: selected ? _accent : Colors.white,
              fontSize: 9,
              height: 1.15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationModeSelector extends StatelessWidget {
  const _DurationModeSelector({
    required this.selected,
    required this.onSelected,
  });

  final GamePlayerDurationMode selected;
  final ValueChanged<GamePlayerDurationMode> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = <GamePlayerDurationMode, String>{
      GamePlayerDurationMode.shortPress: '短按',
      GamePlayerDurationMode.repeatedTap: '连点',
      GamePlayerDurationMode.longPress: '长按',
    };
    return Material(
      color: const Color(0x10FFFFFF),
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final mode in GamePlayerDurationMode.values)
              Expanded(
                child: _PerformanceModeSegment(
                  key: ValueKey('player-overlay-duration-mode-${mode.name}'),
                  label: labels[mode]!,
                  selected: mode == selected,
                  onPressed: () => onSelected(mode),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final String key;
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.data});

  final _QuickActionData data;

  @override
  Widget build(BuildContext context) {
    final disabled = data.onPressed == null;
    final foreground = disabled
        ? _muted
        : data.danger
        ? _danger
        : data.active
        ? _accent
        : Colors.white;
    return Material(
      color: disabled
          ? const Color(0x0AFFFFFF)
          : data.danger
          ? const Color(0x18FF858C)
          : data.active
          ? const Color(0x1F63D3BC)
          : const Color(0x10FFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('player-overlay-action-${data.key}'),
        borderRadius: BorderRadius.circular(12),
        onTap: data.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            children: [
              Icon(data.icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      data.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 9),
                    ),
                  ],
                ),
              ),
              Icon(
                disabled ? Icons.schedule_rounded : Icons.chevron_right_rounded,
                size: 15,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedPreset extends StatelessWidget {
  const _SpeedPreset({
    required this.speed,
    required this.selected,
    required this.onPressed,
  });

  final double speed;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF315F57) : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('player-overlay-speed-${speed.toStringAsFixed(2)}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          height: 30,
          child: Center(
            child: Text(
              speed.toStringAsFixed(2),
              style: TextStyle(
                color: selected ? _accent : Colors.white,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerTab extends StatelessWidget {
  const _PickerTab({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? _accent : _muted,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: selected ? 20 : 0,
            height: 2,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0x1FFFFFFF));
  }
}
