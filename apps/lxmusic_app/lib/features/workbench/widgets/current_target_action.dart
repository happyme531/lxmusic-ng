import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../core/service_locator.dart';
import '../../calibration/calibration_launcher.dart';
import '../../calibration/platform/calibration_platform.dart';
import '../../calibration/providers/calibration_provider.dart';
import '../../layout_preview/layout_preview_route.dart';
import '../../library/models/music_file.dart';
import '../providers/workbench_provider.dart';

class CurrentTargetAction extends ConsumerStatefulWidget {
  const CurrentTargetAction({super.key});

  @override
  ConsumerState<CurrentTargetAction> createState() =>
      _CurrentTargetActionState();
}

class _CurrentTargetActionState extends ConsumerState<CurrentTargetAction>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _supportsAndroidCalibration) {
      unawaited(_consumeCalibrationResult());
    }
  }

  Future<void> _consumeCalibrationResult() async {
    try {
      final result = await ref
          .read(calibrationManagerProvider.notifier)
          .refresh();
      if (!mounted || result == null) {
        return;
      }
      final message = switch (result.status) {
        CalibrationSessionStatus.saved => '键位校准已保存',
        CalibrationSessionStatus.cancelled => '键位校准已取消',
        CalibrationSessionStatus.error =>
          result.message ?? '键位校准失败：${result.errorCode ?? 'unknown'}',
        CalibrationSessionStatus.started => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取校准结果失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selectedProfileProvider);
    final variant = ref.watch(selectedVariantProvider);
    final layout = ref.watch(selectedLayoutProvider);
    final selectedFile = ref.watch(selectedFileProvider);
    final label = _actionLabel(profile, variant, layout);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: '当前配置: $label',
        child: TextButton.icon(
          key: const ValueKey('current-target-action'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            foregroundColor: scheme.onSurface,
            backgroundColor: scheme.surface.withValues(alpha: 0.84),
          ),
          icon: const Icon(Icons.tune, size: 18),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          onPressed: () {
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (sheetContext) {
                return _CurrentTargetPickerSheet(
                  initialProfile: profile,
                  initialVariant: variant,
                  initialLayout: layout,
                  selectedFile: selectedFile,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _actionLabel(
  GameProfile? profile,
  InstrumentVariant? variant,
  KeyLayout? layout,
) {
  final parts = <String>[
    if (profile != null) profile.displayName,
    if (variant != null) variant.displayName,
    if (layout != null)
      profile?.layoutById(layout.id)?.displayName ??
          (layout.metadata['displayName'] as String?) ??
          layout.id,
  ];
  if (parts.isEmpty) {
    return '未选择配置';
  }
  return parts.join(' / ');
}

enum _PickerStage { profile, variant, layout }

class _CurrentTargetPickerSheet extends ConsumerStatefulWidget {
  const _CurrentTargetPickerSheet({
    required this.initialProfile,
    required this.initialVariant,
    required this.initialLayout,
    required this.selectedFile,
  });

  final GameProfile? initialProfile;
  final InstrumentVariant? initialVariant;
  final KeyLayout? initialLayout;
  final MusicFile? selectedFile;

  @override
  ConsumerState<_CurrentTargetPickerSheet> createState() =>
      _CurrentTargetPickerSheetState();
}

class _CurrentTargetPickerSheetState
    extends ConsumerState<_CurrentTargetPickerSheet> {
  late _PickerStage _stage;
  late final GameProfile? _committedProfile;
  late final InstrumentVariant? _committedVariant;
  late final KeyLayout? _committedLayout;
  GameProfile? _profile;
  InstrumentVariant? _variant;
  KeyLayout? _layout;
  String _filterQuery = '';
  bool _startingCalibration = false;
  bool? _hasCalibration;

  @override
  void initState() {
    super.initState();
    _committedProfile = widget.initialProfile;
    _committedVariant = widget.initialVariant;
    _committedLayout = widget.initialLayout;
    _profile = null;
    _variant = null;
    _layout = null;
    _stage = _PickerStage.profile;
    if (_supportsAndroidCalibration &&
        _committedProfile != null &&
        _committedLayout != null) {
      unawaited(_loadCalibrationStatus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(gameProfilesProvider);
    final profileUsage = ref.watch(persistedProfileUsageProvider);
    final filteredProfiles = _filterProfiles(profiles, profileUsage);
    final filteredVariants = _filterVariants();
    final filteredLayouts = _filterLayouts();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '当前配置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _targetSummary(
                        _committedProfile,
                        _committedVariant,
                        _committedLayout,
                        emptyText: '还没有生效配置',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            _committedProfile != null &&
                                _committedVariant != null &&
                                _committedLayout != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                  if (_supportsAndroidCalibration &&
                      _committedProfile != null &&
                      _committedLayout != null) ...[
                    const SizedBox(width: 8),
                    _buildCalibrationAction(context),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _buildStageHeader(context),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('target-filter-${_stage.name}'),
                decoration: InputDecoration(
                  hintText: switch (_stage) {
                    _PickerStage.profile => '筛选游戏名',
                    _PickerStage.variant => '筛选乐器名',
                    _PickerStage.layout => '筛选键位名',
                  },
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _filterQuery = value.trim();
                  });
                },
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: switch (_stage) {
                      _PickerStage.profile => _ProfileList(
                        key: const ValueKey('profile-list'),
                        profiles: filteredProfiles,
                        selectedProfileId: _profile?.id,
                        onSelected: _handleProfileSelected,
                      ),
                      _PickerStage.variant => _VariantList(
                        key: const ValueKey('variant-list'),
                        variants: filteredVariants,
                        selectedVariantId: _variant?.id,
                        onSelected: _handleVariantSelected,
                      ),
                      _PickerStage.layout => _LayoutList(
                        key: const ValueKey('layout-list'),
                        layouts: filteredLayouts,
                        selectedLayoutId: _layout?.id,
                        onPreview: _profile == null
                            ? null
                            : (layoutId) => _openLayoutPreview(
                                context,
                                profile: _profile!,
                                layoutId: layoutId,
                              ),
                        onSelected: _handleLayoutSelected,
                      ),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageHeader(BuildContext context) {
    final canGoBack = _stage != _PickerStage.profile;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canGoBack)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回上一级',
            onPressed: () {
              _setStage(
                switch (_stage) {
                  _PickerStage.profile => _PickerStage.profile,
                  _PickerStage.variant => _PickerStage.profile,
                  _PickerStage.layout => _PickerStage.variant,
                },
                clearVariant: _stage == _PickerStage.variant,
                clearLayout:
                    _stage == _PickerStage.variant ||
                    _stage == _PickerStage.layout,
              );
            },
          )
        else
          const SizedBox(width: 48),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.topCenter,
              child: _SummaryRow(
                profile: _profile,
                variant: _variant,
                layout: _layout,
                layoutLabel: _layoutLabel(_profile, _layout),
                onTapProfile: () => _setStage(
                  _PickerStage.profile,
                  clearVariant: true,
                  clearLayout: true,
                ),
                onTapVariant: _profile == null
                    ? null
                    : () => _setStage(_PickerStage.variant, clearLayout: true),
                onTapLayout: _profile == null || _variant == null
                    ? null
                    : () => _setStage(_PickerStage.layout),
              ),
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  void _handleProfileSelected(GameProfile profile) {
    setState(() {
      _profile = profile;
      _variant = null;
      _layout = null;
      _filterQuery = '';
      _stage = _PickerStage.variant;
    });
  }

  Widget _buildCalibrationAction(BuildContext context) {
    final icon = _startingCalibration
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.tune_outlined, size: 18);
    final compactStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final onPressed = _startingCalibration || _hasCalibration == null
        ? null
        : _calibrateCurrentTarget;

    if (_hasCalibration == true) {
      return TextButton.icon(
        key: const ValueKey('calibrate-current-target'),
        style: compactStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.outline,
          ),
        ),
        onPressed: onPressed,
        icon: icon,
        label: const Text('重新校准'),
      );
    }
    return FilledButton.tonalIcon(
      key: const ValueKey('calibrate-current-target'),
      style: compactStyle,
      onPressed: onPressed,
      icon: icon,
      label: const Text('校准'),
    );
  }

  Future<void> _loadCalibrationStatus() async {
    final profile = _committedProfile;
    final layout = _committedLayout;
    if (profile == null || layout == null) {
      return;
    }
    try {
      final platform = await ref.read(calibrationPlatformProvider).getState();
      final calibration = ref
          .read(calibrationRepositoryProvider)
          .load(
            CalibrationKey(
              profileId: profile.id,
              layoutId: layout.id,
              deviceId: platform.deviceId,
            ),
          );
      if (mounted) {
        setState(() => _hasCalibration = calibration != null);
      }
    } on Object {
      if (mounted) {
        setState(() => _hasCalibration = false);
      }
    }
  }

  Future<void> _calibrateCurrentTarget() async {
    final profile = _committedProfile;
    final layout = _committedLayout;
    if (profile == null || layout == null) {
      return;
    }
    setState(() => _startingCalibration = true);
    final result = await launchCalibration(
      context: context,
      ref: ref,
      profile: profile,
      layout: layout,
    );
    if (mounted && result?.status == CalibrationSessionStatus.started) {
      Navigator.of(context).pop();
      return;
    }
    if (mounted) {
      setState(() => _startingCalibration = false);
    }
  }

  void _handleVariantSelected(InstrumentVariant variant) {
    setState(() {
      _variant = variant;
      _layout = null;
      _filterQuery = '';
      _stage = _PickerStage.layout;
    });
  }

  void _handleLayoutSelected(String layoutId) {
    final profile = _profile;
    final variant = _variant;
    if (profile == null || variant == null) {
      return;
    }
    final layout = _resolveLayout(
      profile: profile,
      layoutRepo: ref.read(layoutRepositoryProvider),
      preferredLayoutId: layoutId,
    );
    if (layout == null) {
      return;
    }

    ref.read(selectedProfileProvider.notifier).select(profile);
    ref.read(selectedVariantProvider.notifier).select(variant);
    ref.read(selectedLayoutProvider.notifier).select(layout);
    markProfileUsedNow(ref, profile.id);

    setState(() {
      _layout = layout;
    });
    Navigator.of(context).pop();
  }

  void _openLayoutPreview(
    BuildContext context, {
    required GameProfile profile,
    required String layoutId,
  }) {
    context.push(
      LayoutPreviewRoute.location(profileId: profile.id, layoutId: layoutId),
    );
  }

  String _layoutLabel(GameProfile? profile, KeyLayout? layout) {
    if (profile == null || layout == null) {
      return '选择键位';
    }
    return profile.layoutById(layout.id)?.displayName ?? layout.id;
  }

  List<GameProfile> _filterProfiles(
    List<GameProfile> profiles,
    PersistedProfileUsage usage,
  ) {
    final query = _filterQuery.toLowerCase();
    final filtered = profiles.where((profile) {
      if (query.isEmpty) {
        return true;
      }
      return profile.displayName.toLowerCase().contains(query) ||
          profile.id.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aUsed = usage.lastUsedAtByProfileId[a.id] ?? 0;
      final bUsed = usage.lastUsedAtByProfileId[b.id] ?? 0;
      if (aUsed != bUsed) {
        return bUsed.compareTo(aUsed);
      }
      return a.displayName.compareTo(b.displayName);
    });
    return filtered;
  }

  List<InstrumentVariant> _filterVariants() {
    final profile = _profile;
    if (profile == null) {
      return const <InstrumentVariant>[];
    }
    final query = _filterQuery.toLowerCase();
    return profile.variants.where((variant) {
      if (query.isEmpty) {
        return true;
      }
      return variant.displayName.toLowerCase().contains(query) ||
          variant.id.toLowerCase().contains(query);
    }).toList();
  }

  List<LayoutBinding> _filterLayouts() {
    final profile = _profile;
    if (profile == null) {
      return const <LayoutBinding>[];
    }
    final query = _filterQuery.toLowerCase();
    return profile.layouts.where((layout) {
      final displayName = layout.displayName ?? layout.layoutId;
      if (query.isEmpty) {
        return true;
      }
      return displayName.toLowerCase().contains(query) ||
          layout.layoutId.toLowerCase().contains(query);
    }).toList();
  }

  void _setStage(
    _PickerStage stage, {
    bool clearVariant = false,
    bool clearLayout = false,
  }) {
    setState(() {
      _stage = stage;
      if (clearVariant) {
        _variant = null;
      }
      if (clearLayout) {
        _layout = null;
      }
      _filterQuery = '';
    });
  }

  String _targetSummary(
    GameProfile? profile,
    InstrumentVariant? variant,
    KeyLayout? layout, {
    required String emptyText,
  }) {
    if (profile == null || variant == null || layout == null) {
      return emptyText;
    }
    return '${profile.displayName} / ${variant.displayName} / ${_layoutLabel(profile, layout)}';
  }

  KeyLayout? _resolveLayout({
    required GameProfile profile,
    required LayoutRepository layoutRepo,
    String? preferredLayoutId,
  }) {
    final preferredBinding = preferredLayoutId == null
        ? null
        : profile.layoutById(preferredLayoutId);
    final binding =
        preferredBinding ??
        profile.layouts
            .where((item) => item.isDefault)
            .cast<LayoutBinding?>()
            .firstOrNull ??
        (profile.layouts.isNotEmpty ? profile.layouts.first : null);
    if (binding == null) {
      return null;
    }
    try {
      return layoutRepo.load(binding.layoutId);
    } catch (_) {
      return null;
    }
  }
}

bool get _supportsAndroidCalibration =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.profile,
    required this.variant,
    required this.layout,
    required this.layoutLabel,
    required this.onTapProfile,
    required this.onTapVariant,
    required this.onTapLayout,
  });

  final GameProfile? profile;
  final InstrumentVariant? variant;
  final KeyLayout? layout;
  final String layoutLabel;
  final VoidCallback onTapProfile;
  final VoidCallback? onTapVariant;
  final VoidCallback? onTapLayout;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          chipKey: const ValueKey('target-summary-profile'),
          label: profile?.displayName ?? '选择游戏',
          selected: profile != null,
          onTap: onTapProfile,
        ),
        _SummaryChip(
          chipKey: const ValueKey('target-summary-variant'),
          label: variant?.displayName ?? '选择乐器',
          selected: variant != null,
          onTap: onTapVariant,
        ),
        _SummaryChip(
          chipKey: const ValueKey('target-summary-layout'),
          label: layout != null ? layoutLabel : '选择键位',
          selected: layout != null,
          onTap: onTapLayout,
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foregroundColor = !enabled
        ? scheme.outline
        : selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final backgroundColor = !enabled
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;

    return ActionChip(
      key: chipKey,
      avatar: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: foregroundColor,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor,
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: 0.28)
            : Colors.transparent,
      ),
      onPressed: onTap,
    );
  }
}

