import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/platform/file_store.dart';
import 'core/service_locator.dart';
import 'core/yaml_asset_loader.dart';
import 'features/game_player/overlay/player_overlay_app.dart';
import 'features/game_player/overlay/platform/player_overlay_bridge.dart';
import 'features/game_player/overlay/platform/player_overlay_calibration_platform.dart';
import 'features/library/library_screen.dart';
import 'features/library/platform/external_file_open_platform.dart';
import 'features/workbench/providers/workbench_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bundle = await loadBundledYamlAssets();
  final prefs = await SharedPreferences.getInstance();
  final persistedTarget = TargetSelectionPersistence.fromPrefs(prefs);
  final persistedProfileUsage =
      TargetSelectionPersistence.profileUsageFromPrefs(prefs);

  runApp(
    ProviderScope(
      overrides: [
        assetBundleProvider.overrideWithValue(bundle),
        sharedPreferencesProvider.overrideWithValue(prefs),
        persistedTargetSelectionProvider.overrideWithValue(persistedTarget),
        initialPersistedProfileUsageProvider.overrideWithValue(
          persistedProfileUsage,
        ),
      ],
      child: const LxMusicApp(),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> playerOverlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = MethodChannelPlayerOverlayBridge();
  final bundle = await loadBundledYamlAssets();
  final prefs = await SharedPreferences.getInstance();
  final persistedTarget = TargetSelectionPersistence.fromPrefs(prefs);
  final persistedProfileUsage =
      TargetSelectionPersistence.profileUsageFromPrefs(prefs);

  runApp(
    ProviderScope(
      overrides: [
        assetBundleProvider.overrideWithValue(bundle),
        sharedPreferencesProvider.overrideWithValue(prefs),
        persistedTargetSelectionProvider.overrideWithValue(persistedTarget),
        initialPersistedProfileUsageProvider.overrideWithValue(
          persistedProfileUsage,
        ),
        calibrationPlatformProvider.overrideWithValue(
          PlayerOverlayCalibrationPlatform(bridge),
        ),
      ],
      child: PlayerOverlayApp(bridge: bridge),
    ),
  );
}

class LxMusicApp extends ConsumerStatefulWidget {
  const LxMusicApp({super.key});

  @override
  ConsumerState<LxMusicApp> createState() => _LxMusicAppState();
}

class _LxMusicAppState extends ConsumerState<LxMusicApp> {
  ExternalFileOpenPlatform? _externalFileOpenPlatform;
  bool _drainingExternalFiles = false;
  bool _drainRequested = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final platform = ref.read(externalFileOpenPlatformProvider);
      _externalFileOpenPlatform = platform;
      platform.setFilesAvailableHandler(() async => _requestExternalDrain());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestExternalDrain();
      });
    }
  }

  @override
  void dispose() {
    _externalFileOpenPlatform?.setFilesAvailableHandler(null);
    super.dispose();
  }

  void _requestExternalDrain() {
    if (!mounted) return;
    _drainRequested = true;
    if (!_drainingExternalFiles) {
      unawaited(_drainExternalFiles());
    }
  }

  Future<void> _drainExternalFiles() async {
    final platform = _externalFileOpenPlatform;
    if (platform == null || _drainingExternalFiles) return;
    _drainingExternalFiles = true;
    try {
      do {
        _drainRequested = false;
        late final List<ExternalOpenedFile> openedFiles;
        try {
          openedFiles = await platform.consumePendingFiles();
        } on MissingPluginException {
          return;
        } on PlatformException {
          return;
        }
        if (!mounted || openedFiles.isEmpty) continue;
        await _importExternalFiles(platform, openedFiles);
      } while (mounted && _drainRequested);
    } finally {
      _drainingExternalFiles = false;
      if (mounted && _drainRequested) {
        _requestExternalDrain();
      }
    }
  }

  Future<void> _importExternalFiles(
    ExternalFileOpenPlatform platform,
    List<ExternalOpenedFile> openedFiles,
  ) async {
    router.go('/library');
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final importContext = rootNavigatorKey.currentContext;
    if (importContext == null || !importContext.mounted) return;

    final failures = openedFiles
        .where((file) => !file.isReadable)
        .toList(growable: false);
    if (failures.isNotEmpty) {
      final message = failures
          .map((file) => '${file.fileName}：${file.errorMessage ?? '无法读取'}')
          .join('\n');
      ScaffoldMessenger.maybeOf(
        importContext,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }

    final readable = openedFiles
        .where((file) => file.isReadable)
        .toList(growable: false);
    if (readable.isEmpty) return;
    final paths = readable.map((file) => file.path!).toList(growable: false);
    try {
      await runMusicImportFlow(
        importContext,
        ref,
        readable
            .map(
              (file) => PickedFileData(
                fileName: file.fileName,
                sourcePath: file.path,
              ),
            )
            .toList(growable: false),
      );
    } finally {
      try {
        await platform.releaseCachedFiles(paths);
      } on MissingPluginException {
        // The native activity may have been torn down while importing.
      } on PlatformException {
        // Stale cache entries are cleaned by Android on the next import.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LxMusic-NG',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
