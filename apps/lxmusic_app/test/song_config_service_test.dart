import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/workbench/models/song_config.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/services/song_config_service.dart';
import 'package:lxmusic_assets/lxmusic_assets.dart';
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

  test('upgrades recognized legacy target mappings when loading', () async {
    final profiles = YamlGameProfileRepository(bundledYamlAssetBundle);
    final layouts = YamlLayoutRepository(bundledYamlAssetBundle);
    final profile = profiles.load('genshin');
    final variant = profile.variantById('old_lyre')!;
    final layout = layouts.load('generic_3x7');
    final legacyPitches = layout.pitchToKeyId.keys.toList()..sort();
    final file = MusicFile(
      path: '/unused/old-lyre.mid',
      fileName: 'old-lyre.mid',
      formatId: 'midi',
    );
    final legacy = SongConfig(
      fileName: file.fileName,
      profileId: profile.id,
      variantId: variant.id,
      layoutId: layout.id,
      steps: <TransformStep>[
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': legacyPitches,
            'semiToneRoundingMode': 'floor',
          },
        ),
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': layout.pitchToKeyId.map(
              (pitch, keyId) => MapEntry(pitch.toString(), keyId),
            ),
          },
        ),
      ],
    );
    const store = SongConfigStore();
    await store.save(legacy);
    final service = SongConfigService(
      parserRegistry: ParserRegistry(const <String, ScoreParser>{}),
      configStore: store,
      fileStore: const _UnusedFileStore(),
    );

    final upgraded = await service.ensureForTarget(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
    );

    final legalize = upgraded.steps.singleWhere(
      (step) => step.type == 'legalizeTargetNoteRange',
    );
    final noteToKey = upgraded.steps.singleWhere(
      (step) => step.type == 'noteToKey',
    );
    expect(legalize.config['mappingMode'], targetDerivedMappingMode);
    expect(legalize.config['wrapPitchRange'], <int>[48, 83]);
    expect(legalize.config['supportedPitches'], contains(82));
    expect(legalize.config['supportedPitches'], isNot(contains(83)));
    expect(noteToKey.config['pitchToKeyId'], containsPair('82', 'B5'));
    expect(noteToKey.config['pitchToKeyId'], isNot(contains('83')));

    final persisted = await store.load(SongConfigKey.fromConfig(upgraded));
    expect(
      persisted!.steps
          .singleWhere((step) => step.type == 'noteToKey')
          .config['mappingMode'],
      targetDerivedMappingMode,
    );
  });

  test('JSON round-trip preserves unknown steps and their config', () {
    final config = SongConfig.fromJson(<String, Object?>{
      'fileName': 'future.mid',
      'profileId': 'genshin',
      'variantId': 'lyre',
      'layoutId': 'generic_3x7',
      'steps': <Object?>[
        <String, Object?>{'type': 'noteToKey'},
        <String, Object?>{
          'type': 'futureTransform',
          'config': <String, Object?>{'enabled': true, 'version': 2},
        },
        <String, Object?>{'type': 'mergeTracks'},
      ],
    });
    final restored = SongConfig.fromJson(config.toJson());

    expect(restored.steps.map((step) => step.type), <String>[
      'mergeTracks',
      'noteToKey',
      'futureTransform',
    ]);
    expect(restored.steps.last.config, <String, Object?>{
      'enabled': true,
      'version': 2,
    });
  });

  test('summarizes transform report for config UI', () {
    const report = TransformReport(
      stats: <PassStat>[
        PassStat(
          name: 'LegalizeTargetNoteRangePass',
          values: <String, Object?>{
            'underFlowedNoteCount': 1,
            'overFlowedNoteCount': 2,
            'middleFailedNoteCount': 3,
            'roundedNoteCount': 4,
          },
        ),
        PassStat(
          name: 'MergeNearbyNotesPass',
          values: <String, Object?>{'droppedSameNoteCount': 2},
        ),
        PassStat(
          name: 'SingleKeyFrequencyLimitPass',
          values: <String, Object?>{'droppedNoteCount': 5},
        ),
        PassStat(
          name: 'ChordNoteCountLimitPass',
          values: <String, Object?>{'droppedNoteCount': 6},
        ),
      ],
      noteSummary: NotePipelineSummary(
        inputNoteCount: 20,
        outputNoteCount: 12,
        pipelineNotesAdded: 1,
        pipelineNotesRemoved: 9,
      ),
    );

    final summary = ConfigReportSummary.fromReport(report);

    expect(summary.inputNoteCount, 20);
    expect(summary.outputNoteCount, 12);
    expect(summary.pipelineNotesAdded, 1);
    expect(summary.pipelineNotesRemoved, 9);
    expect(summary.outOfRangeDiscarded, 6);
    expect(summary.semitoneRounded, 4);
    expect(summary.tooDenseDiscarded, 7);
    expect(summary.chordNotesDiscarded, 6);
  });

  test('updates selected tracks in mergeTracks config', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(
          type: 'mergeTracks',
          config: <String, Object?>{'skipPercussion': true},
        ),
      ],
    );

    config.selectedTrackIndexes = <int>[2, 0];
    expect(config.selectedTrackIndexes, <int>[0, 2]);
    expect(config.steps.single.config['skipPercussion'], isTrue);

    config.selectedTrackIndexes = null;
    expect(config.selectedTrackIndexes, isNull);
    expect(config.steps.single.config.containsKey('selectedTracks'), isFalse);
  });

  test('updates click speed limit as note frequency soft limit', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(type: 'mergeTracks'),
        TransformStep(
          type: 'singleKeyFrequencyLimit',
          config: {'minIntervalMs': 20},
        ),
      ],
    );

    expect(config.clickLimitPerSecond, isNull);

    config.clickLimitPerSecond = 3.3;
    final limitStep = config.steps.singleWhere(
      (step) => step.type == 'noteFrequencySoftLimit',
    );
    expect(limitStep.config['minIntervalMs'], 303);
    expect(config.clickLimitPerSecond, closeTo(3.3, 0.01));

    config.clickLimitPerSecond = null;
    expect(
      config.steps.any((step) => step.type == 'noteFrequencySoftLimit'),
      isFalse,
    );
  });

  test('enables chord limit with legacy defaults', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(
          type: 'singleKeyFrequencyLimit',
          config: <String, Object?>{'minIntervalMs': 20},
        ),
      ],
    );

    expect(config.chordMaxNoteCount, isNull);

    config.chordMaxNoteCount = 2;

    expect(config.chordMaxNoteCount, 2);
    expect(
      config.steps
          .singleWhere((step) => step.type == 'chordNoteCountLimit')
          .config,
      <String, Object?>{
        'maxNoteCount': 2,
        'limitMode': 'split',
        'splitDelayMs': 75,
        'selectMode': 'high',
      },
    );

    config.chordMaxNoteCount = null;
    expect(config.chordMaxNoteCount, isNull);
  });

  test('updates chord limit count without dropping existing config', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(
          type: 'chordNoteCountLimit',
          config: <String, Object?>{
            'maxNoteCount': 4,
            'limitMode': 'delete',
            'splitDelayMs': 120,
            'selectMode': 'random',
            'randomSeed': 1234,
            'futureOption': 'keep-me',
          },
        ),
      ],
    );

    expect(config.chordMaxNoteCount, 4);

    config.chordMaxNoteCount = 3;

    expect(config.chordMaxNoteCount, 3);
    expect(config.steps.single.config, <String, Object?>{
      'maxNoteCount': 3,
      'limitMode': 'delete',
      'splitDelayMs': 120,
      'selectMode': 'random',
      'randomSeed': 1234,
      'futureOption': 'keep-me',
    });
  });

  test('updates octave wrapping options in legalize config', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[60, 62],
            'semiToneRoundingMode': 'floor',
          },
        ),
      ],
    );

    expect(config.wrapHigherOctaveIntoRange, isTrue);
    expect(config.wrapLowerOctaveIntoRange, isFalse);

    config.wrapHigherOctaveIntoRange = false;
    config.wrapLowerOctaveIntoRange = true;

    final legalizeStep = config.steps.single;
    expect(legalizeStep.config['wrapHigherOctave'], 0);
    expect(legalizeStep.config['wrapLowerOctave'], 1);
  });

  test('keeps pitch octave and semitone controls independent', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      recommendedPitchOffset: 3,
      steps: const <TransformStep>[],
    );

    config.pitchSemitoneOffset = 5;
    expect(config.pitchOffset, 5);
    expect(config.pitchOctaveOffset, 0);
    expect(config.pitchSemitoneOffset, 5);

    config.pitchOctaveOffset = 1;
    expect(config.pitchOffset, 17);
    expect(config.pitchOctaveOffset, 1);
    expect(config.pitchSemitoneOffset, 5);

    config.pitchOctaveOffset = -1;
    expect(config.pitchOffset, -7);
    expect(config.pitchOctaveOffset, -1);
    expect(config.pitchSemitoneOffset, 5);
  });

  test('simple octave shift is relative to recommended pitch offset', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      recommendedPitchOffset: 3,
      steps: const <TransformStep>[],
    );

    expect(config.recommendedPitchOctaveOffset, 0);
    expect(config.recommendedPitchSemitoneOffset, 3);

    config.simplePitchOctaveShift = -1;
    expect(config.pitchOffset, -9);
    expect(config.pitchOctaveOffset, -1);
    expect(config.pitchSemitoneOffset, 3);
    expect(config.simplePitchOctaveShift, -1);

    config.simplePitchOctaveShift = 0;
    expect(config.pitchOffset, 3);
    expect(config.simplePitchOctaveShift, 0);

    config.simplePitchOctaveShift = 1;
    expect(config.pitchOffset, 15);
    expect(config.simplePitchOctaveShift, 1);

    config.pitchSemitoneOffset = 5;
    config.simplePitchOctaveShift = -1;
    expect(config.pitchOffset, -9);
    expect(config.pitchSemitoneOffset, 3);
    expect(config.pitchOctaveOffset, -1);
  });

  test('toggles blank skipping as paired transform steps', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(type: 'mergeTracks'),
        TransformStep(type: 'storeCurrentNoteTime'),
        TransformStep(type: 'noteToKey'),
      ],
    );

    config.skipBlank = true;
    expect(config.skipBlank, isTrue);
    expect(config.steps.map((step) => step.type).toList(), <String>[
      'mergeTracks',
      'storeCurrentNoteTime',
      'skipIntro',
      'limitBlankDuration',
      'noteToKey',
    ]);

    config.skipBlank = false;
    expect(config.skipBlank, isFalse);
    expect(config.steps.map((step) => step.type).toList(), <String>[
      'mergeTracks',
      'storeCurrentNoteTime',
      'noteToKey',
    ]);
  });

  test('UI mutations keep a deterministic legacy-compatible step order', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(type: 'mergeTracks'),
        TransformStep(type: 'storeCurrentNoteTime'),
        TransformStep(
          type: 'mergeNearbyNotes',
          config: <String, Object?>{'maxIntervalMs': 50, 'maxBatchSize': 19},
        ),
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[60, 62],
          },
        ),
        TransformStep(
          type: 'singleKeyFrequencyLimit',
          config: <String, Object?>{'minIntervalMs': 20},
        ),
        TransformStep(type: 'bindLyrics'),
        TransformStep(type: 'noteToKey'),
      ],
    );

    config.chordMaxNoteCount = 2;
    config.skipBlank = true;
    config.clickLimitPerSecond = 5;
    config.pitchOffset = 2;
    config.humanifyStrength = 10;
    config.speed = 0.5;

    expect(config.steps.map((step) => step.type).toList(), <String>[
      'mergeTracks',
      'storeCurrentNoteTime',
      'speedChange',
      'mergeNearbyNotes',
      'humanify',
      'pitchOffset',
      'legalizeTargetNoteRange',
      'singleKeyFrequencyLimit',
      'skipIntro',
      'limitBlankDuration',
      'noteFrequencySoftLimit',
      'chordNoteCountLimit',
      'bindLyrics',
      'noteToKey',
    ]);
  });

  test('speed change runs before time-based note filtering', () {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      steps: const <TransformStep>[
        TransformStep(type: 'mergeTracks'),
        TransformStep(type: 'storeCurrentNoteTime'),
        TransformStep(
          type: 'singleKeyFrequencyLimit',
          config: <String, Object?>{'minIntervalMs': 50},
        ),
      ],
    );
    config.speed = 0.5;

    final result = TransformPipeline(config.steps).run(
      const Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(pitch: 60, startMs: 0),
              NoteEvent(pitch: 60, startMs: 30),
            ],
          ),
        ],
      ),
    );

    expect(
      result.score.tracks.first.notes.map((note) => note.startMs).toList(),
      <int>[0, 60],
    );
  });

  test('recommended song config enables blank skipping by default', () {
    const profile = GameProfile(
      id: 'demo',
      displayName: 'Demo',
      packageNameHints: <String>[],
      defaultLayoutId: 'layout',
      layouts: <LayoutBinding>[LayoutBinding(layoutId: 'layout')],
      variants: <InstrumentVariant>[
        InstrumentVariant(
          id: 'default',
          displayName: '默认',
          noteDurationMode: NoteDurationMode.none,
        ),
      ],
      sameKeyMinIntervalMs: 20,
    );
    const variant = InstrumentVariant(
      id: 'default',
      displayName: '默认',
      noteDurationMode: NoteDurationMode.none,
    );
    const layout = KeyLayout(
      id: 'layout',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'C4', pitch: 60, normX: 0.1, normY: 0.8),
      ],
      pitchToKeyId: <int, String>{60: 'C4'},
    );
    const candidate = PitchOffsetCandidate(
      offset: 0,
      outRangedWeight: 0,
      overFlowedNoteCount: 0,
      underFlowedNoteCount: 0,
      roundedNoteCount: 0,
    );

    final config = createRecommendedSongConfig(
      file: MusicFile(
        path: '/tmp/demo.mid',
        fileName: 'demo.mid',
        formatId: 'midi',
      ),
      profile: profile,
      variant: variant,
      layout: layout,
      analysis: const ScoreAnalysis(
        source: Score(
          format: SourceFormat.jsonScore,
          tracks: <Track>[
            Track(
              name: 'Lead',
              channel: 0,
              notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
            ),
          ],
        ),
        target: AnalysisTarget(
          profile: profile,
          variant: variant,
          layout: layout,
        ),
        pitchOffset: PitchOffsetInference(
          bestOffset: 0,
          bestCandidate: candidate,
          candidates: <PitchOffsetCandidate>[candidate],
        ),
        trackSelection: null,
      ),
    );

    expect(config.skipBlank, isTrue);
    expect(config.steps.map((step) => step.type).toList(), <String>[
      'mergeTracks',
      'storeCurrentNoteTime',
      'mergeNearbyNotes',
      'legalizeTargetNoteRange',
      'singleKeyFrequencyLimit',
      'skipIntro',
      'limitBlankDuration',
      'bindLyrics',
      'noteToKey',
    ]);
    expect(
      config.steps
          .singleWhere((step) => step.type == 'mergeNearbyNotes')
          .config,
      <String, Object?>{'maxIntervalMs': 50, 'maxBatchSize': 19},
    );
  });
}

class _UnusedFileStore implements PlatformFileStore {
  const _UnusedFileStore();

  Never _unused() => throw StateError('File store should not be used.');

  @override
  Future<void> deleteFile(String path) async => _unused();

  @override
  Future<bool> exists(String path) async => _unused();

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async => _unused();

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) async => _unused();

  @override
  Future<Uint8List> readBytes(String path) async => _unused();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async => _unused();
}
