import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_locator.dart';
import '../../../core/platform/file_store.dart';
import '../../library/models/music_file.dart';
import '../models/song_config.dart';

const _configStoragePrefix = 'song_config_';

final songConfigStoreProvider = Provider<SongConfigStore>((ref) {
  return const SongConfigStore();
});

final songConfigServiceProvider = Provider<SongConfigService>((ref) {
  return SongConfigService(
    parserRegistry: ref.watch(parserRegistryProvider),
    configStore: ref.watch(songConfigStoreProvider),
    fileStore: ref.watch(fileStoreProvider),
  );
});

class SongConfigKey {
  const SongConfigKey({
    required this.fileName,
    required this.profileId,
    required this.variantId,
    required this.layoutId,
  });

  factory SongConfigKey.fromConfig(SongConfig config) {
    return SongConfigKey(
      fileName: config.fileName,
      profileId: config.profileId,
      variantId: config.variantId,
      layoutId: config.layoutId,
    );
  }

  final String fileName;
  final String profileId;
  final String variantId;
  final String layoutId;
}

class SongConfigStore {
  const SongConfigStore();

  Future<SongConfig?> load(SongConfigKey key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(key));
    if (raw != null) {
      return _decode(raw);
    }

    final legacyRaw = prefs.getString(_legacyStorageKey(key.fileName));
    final legacy = legacyRaw == null ? null : _decode(legacyRaw);
    if (legacy == null) {
      return null;
    }
    if (legacy.profileId != key.profileId ||
        legacy.variantId != key.variantId ||
        legacy.layoutId != key.layoutId) {
      return null;
    }
    return legacy;
  }

  Future<void> save(SongConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(SongConfigKey.fromConfig(config)),
      jsonEncode(config.toJson()),
    );
  }

  Future<void> clear(SongConfigKey key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(key));
  }

  String storageKey(SongConfigKey key) => _storageKey(key);

  String _storageKey(SongConfigKey key) {
    final suffix = <String>[
      key.fileName,
      key.profileId,
      key.variantId,
      key.layoutId,
    ].map(Uri.encodeComponent).join('__');
    return '$_configStoragePrefix$suffix';
  }

  String _legacyStorageKey(String fileName) {
    return '$_configStoragePrefix$fileName';
  }

  SongConfig? _decode(String raw) {
    try {
      return SongConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }
}

class SongConfigService {
  const SongConfigService({
    required this.parserRegistry,
    required this.configStore,
    required this.fileStore,
  });

  final ParserRegistry parserRegistry;
  final SongConfigStore configStore;
  final PlatformFileStore fileStore;

  Future<Score> parseFile(MusicFile file) async {
    final bytes = await fileStore.readBytes(file.path);
    return parserRegistry.parse(bytes: bytes, formatId: file.formatId);
  }

  Future<ScoreAnalysis> analyzeForTarget({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    int? fixedPitchOffset,
  }) async {
    final score = await parseFile(file);
    return analyzeScoreForTarget(
      score,
      target: AnalysisTarget(
        profile: profile,
        variant: variant,
        layout: layout,
      ),
      fixedPitchOffset: fixedPitchOffset,
    );
  }

  Future<SongConfig?> loadForTarget({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
  }) {
    return configStore.load(
      SongConfigKey(
        fileName: file.fileName,
        profileId: profile.id,
        variantId: variant.id,
        layoutId: layout.id,
      ),
    );
  }

  Future<SongConfig> ensureForTarget({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
  }) async {
    final existing = await loadForTarget(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
    );
    if (existing != null) {
      return existing;
    }

    final analysis = await analyzeForTarget(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
    );
    final config = createRecommendedSongConfig(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
      analysis: analysis,
    );
    await save(config);
    return config;
  }

  Future<void> save(SongConfig config) {
    return configStore.save(config);
  }

  Future<void> clearForTarget({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
  }) {
    return configStore.clear(
      SongConfigKey(
        fileName: file.fileName,
        profileId: profile.id,
        variantId: variant.id,
        layoutId: layout.id,
      ),
    );
  }
}

SongConfig createRecommendedSongConfig({
  required MusicFile file,
  required GameProfile profile,
  required InstrumentVariant variant,
  required KeyLayout layout,
  required ScoreAnalysis analysis,
}) {
  return SongConfig(
    fileName: file.fileName,
    profileId: profile.id,
    variantId: variant.id,
    layoutId: layout.id,
    steps: analysis.buildRecommendedPipeline().steps.toList(),
    recommendedPitchOffset: analysis.pitchOffset.bestOffset,
  );
}
