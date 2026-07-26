import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

import 'test_yaml_assets.dart';

void main() {
  final bundle = loadCoreTestYamlAssetBundle();
  final profileRepository = YamlGameProfileRepository(bundle);
  final layoutRepository = YamlLayoutRepository(bundle);

  for (final profileId in <String>['legacy_31', 'legacy_32']) {
    test('$profileId preserves the legacy unlimited same-key interval', () {
      final profile = profileRepository.load(profileId);
      final variant = profile.variants.first;
      final layout = layoutRepository.load(profile.defaultLayoutId!);

      expect(profile.sameKeyMinIntervalMs, 0);

      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Main',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0, durationMs: 10),
              NoteEvent(pitch: 60, startMs: 1, durationMs: 10),
            ],
          ),
        ],
      );
      final plan = const PerformancePlanner().plan(
        score,
        PlanningContext(profile: profile, layout: layout, variant: variant),
      );

      expect(plan.actions.map((action) => action.atMs), <int>[0, 1]);
      expect(
        plan.warnings.where((warning) => warning.code == 'same_key_throttled'),
        isEmpty,
      );
    });
  }
}
