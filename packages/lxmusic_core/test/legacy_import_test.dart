import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

import 'test_yaml_assets.dart';

void main() {
  final bundle = loadCoreTestYamlAssetBundle();

  test('loads imported genshin profile', () {
    final profiles = YamlGameProfileRepository(bundle);
    final profile = profiles.load('genshin');

    expect(profile.displayName, '原神');
    expect(profile.layouts.isNotEmpty, isTrue);
    expect(profile.variants.isNotEmpty, isTrue);
    expect(profile.variantById('horn')?.displayName, '晚风圆号');
    expect(profile.variantById('old_lyre')?.displayName, '老旧的诗琴');
  });

  test('resolves old lyre pitches to their effective physical keys', () {
    final profiles = YamlGameProfileRepository(bundle);
    final layouts = YamlLayoutRepository(bundle);
    final profile = profiles.load('genshin');
    final oldLyre = profile.variantById('old_lyre')!;
    final threeRowLayout = layouts.load('generic_3x7');
    final defaultKeys = profile
        .variantById('default')!
        .playablePitchToKeyId(threeRowLayout);

    expect(defaultKeys[64], 'E4');
    expect(defaultKeys[83], 'B5');
    expect(defaultKeys, isNot(contains(63)));

    final threeRows = oldLyre.playablePitchToKeyId(threeRowLayout);
    expect(threeRows.keys.toList(), <int>[
      48,
      50,
      51,
      53,
      55,
      57,
      58,
      60,
      62,
      63,
      65,
      67,
      69,
      70,
      72,
      73,
      75,
      77,
      79,
      80,
      82,
    ]);
    expect(threeRows[51], 'E3');
    expect(threeRows[58], 'B3');
    expect(threeRows[63], 'E4');
    expect(threeRows[70], 'B4');
    expect(threeRows[73], 'D5');
    expect(threeRows[75], 'E5');
    expect(threeRows[80], 'A5');
    expect(threeRows[82], 'B5');
    expect(threeRows, isNot(contains(64)));
    expect(threeRows, isNot(contains(83)));

    expect(
      oldLyre.playablePitchToKeyId(layouts.load('generic_2x7')).keys,
      <int>[60, 62, 63, 65, 67, 69, 70, 72, 73, 75, 77, 79, 80, 82],
    );

    const topKeyScore = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Lead',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 83, startMs: 0)],
        ),
      ],
    );
    final transformed = analyzeScoreForTarget(
      topKeyScore,
      target: AnalysisTarget(
        profile: profile,
        variant: oldLyre,
        layout: threeRowLayout,
      ),
      fixedPitchOffset: 0,
    ).buildRecommendedPipeline().run(topKeyScore);
    final topKeyNote = transformed.score.tracks.single.notes.single;
    expect(topKeyNote.pitch, 82);
    expect(topKeyNote.attrs['keyId'], 'B5');
  });

  test('keeps legacy variant ids as aliases after cleanup', () {
    final profiles = YamlGameProfileRepository(bundle);

    expect(profiles.load('genshin').variantById('variant_2')?.id, 'horn');
    expect(profiles.load('genshin').variantById('variant_3')?.id, 'old_lyre');
    expect(profiles.load('sdyxz').variantById('variant_2')?.id, 'bamboo_flute');
    expect(profiles.load('sdyxz').variantById('variant_3')?.id, 'xiao');
  });

  test('loads procedural generic_3x7 layout', () {
    final layouts = YamlLayoutRepository(bundle);
    final layout = layouts.load('generic_3x7');

    expect(layout.algorithm, LayoutAlgorithm.procedural);
    expect(layout.keys.length, greaterThan(10));
    expect(layout.keyIdForPitch(60), 'C4');
    expect(layout.keyIdForPitch(71), 'B4');
  });

  test('keeps C6 in speedmobile 37-key layout', () {
    final layouts = YamlLayoutRepository(bundle);
    final layout = layouts.load('speedmobile_interleaved3x12_1');

    expect(layout.algorithm, LayoutAlgorithm.procedural);
    expect(layout.keys.length, 37);
    expect(layout.keyIdForPitch(84), 'C6');
  });
}