class _ProfileList extends StatelessWidget {
  const _ProfileList({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelected,
  });

  final List<GameProfile> profiles;
  final String? selectedProfileId;
  final ValueChanged<GameProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        return ListTile(
          leading: Icon(
            profile.id == selectedProfileId
                ? Icons.check_circle
                : Icons.sports_esports_outlined,
          ),
          title: Text(profile.displayName),
          subtitle: Text(
            '${profile.variants.length} 变体 · ${profile.layouts.length} 布局',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelected(profile),
        );
      },
    );
  }
}

class _VariantList extends StatelessWidget {
  const _VariantList({
    super.key,
    required this.variants,
    required this.selectedVariantId,
    required this.onSelected,
  });

  final List<InstrumentVariant> variants;
  final String? selectedVariantId;
  final ValueChanged<InstrumentVariant> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final variant = variants[index];
        final selected = variant.id == selectedVariantId;
        return ListTile(
          leading: Icon(
            selected ? Icons.check_circle : Icons.music_note_outlined,
          ),
          title: Text(variant.displayName),
          subtitle: Text(variant.id),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelected(variant),
        );
      },
    );
  }
}

class _LayoutList extends StatelessWidget {
  const _LayoutList({
    super.key,
    required this.layouts,
    required this.selectedLayoutId,
    required this.onPreview,
    required this.onSelected,
  });

  final List<LayoutBinding> layouts;
  final String? selectedLayoutId;
  final ValueChanged<String>? onPreview;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: layouts.length,
      itemBuilder: (context, index) {
        final binding = layouts[index];
        final selected = binding.layoutId == selectedLayoutId;
        return ListTile(
          leading: Icon(
            selected ? Icons.check_circle : Icons.grid_view_outlined,
          ),
          title: Text(binding.displayName ?? binding.layoutId),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onPreview != null)
                IconButton(
                  key: ValueKey('layout-preview-${binding.layoutId}'),
                  tooltip: '预览键位',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onPreview!(binding.layoutId),
                  icon: const Icon(Icons.visibility_outlined),
                ),
              if (binding.isDefault)
                const _DefaultTag()
              else
                const Icon(Icons.check, color: Colors.transparent),
            ],
          ),
          onTap: () => onSelected(binding.layoutId),
        );
      },
    );
  }
}

class _DefaultTag extends StatelessWidget {
  const _DefaultTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '默认',
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
