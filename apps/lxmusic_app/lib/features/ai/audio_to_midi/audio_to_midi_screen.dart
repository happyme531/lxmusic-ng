import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/audio_to_midi_provider.dart';

class AudioToMidiScreen extends ConsumerWidget {
  const AudioToMidiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(audioToMidiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 音频转 MIDI')),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _FatalError(error: error),
        data: (state) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _ModelCard(state: state),
            const SizedBox(height: 16),
            _AudioCard(state: state, onPick: () => _pickAudio(context, ref)),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: state.rightsConfirmed,
              onChanged: state.isBusy
                  ? null
                  : (value) => ref
                        .read(audioToMidiProvider.notifier)
                        .setRightsConfirmed(value ?? false),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('我确认拥有所选音频的必要权利'),
              subtitle: const Text('模型权重为 CC BY-NC 4.0，仅限非商业用途。'),
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              _ErrorBanner(message: state.errorMessage!),
            ],
            if (state.isBusy || state.statusMessage.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _ProgressCard(state: state),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: state.canConvert
                    ? () => ref.read(audioToMidiProvider.notifier).convert()
                    : null,
                icon: state.isConverting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(state.isConverting ? '正在转换…' : '一键转换为 MIDI'),
              ),
            ),
            if (state.result != null) ...<Widget>[
              const SizedBox(height: 20),
              _ResultCard(
                state: state,
                onRetrySave: () => ref
                    .read(audioToMidiProvider.notifier)
                    .saveCurrentResultToLibrary(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudio(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp3',
        'wav',
        'flac',
        'm4a',
        'aac',
        'ogg',
        'opus',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.path == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前平台无法取得所选音频的本地路径')));
      }
      return;
    }
    ref
        .read(audioToMidiProvider.notifier)
        .selectAudio(path: file.path!, name: file.name);
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({required this.state});

  final AudioToMidiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.memory),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'MuScriptor Medium W4A32',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text('约 213 MiB, 中等精度, ONNX Runtime CPU推理'),
                    ],
                  ),
                ),
                if (state.modelReady)
                  const Chip(
                    avatar: Icon(Icons.check_circle, size: 18),
                    label: Text('已就绪'),
                  ),
              ],
            ),
            if (!state.modelReady) ...<Widget>[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                            .read(audioToMidiProvider.notifier)
                            .downloadModel(),
                  icon: const Icon(Icons.download),
                  label: const Text('下载量化模型'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.state, required this.onPick});

  final AudioToMidiState state;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedAudioName != null;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          child: Icon(
            selected ? Icons.audio_file : Icons.library_music_outlined,
          ),
        ),
        title: Text(selected ? state.selectedAudioName! : '选择音频'),
        subtitle: Text(
          selected ? '已选择，准备进行端侧转录' : 'MP3 / WAV / FLAC / M4A / AAC / OGG',
        ),
        trailing: OutlinedButton(
          onPressed: state.isBusy ? null : onPick,
          child: Text(selected ? '更换' : '选择'),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});

  final AudioToMidiState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(state.statusMessage.isEmpty ? '处理中…' : state.statusMessage),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress.clamp(0, 1) : null,
            ),
            if (state.task == AudioToMidiTask.transcribing) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                '自回归转录耗时取决于音频复杂度与设备 CPU，请保持应用在前台。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state, required this.onRetrySave});

  final AudioToMidiState state;
  final VoidCallback onRetrySave;

  @override
  Widget build(BuildContext context) {
    final result = state.result!;
    final seconds = result.elapsed.inMilliseconds / 1000;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.task_alt),
                SizedBox(width: 10),
                Text(
                  '转换完成',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text('${result.notes.length} 个音符')),
                Chip(label: Text('${result.trackCount} 条音轨')),
                Chip(label: Text('${result.chunkCount} 个片段')),
                Chip(label: Text('耗时 ${seconds.toStringAsFixed(1)} 秒')),
              ],
            ),
            const SizedBox(height: 14),
            if (state.savedMidiFileName case final fileName?)
              Row(
                children: <Widget>[
                  const Icon(Icons.library_add_check),
                  const SizedBox(width: 10),
                  Expanded(child: Text('已自动保存到曲库：$fileName')),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: state.isBusy ? null : onRetrySave,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    state.task == AudioToMidiTask.savingToLibrary
                        ? '正在保存到曲库…'
                        : '重新保存到曲库',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('初始化失败：$error'));
  }
}
