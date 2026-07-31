import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/service_locator.dart';
import '../workbench/widgets/current_target_action.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(gameProfilesProvider);

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
}
