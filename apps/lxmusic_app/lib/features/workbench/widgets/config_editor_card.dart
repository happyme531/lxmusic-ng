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
    _level = _normalizeLevel(widget.config.configLevel);
  }

  @override
  void didUpdateWidget(ConfigEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _level = _normalizeLevel(widget.config.configLevel);
  }

  void _mutate(void Function(SongConfig c) fn) {
    ref.read(songConfigProvider.notifier).mutate(fn);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final scheme = Theme.of(context).colorScheme;
    final reportAsync = ref.watch(configReportProvider);
    final currentPitchAnalysisAsync = ref.watch(currentPitchAnalysisProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            SegmentedButton<ConfigLevel>(
              segments: const [
                ButtonSegment(value: ConfigLevel.simple, label: Text('简单')),
                ButtonSegment(value: ConfigLevel.advanced, label: Text('高级')),
              ],
              selected: {_level},
              onSelectionChanged: (selection) {
                setState(() => _level = selection.first);
                _mutate((c) => c.configLevel = selection.first);
              },
            ),
            const SizedBox(height: 18),
            ..._buildOptions(config, currentPitchAnalysisAsync),
            if (_level == ConfigLevel.advanced) ...[
              const Divider(height: 32),
              _ExpertPipelineView(steps: config.steps),
            ],
            const Divider(height: 32),
            _SectionHeader(
              icon: Icons.insights_outlined,
              title: '转换摘要',
              subtitle: '用当前配置实际运行 transform 后的结果',
            ),
            const SizedBox(height: 10),
            _ReportSummary(reportAsync: reportAsync, config: config),
          ],
        ),
      ),
    );
  }

  ConfigLevel _normalizeLevel(ConfigLevel level) {
    return level == ConfigLevel.expert ? ConfigLevel.advanced : level;
  }

  List<Widget> _buildOptions(
    SongConfig config,
    AsyncValue<ScoreAnalysis?> analysisAsync,
  ) {
    final trackSelection = analysisAsync.value?.trackSelection;
    return [
      if (_level == ConfigLevel.advanced) ...[
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
        _StepperRow(
          label: '八度',
          value: config.pitchOctaveOffset,
          min: -2,
          max: 2,
          format: _formatOffset,
          suffix: '个',
          recommendedValue: config.recommendedPitchOctaveOffset,
          onChanged: (v) => _mutate((c) => c.pitchOctaveOffset = v),
        ),
        _StepperRow(
          label: '半音',
          value: config.pitchSemitoneOffset,
          min: -11,
          max: 11,
          format: _formatOffset,
          suffix: '个',
          recommendedValue: config.recommendedPitchSemitoneOffset,
          onChanged: (v) => _mutate((c) => c.pitchSemitoneOffset = v),
        ),
      ] else ...[
        _FixOption<int>(
          title: '八度',
          value: config.simplePitchOctaveShift,
          options: const {-1: '降低一个', 0: '不变', 1: '升高一个'},
          onChanged: (value) =>
              _mutate((c) => c.simplePitchOctaveShift = value),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('跳过空白'),
        value: config.skipBlank,
        onChanged: (value) => _mutate((c) => c.skipBlank = value),
      ),
      if (trackSelection != null) ...[
        _TrackSelectionEditor(
          selection: trackSelection,
          selectedTrackIndexes: config.selectedTrackIndexes,
          onChanged: (value) => _mutate((c) => c.selectedTrackIndexes = value),
        ),
        const SizedBox(height: 8),
      ],
      _FixOption<int?>(
        title: '多指模式',
        value: config.chordMaxNoteCount,
        options: const {null: '不限', 3: '3', 2: '2', 1: '1'},
        onChanged: (value) => _mutate((c) => c.chordMaxNoteCount = value),
      ),
      _FixOption<int>(
        title: '同键间隔',
        value: config.sameKeyMinIntervalMs,
        options: const {20: '默认', 35: '稍松', 50: '更稳'},
        onChanged: (value) => _mutate((c) => c.sameKeyMinIntervalMs = value),
      ),
      if (_level == ConfigLevel.advanced)
        _ClickLimitSlider(
          value: config.clickLimitPerSecond,
          onChanged: (value) => _mutate((c) => c.clickLimitPerSecond = value),
        )
      else
        _FixOption<int?>(
          title: '限制点击速度',
          value: _simpleClickLimitValue(config.clickLimitPerSecond),
          options: const {
            null: '不限',
            5: '每秒 5 个',
            3: '每秒 3 个',
            2: '每秒 2 个',
            1: '每秒 1 个',
          },
          onChanged: (value) =>
              _mutate((c) => c.clickLimitPerSecond = value?.toDouble()),
        ),
      _SliderRow(
        label: '人性化',
        value: config.humanifyStrength ?? 0,
        min: 0,
        max: 30,
        divisions: 6,
        format: _formatHumanify,
        onChanged: (v) =>
            _mutate((c) => c.humanifyStrength = v == 0 ? null : v),
      ),
      if (_level == ConfigLevel.advanced) ...[
        const SizedBox(height: 8),
        _OptionalStepSwitch(
          title: '移动高八度音符到音域内',
          subtitle: '高于目标音域一个八度内的音符会降八度保留',
          enabled: config.wrapHigherOctaveIntoRange,
          onChanged: (enabled) =>
              _mutate((c) => c.wrapHigherOctaveIntoRange = enabled),
        ),
        _OptionalStepSwitch(
          title: '移动低八度音符到音域内',
          subtitle: '低于目标音域一个八度内的音符会升八度保留',
          enabled: config.wrapLowerOctaveIntoRange,
          onChanged: (enabled) =>
              _mutate((c) => c.wrapLowerOctaveIntoRange = enabled),
        ),
        _OptionalStepSwitch(
          title: '合并过近音符',
          subtitle: '把 50ms 内的相邻音组合成同一批',
          enabled: _hasStep(config, 'mergeNearbyNotes'),
          onChanged: (enabled) => _mutate(
            (c) => _setOptionalStep(
              c,
              enabled: enabled,
              step: const TransformStep(
                type: 'mergeNearbyNotes',
                config: {'maxIntervalMs': 50, 'maxBatchSize': 19},
              ),
            ),
          ),
        ),
        _OptionalStepSwitch(
          title: '折叠重复音符',
          subtitle: '减少短时间内反复出现的同音',
          enabled: _hasStep(config, 'foldFrequentSameNote'),
          onChanged: (enabled) => _mutate(
            (c) => _setOptionalStep(
              c,
              enabled: enabled,
              step: const TransformStep(
                type: 'foldFrequentSameNote',
                config: {'maxIntervalMs': 150},
              ),
            ),
          ),
        ),
      ],
    ];
  }

  bool _hasStep(SongConfig config, String type) {
    return config.steps.any((step) => step.type == type);
  }

  void _setOptionalStep(
    SongConfig config, {
    required bool enabled,
    required TransformStep step,
  }) {
    config.setOptionalTransformStep(enabled: enabled, step: step);
  }

  String _formatOffset(int value) {
    if (value == 0) return '0';
    return value > 0 ? '+$value' : '$value';
  }

  String _formatHumanify(double value) {
    if (value == 0) return '关';
    if (value <= 5) return '轻';
    if (value <= 15) return '中';
    return '强';
  }

  int? _simpleClickLimitValue(double? value) {
    if (value == null) return null;
    const options = <int>[5, 3, 2, 1];
    for (final option in options) {
      if ((value - option).abs() < 0.05) {
        return option;
      }
    }
    return null;
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.reportAsync, required this.config});

  final AsyncValue<ConfigReportSummary?> reportAsync;
  final SongConfig config;

  @override
  Widget build(BuildContext context) {
    return reportAsync.when(
      data: (report) {
        if (report == null) {
          return const Text('选择乐曲和目标后会显示转换结果');
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(
              label: '音符',
              value: '${report.inputNoteCount} -> ${report.outputNoteCount}',
            ),
            _MetricChip(label: '丢弃', value: '${report.pipelineNotesRemoved}'),
            _MetricChip(label: '新增', value: '${report.pipelineNotesAdded}'),
            _MetricChip(label: '超音域', value: '${report.outOfRangeDiscarded}'),
            _MetricChip(label: '过密过滤', value: '${report.tooDenseDiscarded}'),
            _MetricChip(label: '和弦过滤', value: '${report.chordNotesDiscarded}'),
          ],
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => Text(
        '转换报告生成失败: $error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _ExpertPipelineView extends StatelessWidget {
  const _ExpertPipelineView({required this.steps});

  final List<TransformStep> steps;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text('Pipeline（共 ${steps.length} 步）'),
      subtitle: const Text('只读展示，用于确认内部 transform 顺序和参数'),
      children: [
        for (var index = 0; index < steps.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 13,
              child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
            ),
            title: Text(_stepLabel(steps[index].type)),
            subtitle: steps[index].config.isEmpty
                ? const Text('无参数')
                : Text(
                    steps[index].config.entries
                        .map((entry) => '${entry.key}: ${entry.value}')
                        .join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
      ],
    );
  }

  static String _stepLabel(String type) {
    return switch (type) {
      'mergeTracks' => '合并音轨',
      'removeEmptyTracks' => '移除空音轨',
      'pitchOffset' => '移调',
      'legalizeTargetNoteRange' => '音域合法化',
      'storeCurrentNoteTime' => '保存原始时间',
      'singleKeyFrequencyLimit' => '同键频率限制',
      'bindLyrics' => '绑定歌词',
      'noteToKey' => '映射到按键',
      'mergeNearbyNotes' => '合并相邻音符',
      'foldFrequentSameNote' => '折叠重复音符',
      'estimateNoteDuration' => '估算音符时长',
      'splitLongNote' => '拆分长音',
      'speedChange' => '速度调整',
      'limitBlankDuration' => '限制长空白',
      'skipIntro' => '跳过前奏',
      'noteFrequencySoftLimit' => '音符频率软限制',
      'chordNoteCountLimit' => '和弦数量限制',
      'humanify' => '人性化时间偏差',
      _ => type,
    };
  }
}

class _TrackSelectionEditor extends StatelessWidget {
  const _TrackSelectionEditor({
    required this.selection,
    required this.selectedTrackIndexes,
    required this.onChanged,
  });

  final TrackSelectionAnalysis selection;
  final List<int>? selectedTrackIndexes;
  final ValueChanged<List<int>?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '音轨选择',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectionSummary(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _showTrackSheet(context),
            icon: const Icon(Icons.queue_music_outlined),
            label: const Text('选择'),
          ),
        ],
      ),
    );
  }

  String _selectionSummary() {
    if (selectedTrackIndexes == null || selectedTrackIndexes!.isEmpty) {
      return '全部音轨';
    }
    final selected = selectedTrackIndexes!.toSet();
    final names = selection.recommendations
        .where((item) => selected.contains(item.trackIndex))
        .map((item) => '#${item.trackIndex + 1} ${item.trackName}')
        .toList();
    if (names.isEmpty) {
      return '已选择 ${selected.length} 条音轨';
    }
    return names.join(', ');
  }

  Future<void> _showTrackSheet(BuildContext context) async {
    final recommended = selection.recommendedTrackIndexes.toSet();
    Set<int>? draft = selectedTrackIndexes == null
        ? null
        : Set<int>.from(selectedTrackIndexes!);
    var applied = false;

    final result = await showModalBottomSheet<List<int>?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allSelected = draft == null;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '音轨选择',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: recommended.isEmpty
                              ? null
                              : () {
                                  setSheetState(() {
                                    draft = Set<int>.from(recommended);
                                  });
                                },
                          child: const Text('使用推荐'),
                        ),
                      ],
                    ),
                    Text(
                      '只合并选中的音轨；不确定时选“全部”。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('全部音轨'),
                            subtitle: const Text('不写入 selectedTracks'),
                            value: allSelected,
                            onChanged: (_) {
                              setSheetState(() {
                                draft = null;
                              });
                            },
                          ),
                          const Divider(height: 1),
                          for (final item in selection.recommendations)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: SizedBox(
                                width: 36,
                                child: Text(
                                  '#${item.trackIndex + 1}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(item.trackName),
                              subtitle: Text(_trackSubtitle(item)),
                              value: draft?.contains(item.trackIndex) ?? false,
                              onChanged: (_) {
                                setSheetState(() {
                                  final next = (draft ?? <int>{}).toSet();
                                  if (next.contains(item.trackIndex)) {
                                    next.remove(item.trackIndex);
                                  } else {
                                    next.add(item.trackIndex);
                                  }
                                  draft = next;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final value = draft == null || draft!.isEmpty
                                ? null
                                : (draft!.toList()..sort());
                            applied = true;
                            Navigator.of(sheetContext).pop(value);
                          },
                          child: const Text('应用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied) {
      onChanged(result);
    }
  }

  String _trackSubtitle(TrackPlayabilityRecommendation item) {
    final ratio = (item.playableRatio * 100).round();
    final parts = <String>[
      if (item.recommended) '推荐',
      if (item.isPercussion) '打击乐，默认不推荐',
      '可演奏 $ratio%',
      '${item.playableNoteCount}/${item.noteCount} 音符',
    ];
    return parts.join(' · ');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: scheme.outline)),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _FixOption<T> extends StatelessWidget {
  const _FixOption({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: entry.key == value,
                  onSelected: (_) => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionalStepSwitch extends StatelessWidget {
  const _OptionalStepSwitch({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: onChanged,
    );
  }
}

class _ClickLimitSlider extends StatelessWidget {
  const _ClickLimitSlider({required this.value, required this.onChanged});

  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = value != null;
    final sliderValue = (value ?? 5).clamp(1.0, 10.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('限制点击速度'),
            subtitle: Text(
              enabled ? '每秒 ${sliderValue.toStringAsFixed(1)} 个' : '不限',
            ),
            value: enabled,
            onChanged: (nextEnabled) =>
                onChanged(nextEnabled ? sliderValue : null),
          ),
          if (enabled)
            _SliderRow(
              label: '上限',
              value: sliderValue,
              min: 1,
              max: 10,
              divisions: 90,
              format: (v) => '${v.toStringAsFixed(1)}/s',
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

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
    this.suffix = '',
    this.recommendedValue,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int) format;
  final String suffix;
  final int? recommendedValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text(
          '${format(value)} $suffix',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: value < max ? () => onChanged(value + 1) : null,
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
