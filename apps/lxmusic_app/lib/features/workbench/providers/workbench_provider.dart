import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_locator.dart';
import '../../library/models/music_file.dart';
import '../models/song_config.dart';
import '../services/song_config_service.dart';

// ---------------------------------------------------------------------------
// Selected file
// ---------------------------------------------------------------------------

final selectedFileProvider = NotifierProvider<SelectedFileNotifier, MusicFile?>(
  SelectedFileNotifier.new,
);

class SelectedFileNotifier extends Notifier<MusicFile?> {
  @override
  MusicFile? build() => null;

  void select(MusicFile file) => state = file;
  void clear() => state = null;
}

// ---------------------------------------------------------------------------
// Target selection
// ---------------------------------------------------------------------------

class PersistedTargetSelection {
  const PersistedTargetSelection({
    this.profileId,
    this.variantId,
    this.layoutId,
  });

  final String? profileId;
  final String? variantId;
  final String? layoutId;
}

class PersistedProfileUsage {
  const PersistedProfileUsage(this.lastUsedAtByProfileId);

  final Map<String, int> lastUsedAtByProfileId;
}

final persistedTargetSelectionProvider = Provider<PersistedTargetSelection>((
  ref,
) {
  return const PersistedTargetSelection();
});

final initialPersistedProfileUsageProvider = Provider<PersistedProfileUsage>((
  ref,
) {
  return const PersistedProfileUsage(<String, int>{});
});

final persistedProfileUsageProvider =
    NotifierProvider<PersistedProfileUsageNotifier, PersistedProfileUsage>(
      PersistedProfileUsageNotifier.new,
    );

final targetSelectionPersistenceProvider = Provider<TargetSelectionPersistence>(
  (ref) {
    return const TargetSelectionPersistence();
  },
);

class PersistedProfileUsageNotifier extends Notifier<PersistedProfileUsage> {
  @override
  PersistedProfileUsage build() {
    return ref.watch(initialPersistedProfileUsageProvider);
  }

  void markUsed(String profileId, int timestamp) {
    state = PersistedProfileUsage(<String, int>{
      ...state.lastUsedAtByProfileId,
      profileId: timestamp,
    });
  }
}

final selectedProfileProvider =
    NotifierProvider<SelectedProfileNotifier, GameProfile?>(
      SelectedProfileNotifier.new,
    );

class SelectedProfileNotifier extends Notifier<GameProfile?> {
  @override
  GameProfile? build() {
    final persisted = ref.watch(persistedTargetSelectionProvider);
    if (persisted.profileId == null) {
      return null;
    }
    try {
      return ref.read(profileRepositoryProvider).load(persisted.profileId!);
    } catch (_) {
      return null;
    }
  }

  void select(GameProfile profile) {
    state = profile;
    _saveProfileId(ref, profile.id);
  }

  void clear() {
    state = null;
    ref.read(selectedVariantProvider.notifier).clear();
    ref.read(selectedLayoutProvider.notifier).clear();
    _saveTargetSelection(ref, profileId: null, variantId: null, layoutId: null);
  }
}

final selectedVariantProvider =
    NotifierProvider<SelectedVariantNotifier, InstrumentVariant?>(
      SelectedVariantNotifier.new,
    );

class SelectedVariantNotifier extends Notifier<InstrumentVariant?> {
  @override
  InstrumentVariant? build() {
    final profile = ref.watch(selectedProfileProvider);
    final persisted = ref.watch(persistedTargetSelectionProvider);
    if (profile == null || persisted.variantId == null) {
      return null;
    }
    return profile.variantById(persisted.variantId!);
  }

  void select(InstrumentVariant variant) {
    state = variant;
    _saveVariantId(ref, variant.id);
  }

  void clear() {
    state = null;
    _saveVariantId(ref, null);
  }
}

final selectedLayoutProvider =
    NotifierProvider<SelectedLayoutNotifier, KeyLayout?>(
      SelectedLayoutNotifier.new,
    );

class SelectedLayoutNotifier extends Notifier<KeyLayout?> {
  @override
  KeyLayout? build() {
    final persisted = ref.watch(persistedTargetSelectionProvider);
    if (persisted.layoutId == null) {
      return null;
    }
    try {
      return ref.read(layoutRepositoryProvider).load(persisted.layoutId!);
    } catch (_) {
      return null;
    }
  }

  void select(KeyLayout layout) {
    state = layout;
    _saveLayoutId(ref, layout.id);
  }

  void clear() {
    state = null;
    _saveLayoutId(ref, null);
  }
}

// ---------------------------------------------------------------------------
// Auto-analysis: runs when file + profile + variant + layout are all set
// ---------------------------------------------------------------------------

