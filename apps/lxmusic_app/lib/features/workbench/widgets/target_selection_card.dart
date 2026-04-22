import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../core/service_locator.dart';
import '../providers/workbench_provider.dart';

class TargetSelectionCard extends ConsumerWidget {
  const TargetSelectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(gameProfilesProvider);
    final selectedProfile = ref.watch(selectedProfileProvider);
    final selectedVariant = ref.watch(selectedVariantProvider);
    final selectedLayout = ref.watch(selectedLayoutProvider);
    final layoutRepo = ref.watch(layoutRepositoryProvider);

    // Build the available variants and layouts from the selected profile
    final variants = selectedProfile?.variants ?? [];
    final layoutBindings = selectedProfile?.layouts ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '目标配置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),

            // Game profile
            DropdownMenu<GameProfile>(
              label: const Text('游戏 Profile'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: selectedProfile,
              dropdownMenuEntries: profiles
                  .map((p) => DropdownMenuEntry(
                        value: p,
                        label: p.displayName,
                      ))
                  .toList(),
              onSelected: (profile) {
                if (profile == null) return;
                ref.read(selectedProfileProvider.notifier).select(profile);
                // Auto-select default variant
                if (profile.variants.isNotEmpty) {
                  ref
                      .read(selectedVariantProvider.notifier)
                      .select(profile.variants.first);
                }
                // Auto-select default layout
                final defaultBinding = profile.layouts.firstWhere(
                  (b) => b.isDefault,
                  orElse: () => profile.layouts.first,
                );
                try {
                  final layout = layoutRepo.load(defaultBinding.layoutId);
                  ref.read(selectedLayoutProvider.notifier).select(layout);
                } catch (_) {}
              },
            ),
            const SizedBox(height: 12),

            // Variant
            if (variants.isNotEmpty)
              DropdownMenu<InstrumentVariant>(
                label: const Text('乐器变体'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: selectedVariant,
                dropdownMenuEntries: variants
                    .map((v) => DropdownMenuEntry(
                          value: v,
                          label: v.displayName,
                        ))
                    .toList(),
                onSelected: (variant) {
                  if (variant != null) {
                    ref.read(selectedVariantProvider.notifier).select(variant);
                  }
                },
              ),
            if (variants.isNotEmpty) const SizedBox(height: 12),

            // Layout
            if (layoutBindings.isNotEmpty)
              DropdownMenu<String>(
                label: const Text('键位布局'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: selectedLayout?.id,
                dropdownMenuEntries: layoutBindings
                    .map((b) => DropdownMenuEntry(
                          value: b.layoutId,
                          label: b.displayName ?? b.layoutId,
                        ))
                    .toList(),
                onSelected: (layoutId) {
                  if (layoutId == null) return;
                  try {
                    final layout = layoutRepo.load(layoutId);
                    ref.read(selectedLayoutProvider.notifier).select(layout);
                  } catch (_) {}
                },
              ),
          ],
        ),
      ),
    );
  }
}
