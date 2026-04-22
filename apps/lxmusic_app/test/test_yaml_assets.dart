import 'dart:io';

import 'package:lxmusic_core/lxmusic_core.dart';

YamlAssetBundle loadTestYamlAssetBundle() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final candidate = Directory('${dir.path}/assets');
    if (candidate.existsSync()) {
      return _bundleFromDirectory(candidate);
    }
    dir = dir.parent;
  }
  throw StateError('Unable to locate assets directory from ${Directory.current.path}');
}

YamlAssetBundle _bundleFromDirectory(Directory rootDirectory) {
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