final analysisProvider = FutureProvider<ScoreAnalysis?>((ref) async {
  final file = ref.watch(selectedFileProvider);
  final profile = ref.watch(selectedProfileProvider);
  final variant = ref.watch(selectedVariantProvider);
  final layout = ref.watch(selectedLayoutProvider);

  if (file == null || profile == null || variant == null || layout == null) {
    return null;
  }

  return ref
      .read(songConfigServiceProvider)
      .analyzeForTarget(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
      );
});

final currentPitchAnalysisProvider = FutureProvider<ScoreAnalysis?>((
  ref,
) async {
  final file = ref.watch(selectedFileProvider);
  final profile = ref.watch(selectedProfileProvider);
  final variant = ref.watch(selectedVariantProvider);
  final layout = ref.watch(selectedLayoutProvider);
  final config = await ref.watch(songConfigProvider.future);

  if (file == null ||
      profile == null ||
      variant == null ||
      layout == null ||
      config == null) {
    return null;
  }

  return ref
      .read(songConfigServiceProvider)
      .analyzeForTarget(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
        fixedPitchOffset: config.pitchOffset,
      );
});

// ---------------------------------------------------------------------------
// Song config: auto-generated from analysis, then user-editable
// ---------------------------------------------------------------------------

final songConfigProvider =
    AsyncNotifierProvider<SongConfigNotifier, SongConfig?>(
      SongConfigNotifier.new,
    );

final configReportProvider = FutureProvider<ConfigReportSummary?>((ref) async {
  final file = ref.watch(selectedFileProvider);
  final config = await ref.watch(songConfigProvider.future);
  if (file == null || config == null) {
    return null;
  }

  final service = ref.watch(songConfigServiceProvider);
  final rawScore = await service.parseFile(file);
  final transformed = TransformPipeline(config.steps).run(rawScore);
  return ConfigReportSummary.fromReport(transformed.report);
});

class ConfigReportSummary {
  const ConfigReportSummary({
    required this.inputNoteCount,
    required this.outputNoteCount,
    required this.pipelineNotesAdded,
    required this.pipelineNotesRemoved,
    required this.outOfRangeDiscarded,
    required this.semitoneRounded,
    required this.tooDenseDiscarded,
    required this.chordNotesDiscarded,
  });

  final int inputNoteCount;
  final int outputNoteCount;
  final int pipelineNotesAdded;
  final int pipelineNotesRemoved;
  final int outOfRangeDiscarded;
  final int semitoneRounded;
  final int tooDenseDiscarded;
  final int chordNotesDiscarded;

  factory ConfigReportSummary.fromReport(TransformReport report) {
    final summary = report.noteSummary;
    final legalize = _firstStat(report, 'LegalizeTargetNoteRangePass');
    final mergeNearby = _firstStat(report, 'MergeNearbyNotesPass');
    final singleKey = _firstStat(report, 'SingleKeyFrequencyLimitPass');
    final chord = _firstStat(report, 'ChordNoteCountLimitPass');
    return ConfigReportSummary(
      inputNoteCount: summary?.inputNoteCount ?? 0,
      outputNoteCount: summary?.outputNoteCount ?? 0,
      pipelineNotesAdded: summary?.pipelineNotesAdded ?? 0,
      pipelineNotesRemoved: summary?.pipelineNotesRemoved ?? 0,
      outOfRangeDiscarded:
          _intValue(legalize, 'underFlowedNoteCount') +
          _intValue(legalize, 'overFlowedNoteCount') +
          _intValue(legalize, 'middleFailedNoteCount'),
      semitoneRounded: _intValue(legalize, 'roundedNoteCount'),
      tooDenseDiscarded:
          _intValue(mergeNearby, 'droppedSameNoteCount') +
          _intValue(singleKey, 'droppedNoteCount'),
      chordNotesDiscarded:
          _intValue(chord, 'droppedNoteCount') +
          _intValue(chord, 'discardedNoteCount'),
    );
  }

  static PassStat? _firstStat(TransformReport report, String name) {
    for (final stat in report.stats) {
      if (stat.name == name) {
        return stat;
      }
    }
    return null;
  }

  static int _intValue(PassStat? stat, String key) {
    return (stat?.values[key] as int?) ?? 0;
  }
}

class SongConfigNotifier extends AsyncNotifier<SongConfig?> {
  @override
  Future<SongConfig?> build() async {
    final file = ref.watch(selectedFileProvider);
    final profile = ref.watch(selectedProfileProvider);
    final variant = ref.watch(selectedVariantProvider);
    final layout = ref.watch(selectedLayoutProvider);

    if (file == null || profile == null || variant == null || layout == null) {
      return null;
    }

    return ref
        .read(songConfigServiceProvider)
        .ensureForTarget(
          file: file,
          profile: profile,
          variant: variant,
          layout: layout,
        );
  }

  /// Mutate config and persist.
  Future<void> mutate(void Function(SongConfig config) fn) async {
    final current = state.value;
    if (current == null) return;
    fn(current);
    await ref.read(songConfigServiceProvider).save(current);
    state = AsyncData(current);
  }

