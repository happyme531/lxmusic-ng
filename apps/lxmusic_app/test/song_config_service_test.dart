import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/workbench/models/song_config.dart';
import 'package:lxmusic_app/features/workbench/services/song_config_service.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores independent song configs per target triple', () async {
    final store = const SongConfigStore();
    final a = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[],
      recommendedPitchOffset: 2,
    );
    final b = SongConfig(
      fileName: 'demo.mid',
      profileId: 'sky',
      variantId: 'harp',
      layoutId: 'sky_3x5',
      steps: const <TransformStep>[],
      recommendedPitchOffset: -3,
    );

    await store.save(a);
    await store.save(b);

    final loadedA = await store.load(SongConfigKey.fromConfig(a));
    final loadedB = await store.load(SongConfigKey.fromConfig(b));

    expect(loadedA, isNotNull);
    expect(loadedA!.profileId, 'genshin');
    expect(loadedA.recommendedPitchOffset, 2);
    expect(loadedB, isNotNull);
    expect(loadedB!.profileId, 'sky');
    expect(loadedB.recommendedPitchOffset, -3);
  });

  test('falls back to legacy file-only storage when target matches', () async {
    final legacy = SongConfig(
      fileName: 'legacy.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[],
      recommendedPitchOffset: 5,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'song_config_legacy.mid': jsonEncode(legacy.toJson()),
    });

    final store = const SongConfigStore();
    final loaded = await store.load(
      const SongConfigKey(
        fileName: 'legacy.mid',
        profileId: 'genshin',
        variantId: 'lyre',
        layoutId: 'generic_3x7',
      ),
    );
    final mismatch = await store.load(
      const SongConfigKey(
        fileName: 'legacy.mid',
        profileId: 'sky',
        variantId: 'harp',
        layoutId: 'sky_3x5',
      ),
    );

    expect(loaded, isNotNull);
    expect(loaded!.recommendedPitchOffset, 5);
    expect(mismatch, isNull);
  });
}

