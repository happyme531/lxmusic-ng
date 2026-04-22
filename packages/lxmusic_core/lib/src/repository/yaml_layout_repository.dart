import 'package:yaml/yaml.dart';

import '../domain/game_profile.dart';
import '../transform/layout_generator.dart';
import 'layout_repository.dart';
import 'yaml_asset_bundle.dart';

class YamlLayoutRepository implements LayoutRepository {
  YamlLayoutRepository(this.bundle);

  final YamlAssetBundle bundle;
  final LayoutGenerator _generator = const LayoutGenerator();
  Map<String, KeyLayout>? _cache;

  @override
  KeyLayout load(String id) {
    final cache = _cache ??= _loadAll();
    final layout = cache[id];
    if (layout == null) {
      throw ArgumentError('Unknown layout "$id".');
    }
    return layout;
  }

  @override
  List<KeyLayout> list() {
    final cache = _cache ??= _loadAll();
    return cache.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  Map<String, KeyLayout> _loadAll() {
    final layoutPaths = bundle
        .listFiles('layouts')
        .where((path) => path.endsWith('.yaml'))
        .toList();
    if (layoutPaths.isEmpty) {
      throw StateError('Layout assets not found: layouts/');
    }

    final result = <String, KeyLayout>{};
    for (final path in layoutPaths) {
      final text = bundle.readText(path);
      if (text == null) {
        continue;
      }
      final yaml = loadYaml(text) as YamlMap;
      final algorithm = LayoutAlgorithm.values.byName(
        yaml['algorithm'] as String? ?? 'explicit',
      );
      final metadata = Map<String, Object?>.from(
        (yaml['metadata'] as YamlMap?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, Object?>{},
      );
      if (algorithm == LayoutAlgorithm.procedural) {
        result[yaml['id'] as String] = _generator.generate(
          id: yaml['id'] as String,
          params: _yamlMapToObjectMap(yaml['params'] as YamlMap? ?? YamlMap()),
          metadata: metadata,
        );
        continue;
      }
      final keys = (yaml['keys'] as YamlList? ?? YamlList())
          .cast<YamlMap>()
          .map(
            (item) => KeyDefinition(
              id: item['id'] as String,
              pitch: item['pitch'] as int?,
              normX: (item['normX'] as num).toDouble(),
              normY: (item['normY'] as num).toDouble(),
            ),
          )
          .toList();
      result[yaml['id'] as String] = KeyLayout(
        id: yaml['id'] as String,
        algorithm: algorithm,
        keys: keys,
        pitchToKeyId: <int, String>{
          for (final key in keys)
            if (key.pitch != null) key.pitch!: key.id,
        },
        metadata: metadata,
      );
    }
    return result;
  }

  Map<String, Object?> _yamlMapToObjectMap(YamlMap yaml) {
    final result = <String, Object?>{};
    for (final entry in yaml.entries) {
      result[entry.key.toString()] = _convertYamlValue(entry.value);
    }
    return result;
  }

  Object? _convertYamlValue(Object? value) {
    if (value is YamlMap) {
      return _yamlMapToObjectMap(value);
    }
    if (value is YamlList) {
      return value.map(_convertYamlValue).toList();
    }
    return value;
  }
}
