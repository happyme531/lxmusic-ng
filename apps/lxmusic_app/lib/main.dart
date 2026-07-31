import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/service_locator.dart';
import 'core/yaml_asset_loader.dart';
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
