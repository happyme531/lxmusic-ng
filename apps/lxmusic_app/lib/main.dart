import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/service_locator.dart';
import 'core/yaml_asset_loader.dart';
import 'features/game_player/overlay/player_overlay_app.dart';
import 'features/game_player/overlay/platform/player_overlay_bridge.dart';
import 'features/game_player/overlay/platform/player_overlay_calibration_platform.dart';
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

class LxMusicApp extends StatelessWidget {
  const LxMusicApp({super.key});

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
