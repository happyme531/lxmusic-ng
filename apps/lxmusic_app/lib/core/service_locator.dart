import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import 'platform/file_store.dart';
import 'platform/file_store_factory.dart';

// ---------------------------------------------------------------------------
// Asset bundle — points to the monorepo assets/ directory.
// For a release build this should be switched to bundled Flutter assets.
// ---------------------------------------------------------------------------

final assetBundleProvider = Provider<YamlAssetBundle>((ref) {
  // Overridden at app startup via ProviderScope.overrides.
  throw UnimplementedError('assetBundleProvider must be overridden');
});

final fileStoreProvider = Provider<PlatformFileStore>((ref) {
  return createAppFileStore();
});

// ---------------------------------------------------------------------------
// Core repositories
// ---------------------------------------------------------------------------

final profileRepositoryProvider = Provider<GameProfileRepository>((ref) {
  return YamlGameProfileRepository(ref.watch(assetBundleProvider));
});

final layoutRepositoryProvider = Provider<LayoutRepository>((ref) {
  return YamlLayoutRepository(ref.watch(assetBundleProvider));
});

final calibrationRepositoryProvider = Provider<CalibrationRepository>((ref) {
  return YamlCalibrationRepository(ref.watch(assetBundleProvider));
});

// ---------------------------------------------------------------------------
// Parser registry
// ---------------------------------------------------------------------------

final parserRegistryProvider = Provider<ParserRegistry>((ref) {
  return ParserRegistry(<String, ScoreParser>{
    'domiso': DoMiSoScoreParser(),
    'json-score': _JsonScoreParser(),
    'midi': const MidiScoreParser(),
    'skystudio-json': const SkyStudioJsonScoreParser(),
    'tonejs-json': ToneJsJsonScoreParser(),
  });
});

// ---------------------------------------------------------------------------
// Convenience list providers
// ---------------------------------------------------------------------------

final gameProfilesProvider = Provider<List<GameProfile>>((ref) {
  return ref.watch(profileRepositoryProvider).list();
});

final layoutsProvider = Provider<List<KeyLayout>>((ref) {
  return ref.watch(layoutRepositoryProvider).list();
});

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _JsonScoreParser implements ScoreParser {
  @override
  String get formatId => 'json-score';

  @override
  Score parse(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return Score.fromJson(decoded);
  }
}
