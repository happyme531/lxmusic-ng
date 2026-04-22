import 'package:yaml/yaml.dart';

import '../domain/game_profile.dart';
import 'profile_repository.dart';
import 'yaml_asset_bundle.dart';

class YamlGameProfileRepository implements GameProfileRepository {
  YamlGameProfileRepository(this.bundle);

  final YamlAssetBundle bundle;
  Map<String, GameProfile>? _cache;

  @override
  GameProfile load(String id) {
    final cache = _cache ??= _loadAll();
    final profile = cache[id];
    if (profile == null) {
      throw ArgumentError('Unknown profile "$id".');
    }
    return profile;
  }

  @override
  List<GameProfile> list() {
    final cache = _cache ??= _loadAll();
    return cache.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  Map<String, GameProfile> _loadAll() {
    final profilePaths = bundle
        .listFiles('game_profiles')
        .where((path) => path.endsWith('.yaml'))
        .toList();
    if (profilePaths.isEmpty) {
      throw StateError('Profile assets not found: game_profiles/');
    }

    final result = <String, GameProfile>{};
    for (final path in profilePaths) {
      final text = bundle.readText(path);
      if (text == null) {
        continue;
      }
      final yaml = loadYaml(text) as YamlMap;
      final profile = GameProfile(
        id: yaml['id'] as String,
        displayName: yaml['displayName'] as String,
        packageNameHints: (yaml['packageNameHints'] as YamlList? ?? YamlList())
            .cast<String>()
            .toList(),
        defaultLayoutId: yaml['defaultLayoutId'] as String?,
        sameKeyMinIntervalMs: yaml['sameKeyMinIntervalMs'] as int? ?? 20,
        featureFlags:
            ((yaml['featureFlags'] as YamlList? ?? YamlList()).cast<String>())
                .toSet(),
        layouts: (yaml['layouts'] as YamlList? ?? YamlList())
            .cast<YamlMap>()
            .map(
              (item) => LayoutBinding(
                layoutId: item['layoutId'] as String,
                displayName: item['displayName'] as String?,
                isDefault: item['isDefault'] as bool? ?? false,
              ),
            )
            .toList(),
        variants: (yaml['variants'] as YamlList? ?? YamlList())
            .cast<YamlMap>()
            .map(
              (item) => InstrumentVariant(
                id: item['id'] as String,
                displayName: item['displayName'] as String,
                noteDurationMode: NoteDurationMode.values.byName(
                  item['noteDurationMode'] as String? ?? 'none',
                ),
                aliases: (item['aliases'] as YamlList? ?? YamlList())
                    .cast<String>()
                    .toList(),
                availablePitchRange: item['availablePitchRange'] == null
                    ? null
                    : IntRange(
                        (item['availablePitchRange'] as YamlList)[0] as int,
                        (item['availablePitchRange'] as YamlList)[1] as int,
                      ),
                replacePitchMap: Map<int, int>.fromEntries(
                  (item['replacePitchMap'] as YamlMap? ?? YamlMap()).entries
                      .map(
                        (entry) => MapEntry(
                          int.parse(entry.key as String),
                          entry.value as int,
                        ),
                      ),
                ),
                sameKeyMinIntervalOverrideMs:
                    item['sameKeyMinIntervalOverrideMs'] as int?,
              ),
            )
            .toList(),
      );
      result[profile.id] = profile;
    }
    return result;
  }
}
