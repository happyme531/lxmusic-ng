import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/models/music_file.dart';
import 'providers/workbench_provider.dart';
import 'widgets/config_editor_card.dart';
import 'widgets/current_target_action.dart';
import 'widgets/file_selection_card.dart';

class WorkbenchScreen extends ConsumerStatefulWidget {
  const WorkbenchScreen({super.key, this.initialFile});

  final MusicFile? initialFile;

  @override
  ConsumerState<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends ConsumerState<WorkbenchScreen> {
  @override
  void initState() {
    super.initState();
    _applyInitialFile(widget.initialFile);
  }

  @override
  void didUpdateWidget(covariant WorkbenchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFile != null &&
        widget.initialFile?.path != oldWidget.initialFile?.path) {
      _applyInitialFile(widget.initialFile);
    }
  }

  void _applyInitialFile(MusicFile? file) {
    if (file == null) {
      return;
    }
    // Defer to after build to avoid modifying providers during build.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(selectedFileProvider.notifier).select(file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedFile = ref.watch(selectedFileProvider);
    final songConfigAsync = ref.watch(songConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('乐曲配置'),
        actions: [
          if (songConfigAsync.value != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新分析并生成推荐配置',
              onPressed: () {
                ref.read(songConfigProvider.notifier).regenerateFromAnalysis();
              },
            ),
          const CurrentTargetAction(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. File selection
          FileSelectionCard(
            file: selectedFile,
            onSelectFromLibrary: () => context.go('/library'),
          ),
          const SizedBox(height: 12),

          // 2. Config editor (only when config exists)
          if (songConfigAsync.value != null) ...[
            ConfigEditorCard(config: songConfigAsync.value!),
            const SizedBox(height: 24),
          ],

          // 3. Launch button
          if (songConfigAsync.value != null)
            FilledButton.icon(
              onPressed: () => context.go('/preview'),
              icon: const Icon(Icons.piano),
              label: const Text('打开预览'),
            ),
        ],
      ),
    );
  }
}
