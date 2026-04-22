import 'package:flutter/services.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

const _assetPrefix = 'packages/lxmusic_assets/assets/';

Future<YamlAssetBundle> loadBundledYamlAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = <String, String>{};

  for (final assetPath in manifest.listAssets()) {
    if (!assetPath.startsWith(_assetPrefix) || !assetPath.endsWith('.yaml')) {
      continue;
    }
    final logicalPath = assetPath.substring(_assetPrefix.length);
    assets[logicalPath] = await rootBundle.loadString(assetPath);
  }

  return YamlAssetBundle(assets);
}
