import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../models/song_config.dart';
import '../providers/workbench_provider.dart';

class ConfigEditorCard extends ConsumerStatefulWidget {
  const ConfigEditorCard({super.key, required this.config});

  final SongConfig config;

  @override
  ConsumerState<ConfigEditorCard> createState() => _ConfigEditorCardState();
}

class _ConfigEditorCardState extends ConsumerState<ConfigEditorCard> {
  late ConfigLevel _level;

  @override
  void initState() {
    super.initState();
    _level = widget.config.configLevel;
  }

  @override
  void didUpdateWidget(ConfigEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _level = widget.config.configLevel;
  }

  void _mutate(void Function(SongConfig c) fn) {
    ref.read(songConfigProvider.notifier).mutate(fn);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.tune, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '转换配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Level selector
            SegmentedButton<ConfigLevel>(
              segments: const [
                ButtonSegment(value: ConfigLevel.simple, label: Text('简单')),
                ButtonSegment(value: ConfigLevel.advanced, label: Text('高级')),
                ButtonSegment(value: ConfigLevel.expert, label: Text('专家')),
              ],
              selected: {_level},
              onSelectionChanged: (selection) {
                setState(() => _level = selection.first);
                _mutate((c) => c.configLevel = selection.first);
              },
            ),
            const SizedBox(height: 16),

            // Simple level params (always shown)
            ..._buildSimpleParams(config),

            // Advanced level params
            if (_level == ConfigLevel.advanced ||
                _level == ConfigLevel.expert) ...[
              const Divider(height: 32),
              ..._buildAdvancedParams(config),
            ],

            // Expert level params
            if (_level == ConfigLevel.expert) ...[
              const Divider(height: 32),
              ..._buildExpertParams(config),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Simple: 5 params
  // -------------------------------------------------------------------------

  List<Widget> _buildSimpleParams(SongConfig config) {
    return [
      // Speed
      _SliderRow(
        label: '速度',
        value: config.speed,
        min: 0.25,
        max: 3.0,
        divisions: 11,
        format: (v) => '${v.toStringAsFixed(2)}x',
        onChanged: (v) => _mutate((c) => c.speed = v),
      ),
      const SizedBox(height: 8),

      // Pitch offset
      _StepperRow(
        label: '移调',
        value: config.pitchOffset,
        min: -24,
        max: 24,
        format: (v) {
          if (v == 0) return '0';
          return v > 0 ? '+$v' : '$v';
        },
        suffix: '半音',
        recommendedValue: config.recommendedPitchOffset,
        onChanged: (v) => _mutate((c) => c.pitchOffset = v),
      ),
      const SizedBox(height: 8),

      // Skip percussion
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('跳过打击乐'),
        value: config.skipPercussion,
        onChanged: (v) => _mutate((c) => c.skipPercussion = v),
      ),

      // Humanify
      _SliderRow(
        label: '人性化',
        value: config.humanifyStrength ?? 0,
        min: 0,
        max: 30,
        divisions: 6,
        format: (v) {
          if (v == 0) return '关';
          if (v <= 5) return '轻';
          if (v <= 15) return '中';
          return '强';
        },
        onChanged: (v) =>
            _mutate((c) => c.humanifyStrength = v == 0 ? null : v),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Advanced: ~8 more params
  // -------------------------------------------------------------------------

  List<Widget> _buildAdvancedParams(SongConfig config) {
    return [
      Text(
        '高级参数',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
      const SizedBox(height: 12),

      // Semi-tone rounding mode
      _DropdownRow<String>(
        label: '半音取整模式',
        value: config.semiToneRoundingMode,
        items: const {
          'floor': '向下取整',
          'ceil': '向上取整',
          'drop': '丢弃',
          'both': '双向',
          'alternating': '交替',
          'none': '不处理',
        },
        onChanged: (v) => _mutate((c) => c.semiToneRoundingMode = v),
      ),
      const SizedBox(height: 8),

      // Same-key minimum interval
      _StepperRow(
        label: '同键最小间隔',
        value: config.sameKeyMinIntervalMs,
        min: 5,
        max: 200,
        step: 5,
        format: (v) => '$v',
        suffix: 'ms',
        onChanged: (v) => _mutate((c) => c.sameKeyMinIntervalMs = v),
      ),
      const SizedBox(height: 8),

      // Chord note count limit
      _NullableStepperRow(
        label: '和弦最大音符数',
        value: config.chordMaxNoteCount,
        min: 1,
        max: 20,
        format: (v) => v == null ? '不限' : '$v',
        onChanged: (v) => _mutate((c) => c.chordMaxNoteCount = v),
      ),
      const SizedBox(height: 8),

      // Optional steps toggles
      _OptionalStepToggle(
        label: '跳过前奏',
        stepType: 'skipIntro',
        config: config,
        defaultConfig: const {'maxIntroMs': 2000},
        onToggle: (enabled) {
          _mutate((c) {
            if (enabled) {
              c.steps.add(const TransformStep(
                type: 'skipIntro',
                config: {'maxIntroMs': 2000},
              ));
            } else {
              c.steps.removeWhere((s) => s.type == 'skipIntro');
            }
          });
        },
      ),

      _OptionalStepToggle(
        label: '限制空白时长',
        stepType: 'limitBlankDuration',
        config: config,
        defaultConfig: const {'maxBlankDurationMs': 5000},
        onToggle: (enabled) {
          _mutate((c) {
            if (enabled) {
              c.steps.add(const TransformStep(
                type: 'limitBlankDuration',
                config: {'maxBlankDurationMs': 5000},
              ));
            } else {
              c.steps.removeWhere((s) => s.type == 'limitBlankDuration');
            }
          });
        },
      ),

      _OptionalStepToggle(
        label: '合并相邻音符',
        stepType: 'mergeNearbyNotes',
        config: config,
        defaultConfig: const {'maxIntervalMs': 30, 'maxBatchSize': 19},
        onToggle: (enabled) {
          _mutate((c) {
            if (enabled) {
              c.steps.add(const TransformStep(
                type: 'mergeNearbyNotes',
                config: {'maxIntervalMs': 30, 'maxBatchSize': 19},
              ));
            } else {
              c.steps.removeWhere((s) => s.type == 'mergeNearbyNotes');
            }
          });
        },
      ),

      _OptionalStepToggle(
        label: '折叠高频重复音符',
        stepType: 'foldFrequentSameNote',
        config: config,
        defaultConfig: const {'maxIntervalMs': 150},
        onToggle: (enabled) {
          _mutate((c) {
            if (enabled) {
              c.steps.add(const TransformStep(
                type: 'foldFrequentSameNote',
                config: {'maxIntervalMs': 150},
              ));
            } else {
              c.steps.removeWhere((s) => s.type == 'foldFrequentSameNote');
            }
          });
        },
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Expert: pipeline step list
  // -------------------------------------------------------------------------

  List<Widget> _buildExpertParams(SongConfig config) {
    return [
      Text(
        'Pipeline 步骤',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
      const SizedBox(height: 8),
      Text(
        '共 ${config.steps.length} 步',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
      const SizedBox(height: 8),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: config.steps.length,
        onReorder: (oldIdx, newIdx) {
          _mutate((c) {
            if (newIdx > oldIdx) newIdx--;
            final step = c.steps.removeAt(oldIdx);
            c.steps.insert(newIdx, step);
          });
        },
        itemBuilder: (context, index) {
          final step = config.steps[index];
          return ListTile(
            key: ValueKey('$index-${step.type}'),
            dense: true,
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, size: 20),
            ),
            title: Text(step.type, style: const TextStyle(fontSize: 13)),
            subtitle: step.config.isNotEmpty
                ? Text(
                    step.config.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  )
                : null,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () {
                _mutate((c) => c.steps.removeAt(index));
              },
            ),
          );
        },
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Reusable param widgets
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(format(value), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
    this.recommendedValue,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int) format;
  final String suffix;
  final int? recommendedValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value > min ? () => onChanged(value - step) : null,
        ),
        Text(
          '${format(value)} $suffix',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: value < max ? () => onChanged(value + step) : null,
        ),
        if (recommendedValue != null && recommendedValue != value)
          TextButton(
            onPressed: () => onChanged(recommendedValue!),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '推荐: ${format(recommendedValue!)}',
              style: TextStyle(fontSize: 11, color: scheme.primary),
            ),
          ),
      ],
    );
  }
}

class _NullableStepperRow extends StatelessWidget {
  const _NullableStepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final int min;
  final int max;
  final String Function(int?) format;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        if (value == null)
          TextButton(
            onPressed: () => onChanged(min),
            child: Text(format(null)),
          )
        else ...[
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: value! > min
                ? () => onChanged(value! - 1)
                : () => onChanged(null),
          ),
          Text(format(value),
              style: const TextStyle(fontWeight: FontWeight.w500)),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: value! < max ? () => onChanged(value! + 1) : null,
          ),
        ],
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownMenu<T>(
            expandedInsets: EdgeInsets.zero,
            initialSelection: value,
            dropdownMenuEntries: items.entries
                .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                .toList(),
            onSelected: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _OptionalStepToggle extends StatelessWidget {
  const _OptionalStepToggle({
    required this.label,
    required this.stepType,
    required this.config,
    required this.defaultConfig,
    required this.onToggle,
  });

  final String label;
  final String stepType;
  final SongConfig config;
  final Map<String, Object?> defaultConfig;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = config.steps.any((s) => s.type == stepType);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: enabled,
      onChanged: (v) => onToggle(v),
    );
  }
}