  /// Re-run analysis and replace the current config with the recommended one.
  Future<void> regenerateFromAnalysis() async {
    final file = ref.read(selectedFileProvider);
    final analysis = await ref.read(analysisProvider.future);
    if (file == null || analysis == null) return;

    final profile = ref.read(selectedProfileProvider)!;
    final variant = ref.read(selectedVariantProvider)!;
    final layout = ref.read(selectedLayoutProvider)!;

    final config = createRecommendedSongConfig(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
      analysis: analysis,
    );

    await ref.read(songConfigServiceProvider).save(config);
    state = AsyncData(config);
  }

  /// Clear persisted config for current file.
  Future<void> clearConfig() async {
    final file = ref.read(selectedFileProvider);
    final profile = ref.read(selectedProfileProvider);
    final variant = ref.read(selectedVariantProvider);
    final layout = ref.read(selectedLayoutProvider);
    if (file == null || profile == null || variant == null || layout == null) {
      return;
    }
    await ref
        .read(songConfigServiceProvider)
        .clearForTarget(
          file: file,
          profile: profile,
          variant: variant,
          layout: layout,
        );
    // Trigger rebuild
    ref.invalidateSelf();
  }
}

class TargetSelectionPersistence {
  const TargetSelectionPersistence();

  static const _profileKey = 'last_profile_id';
  static const _variantKey = 'last_variant_id';
  static const _layoutKey = 'last_layout_id';
  static const _profileUsageKey = 'profile_last_used_at';

  Future<void> save({
    required String? profileId,
    required String? variantId,
    required String? layoutId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _setString(prefs, _profileKey, profileId);
    await _setString(prefs, _variantKey, variantId);
    await _setString(prefs, _layoutKey, layoutId);
  }

  Future<void> saveProfileId(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await _setString(prefs, _profileKey, profileId);
  }

  Future<void> saveVariantId(String? variantId) async {
    final prefs = await SharedPreferences.getInstance();
    await _setString(prefs, _variantKey, variantId);
  }

  Future<void> saveLayoutId(String? layoutId) async {
    final prefs = await SharedPreferences.getInstance();
    await _setString(prefs, _layoutKey, layoutId);
  }

  Future<int> markProfileUsedNow(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final usage = _readProfileUsageMap(prefs);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    usage[profileId] = timestamp;
    await prefs.setString(_profileUsageKey, _encodeProfileUsageMap(usage));
    return timestamp;
  }

  static PersistedTargetSelection fromPrefs(SharedPreferences prefs) {
    return PersistedTargetSelection(
      profileId: prefs.getString(_profileKey),
      variantId: prefs.getString(_variantKey),
      layoutId: prefs.getString(_layoutKey),
    );
  }

  static PersistedProfileUsage profileUsageFromPrefs(SharedPreferences prefs) {
    return PersistedProfileUsage(_readProfileUsageMap(prefs));
  }

  Future<void> _setString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static Map<String, int> _readProfileUsageMap(SharedPreferences prefs) {
    final raw = prefs.getString(_profileUsageKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }
    final result = <String, int>{};
    for (final entry in raw.split(';')) {
      if (entry.isEmpty) {
        continue;
      }
      final sep = entry.indexOf('=');
      if (sep <= 0 || sep >= entry.length - 1) {
        continue;
      }
      final key = Uri.decodeComponent(entry.substring(0, sep));
      final value = int.tryParse(entry.substring(sep + 1));
      if (value != null) {
        result[key] = value;
      }
    }
    return result;
  }

  static String _encodeProfileUsageMap(Map<String, int> usage) {
    return usage.entries
        .map((entry) => '${Uri.encodeComponent(entry.key)}=${entry.value}')
        .join(';');
  }
}

void _saveTargetSelection(
  Ref ref, {
  required String? profileId,
  required String? variantId,
  required String? layoutId,
}) {
  unawaited(
    ref
        .read(targetSelectionPersistenceProvider)
        .save(profileId: profileId, variantId: variantId, layoutId: layoutId),
  );
}

void _saveProfileId(Ref ref, String? profileId) {
  unawaited(
    ref.read(targetSelectionPersistenceProvider).saveProfileId(profileId),
  );
}

void _saveVariantId(Ref ref, String? variantId) {
  unawaited(
    ref.read(targetSelectionPersistenceProvider).saveVariantId(variantId),
  );
}

void _saveLayoutId(Ref ref, String? layoutId) {
  unawaited(
    ref.read(targetSelectionPersistenceProvider).saveLayoutId(layoutId),
  );
}

void markProfileUsedNow(WidgetRef ref, String profileId) {
  unawaited(() async {
    final timestamp = await ref
        .read(targetSelectionPersistenceProvider)
        .markProfileUsedNow(profileId);
    ref
        .read(persistedProfileUsageProvider.notifier)
        .markUsed(profileId, timestamp);
  }());
}
