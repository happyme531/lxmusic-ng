import 'dart:io';

import 'package:lxmusic_core/lxmusic_core.dart';

YamlAssetBundle loadCoreTestYamlAssetBundle() {
  final rootDirectory = Directory('../../assets');
  final assets = <String, String>{};
  for (final entity in rootDirectory.listSync(recursive: true).whereType<File>()) {
    if (!entity.path.endsWith('.yaml')) {
      continue;
    }
    final relativePath = entity.path.substring(rootDirectory.path.length + 1);
    assets[relativePath] = entity.readAsStringSync();
  }
  return YamlAssetBundle(assets);
}
