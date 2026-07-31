import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../core/service_locator.dart';
import 'layout_key_label_formatter.dart';
import 'widgets/key_layout_preview_canvas.dart';

final layoutPreviewOrientationSupportedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return false;
      }
      return (await ref.watch(calibrationPlatformProvider).getState())
          .orientationLockSupported;
    });

class LayoutPreviewScreen extends ConsumerStatefulWidget {
  const LayoutPreviewScreen({
    super.key,
    required this.profileId,
    required this.layoutId,
    this.initialSelectedKeyId,
  });

  final String profileId;
  final String layoutId;
  final String? initialSelectedKeyId;

  @override
  ConsumerState<LayoutPreviewScreen> createState() =>
      _LayoutPreviewScreenState();
}

class _LayoutPreviewScreenState extends ConsumerState<LayoutPreviewScreen> {
  LayoutLabelMode _labelMode = LayoutLabelMode.numbered;
  bool _hasOrientationOverride = false;
  String? _selectedKeyId;

  @override
  void initState() {
    super.initState();
    _selectedKeyId = widget.initialSelectedKeyId;
  }

  @override
  void didUpdateWidget(covariant LayoutPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutId != widget.layoutId ||
        oldWidget.profileId != widget.profileId ||
        oldWidget.initialSelectedKeyId != widget.initialSelectedKeyId) {
      _selectedKeyId = widget.initialSelectedKeyId;
      _labelMode = LayoutLabelMode.numbered;
    }
  }

  @override
  void dispose() {
    if (_hasOrientationOverride) {
      unawaited(
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _loadProfile();
    final layout = _loadLayout();
    if (profile == null || layout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('键位预览')),
        body: const Center(child: Text('无法加载这个键位布局')),
      );
    }

    final binding = profile.layoutById(layout.id);
    final layoutTitle =
        binding?.displayName ??
        (layout.metadata['displayName'] as String?) ??
        layout.id;
    final selectedKey = _resolveSelectedKey(layout);
    // TODO(variant-layout-preview): Carry variantId into this route before
    // presenting effective pitches here; this screen currently documents the
    // nominal physical layout only.
    final displayConfig = LayoutPreviewDisplayConfig(labelMode: _labelMode);
    final isLandscapePreview =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final supportsOrientationToggle =
        ref.watch(layoutPreviewOrientationSupportedProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(layoutTitle),
            Text(
              profile.displayName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (supportsOrientationToggle) ...[
            TextButton.icon(
              key: const ValueKey('layout-preview-orientation-toggle'),
              onPressed: () => _togglePreviewOrientation(isLandscapePreview),
              icon: Icon(
                isLandscapePreview
                    ? Icons.stay_current_portrait_rounded
                    : Icons.stay_current_landscape_rounded,
              ),
              label: Text(isLandscapePreview ? '竖屏' : '横屏'),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final previewWidth = _previewWidthFor(
            constraints.maxWidth.clamp(320.0, 920.0),
            layout.keys,
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '基础布局预览',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${layout.keys.length} 键',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                SegmentedButton<LayoutLabelMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: LayoutLabelMode.numbered,
                                      label: Text('简谱'),
                                    ),
                                    ButtonSegment(
                                      value: LayoutLabelMode.pitchName,
                                      label: Text('音名'),
                                    ),
                                  ],
                                  selected: <LayoutLabelMode>{_labelMode},
                                  onSelectionChanged: (selection) {
                                    setState(() {
                                      _labelMode = selection.first;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '显示布局定义的标称音高；乐器变体的实际音高请在乐曲预览中查看。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            _FittedLayoutPreview(
                              naturalWidth: previewWidth,
                              layout: layout,
                              config: displayConfig,
                              selectedKeyId: selectedKey?.id,
                              onKeyTap: (key) {
                                setState(() {
                                  _selectedKeyId = key.id;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SelectedKeyCard(
                      selectedKey: selectedKey,
                      labelMode: _labelMode,
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

  GameProfile? _loadProfile() {
    try {
      return ref.read(profileRepositoryProvider).load(widget.profileId);
    } catch (_) {
      return null;
    }
  }

  KeyLayout? _loadLayout() {
    try {
      return ref.read(layoutRepositoryProvider).load(widget.layoutId);
    } catch (_) {
      return null;
    }
  }

  KeyDefinition? _resolveSelectedKey(KeyLayout layout) {
    if (layout.keys.isEmpty) {
      return null;
    }
    final selected = _selectedKeyId == null
        ? null
        : layout.keys.where((key) => key.id == _selectedKeyId).firstOrNull;
    return selected ?? layout.keys.first;
  }

  Future<void> _togglePreviewOrientation(bool isLandscapePreview) async {
    final requestLandscape = !isLandscapePreview;
    setState(() {
      _hasOrientationOverride = true;
    });

    try {
      await SystemChrome.setPreferredOrientations(
        requestLandscape
            ? const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const <DeviceOrientation>[
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
      );
    } on PlatformException {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasOrientationOverride = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前设备无法切换预览方向')));
    }
  }

  double _previewWidthFor(double viewportWidth, List<KeyDefinition> keys) {
    final columnCount = _clusterCount(keys.map((key) => key.normX));
    final widthFactor = mathFactorForColumns(columnCount);
    return viewportWidth * widthFactor;
  }

  int _clusterCount(Iterable<double> values) {
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

  double mathFactorForColumns(int columns) {
    return (columns / 14).clamp(1.0, 4.0);
  }
}

class _FittedLayoutPreview extends StatelessWidget {
  const _FittedLayoutPreview({
    required this.naturalWidth,
    required this.layout,
    required this.config,
    required this.selectedKeyId,
    required this.onKeyTap,
  });

  final double naturalWidth;
  final KeyLayout layout;
  final LayoutPreviewDisplayConfig config;
  final String? selectedKeyId;
  final ValueChanged<KeyDefinition> onKeyTap;

  @override
  Widget build(BuildContext context) {
    const landscapeAspectRatio = 16 / 9;
    final naturalHeight = naturalWidth / landscapeAspectRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(1.0, constraints.maxWidth / naturalWidth);
        return SizedBox(
          key: const ValueKey('layout-preview-fit-frame'),
          width: constraints.maxWidth,
          height: naturalHeight * scale,
          child: FittedBox(
            key: const ValueKey('layout-preview-fitted-box'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const ValueKey('layout-preview-natural-canvas'),
              width: naturalWidth,
              height: naturalHeight,
              child: KeyLayoutPreviewCanvas(
                layout: layout,
                config: config,
                selectedKeyId: selectedKeyId,
                onKeyTap: onKeyTap,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectedKeyCard extends StatelessWidget {
  const _SelectedKeyCard({required this.selectedKey, required this.labelMode});

  final KeyDefinition? selectedKey;
  final LayoutLabelMode labelMode;

  @override
  Widget build(BuildContext context) {
    final key = selectedKey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: key == null
            ? const Text('点一个按键看详情')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前按键',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoPill(
                        valueKey: const ValueKey('selected-key-label'),
                        label: '显示',
                        value: key.pitch == null
                            ? key.id
                            : LayoutKeyLabelFormatter.format(
                                pitch: key.pitch!,
                                mode: labelMode,
                              ),
                      ),
                      _InfoPill(
                        valueKey: const ValueKey('selected-key-id'),
                        label: '键位 ID',
                        value: key.id,
                      ),
                      if (key.pitch != null)
                        _InfoPill(
                          valueKey: const ValueKey('selected-key-pitch-name'),
                          label: '音名',
                          value: LayoutKeyLabelFormatter.formatPitchName(
                            key.pitch!,
                          ),
                        ),
                      if (key.pitch != null)
                        _InfoPill(
                          valueKey: const ValueKey('selected-key-midi'),
                          label: 'MIDI',
                          value: '${key.pitch}',
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({this.valueKey, required this.label, required this.value});

  final Key? valueKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
