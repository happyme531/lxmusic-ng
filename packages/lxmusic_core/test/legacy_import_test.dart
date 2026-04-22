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

  test('keeps legacy variant ids as aliases after cleanup', () {
    final profiles = YamlGameProfileRepository(bundle);

    expect(profiles.load('genshin').variantById('variant_2')?.id, 'horn');
    expect(
      profiles.load('genshin').variantById('variant_3')?.id,
      'old_lyre',
    );
    expect(
      profiles.load('sdyxz').variantById('variant_2')?.id,
      'bamboo_flute',
    );
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
