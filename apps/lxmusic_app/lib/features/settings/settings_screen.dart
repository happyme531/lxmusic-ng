import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/service_locator.dart';
import '../ai/audio_to_midi/providers/audio_to_midi_provider.dart';
import '../workbench/widgets/current_target_action.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(gameProfilesProvider);
    final aiModel = ref.watch(audioToMidiProvider);
    final aiModelState = aiModel.value;
    final isClearingModelCache =
        aiModelState?.task == AudioToMidiTask.clearingModelCache;
    final canClearModelCache =
        aiModelState != null &&
        aiModelState.modelCachePresent &&
        !aiModelState.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: const [CurrentTargetAction()],
      ),
      body: ListView(
        children: [
          // Game profiles section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '游戏 Profile',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...profiles.map(
            (profile) => ListTile(
              title: Text(profile.displayName),
              subtitle: Text(
                '${profile.layouts.length} 布局 · ${profile.variants.length} 变体',
              ),
              leading: const Icon(Icons.sports_esports_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: Navigate to profile detail in Phase 2
              },
            ),
          ),
          const Divider(),

          // Storage section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '存储',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除 AI 模型缓存'),
            subtitle: Text(_modelCacheSubtitle(aiModel)),
            trailing: isClearingModelCache
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            enabled: canClearModelCache,
            onTap: canClearModelCache
                ? () => _clearAiModelCache(context, ref)
                : null,
          ),
          const Divider(),

          // About section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '关于',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('LxMusic-NG'),
            subtitle: const Text('项目介绍、仓库链接与开源协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    );
  }

  String _modelCacheSubtitle(AsyncValue<AudioToMidiState> aiModel) {
    return aiModel.when(
      loading: () => '正在检查模型缓存…',
      error: (_, _) => '无法读取模型缓存状态',
      data: (state) {
        if (state.task == AudioToMidiTask.clearingModelCache) {
          return '正在删除本地模型文件…';
        }
        if (!state.modelCachePresent) return '当前没有已下载的 AI 模型';
        if (state.modelReady) return 'MuScriptor Medium W4A32 · 约 213 MiB';
        return '包含未完成下载或旧版本模型文件';
      },
    );
  }

  Future<void> _clearAiModelCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除 AI 模型缓存'),
        content: const Text(
          '将删除本机上的全部 AI 模型和未完成的下载。'
          '已导出的 MIDI 不受影响，再次使用音频转 MIDI 时需要重新下载模型。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final cleared = await ref
        .read(audioToMidiProvider.notifier)
        .clearModelCache();
    if (!context.mounted) return;
    final message = cleared
        ? 'AI 模型缓存已清除'
        : ref.read(audioToMidiProvider).value?.errorMessage ?? '模型缓存清除失败';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
