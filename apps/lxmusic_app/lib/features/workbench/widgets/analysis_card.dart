import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/workbench_provider.dart';

class AnalysisCard extends ConsumerWidget {
  const AnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(analysisProvider);
    final scheme = Theme.of(context).colorScheme;

    return analysisAsync.when(
      data: (analysis) {
        if (analysis == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.outline),
                  const SizedBox(width: 12),
                  Text(
                    '请先选择完整的目标配置以触发自动分析',
                    style: TextStyle(color: scheme.outline),
                  ),
                ],
              ),
            ),
          );
        }

        final offset = analysis.pitchOffset.bestOffset;
        final best = analysis.pitchOffset.bestCandidate;
        final totalNotes = analysis.source.totalNoteCount;
        final outOfRange = best.overFlowedNoteCount + best.underFlowedNoteCount;
        final outPct = totalNotes > 0
            ? (outOfRange / totalNotes * 100).toStringAsFixed(1)
            : '0';
        final recommendedTracks = analysis.trackSelection?.recommendations
            .where((entry) => entry.recommended)
            .map((entry) => '#${entry.trackIndex + 1} ${entry.trackName}')
            .join(', ');

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '分析结果',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(label: '推荐移调', value: _formatOffset(offset)),
                _InfoRow(label: '音符总数', value: '$totalNotes'),
                _InfoRow(
                  label: '音轨数',
                  value: '${analysis.source.tracks.length}',
                ),
                if (recommendedTracks != null && recommendedTracks.isNotEmpty)
                  _InfoRow(label: '推荐音轨', value: recommendedTracks),
                _InfoRow(label: '超范围音符', value: '$outOfRange ($outPct%)'),
                _InfoRow(label: '需取整音符', value: '${best.roundedNoteCount}'),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('分析失败: $e', style: TextStyle(color: scheme.error)),
        ),
      ),
    );
  }

  String _formatOffset(int offset) {
    if (offset == 0) return '0 (无需移调)';
    final sign = offset > 0 ? '+' : '';
    final octaves = offset ~/ 12;
    final semitones = offset % 12;
    final parts = <String>[];
    if (octaves != 0) parts.add('$octaves 八度');
    if (semitones != 0) parts.add('$semitones 半音');
    return '$sign$offset (${parts.join(' ')})';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
