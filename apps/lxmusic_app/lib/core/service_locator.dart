import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/calibration/data/app_calibration_repository.dart';
import '../features/calibration/platform/calibration_platform.dart';
import '../features/library/services/archive_import_service.dart';
import '../features/library/services/archive_import_service_factory.dart';
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

final archiveImportServiceProvider = Provider<ArchiveImportService>((ref) {
  return createArchiveImportService();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final calibrationPlatformProvider = Provider<CalibrationPlatform>((ref) {
  return const MethodChannelCalibrationPlatform();
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

final bundledCalibrationRepositoryProvider = Provider<CalibrationRepository>((
  ref,
) {
  return YamlCalibrationRepository(ref.watch(assetBundleProvider));
});

final userCalibrationRepositoryProvider =
    Provider<SharedPreferencesCalibrationRepository>((ref) {
      return SharedPreferencesCalibrationRepository(
        ref.watch(sharedPreferencesProvider),
      );
    });

final compositeCalibrationRepositoryProvider =
    Provider<CompositeCalibrationRepository>((ref) {
      return CompositeCalibrationRepository(
        userRepository: ref.watch(userCalibrationRepositoryProvider),
        bundledRepository: ref.watch(bundledCalibrationRepositoryProvider),
      );
    });

final calibrationRepositoryProvider = Provider<MutableCalibrationRepository>((
  ref,
) {
  return ref.watch(compositeCalibrationRepositoryProvider);
});

// ---------------------------------------------------------------------------
// Parser registry
// ---------------------------------------------------------------------------

final parserRegistryProvider = Provider<ParserRegistry>((ref) {
  return createDefaultParserRegistry();
});

final scoreFormatDetectorProvider = Provider<ScoreFormatDetector>((ref) {
  return const ScoreFormatDetector();
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
