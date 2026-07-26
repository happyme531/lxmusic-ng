import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/workbench/models/song_config.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/widgets/config_editor_card.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
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
  const pitchCandidate = PitchOffsetCandidate(
    offset: 0,
    outRangedWeight: 0,
    overFlowedNoteCount: 0,
    underFlowedNoteCount: 0,
    roundedNoteCount: 0,
  );

  testWidgets('simple config keeps only direct options', (tester) async {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'demo',
      variantId: 'default',
      layoutId: 'layout',
      steps: const <TransformStep>[
        TransformStep(type: 'mergeTracks'),
        TransformStep(type: 'storeCurrentNoteTime'),
        TransformStep(type: 'noteToKey'),
      ],
    )..skipBlank = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configReportProvider.overrideWith(
            (ref) async => const ConfigReportSummary(
              inputNoteCount: 10,
              outputNoteCount: 8,
              pipelineNotesAdded: 0,
              pipelineNotesRemoved: 2,
              outOfRangeDiscarded: 1,
              semitoneRounded: 1,
              tooDenseDiscarded: 0,
              chordNotesDiscarded: 0,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [ConfigEditorCard(config: config)]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('常用调整'), findsNothing);
    expect(find.text('问题修复'), findsNothing);
    expect(find.text('速度'), findsNothing);
    expect(find.text('移调'), findsNothing);
    expect(find.text('半音处理'), findsNothing);
    expect(find.text('八度'), findsOneWidget);
    expect(find.text('降低一个'), findsOneWidget);
    expect(find.text('不变'), findsOneWidget);
    expect(find.text('升高一个'), findsOneWidget);
    expect(find.text('跳过空白'), findsOneWidget);
    expect(find.text('多指模式'), findsOneWidget);
    expect(find.text('限制点击速度'), findsOneWidget);
    expect(find.text('每秒 5 个'), findsOneWidget);
    expect(find.text('移动高八度音符到音域内'), findsNothing);
    expect(find.text('移动低八度音符到音域内'), findsNothing);
  });

  testWidgets('advanced pipeline is folded and read-only', (tester) async {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'genshin',
      variantId: 'lyre',
      layoutId: 'generic_3x7',
      configLevel: ConfigLevel.advanced,
      steps: const <TransformStep>[
        TransformStep(
          type: 'mergeTracks',
          config: <String, Object?>{'skipPercussion': true},
        ),
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[60, 62],
            'semiToneRoundingMode': 'floor',
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configReportProvider.overrideWith(
            (ref) async => const ConfigReportSummary(
              inputNoteCount: 10,
              outputNoteCount: 8,
              pipelineNotesAdded: 0,
              pipelineNotesRemoved: 2,
              outOfRangeDiscarded: 1,
              semitoneRounded: 1,
              tooDenseDiscarded: 0,
              chordNotesDiscarded: 0,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [ConfigEditorCard(config: config)]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('跳过打击乐'), findsNothing);
    expect(find.text('限制点击速度'), findsOneWidget);
    expect(find.text('八度'), findsOneWidget);
    expect(find.text('半音'), findsOneWidget);
    expect(find.text('移动高八度音符到音域内'), findsOneWidget);
    expect(find.text('移动低八度音符到音域内'), findsOneWidget);
    expect(find.text('不限'), findsAtLeastNWidgets(1));
    expect(find.text('Pipeline（共 2 步）'), findsOneWidget);
    expect(find.text('合并音轨'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pipeline（共 2 步）'));
    await tester.pumpAndSettle();

    expect(find.text('合并音轨'), findsOneWidget);
    expect(find.text('音域合法化'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  testWidgets('track picker shows percussion hint in a sheet', (tester) async {
    final config = SongConfig(
      fileName: 'demo.mid',
      profileId: 'demo',
      variantId: 'default',
      layoutId: 'layout',
      steps: const <TransformStep>[
        TransformStep(
          type: 'mergeTracks',
          config: <String, Object?>{'skipPercussion': false},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configReportProvider.overrideWith(
            (ref) async => const ConfigReportSummary(
              inputNoteCount: 10,
              outputNoteCount: 8,
              pipelineNotesAdded: 0,
              pipelineNotesRemoved: 2,
              outOfRangeDiscarded: 1,
              semitoneRounded: 1,
              tooDenseDiscarded: 0,
              chordNotesDiscarded: 0,
            ),
          ),
          currentPitchAnalysisProvider.overrideWith(
            (ref) async => const ScoreAnalysis(
              source: Score(
                format: SourceFormat.jsonScore,
                tracks: <Track>[
                  Track(
                    name: 'Drums',
                    channel: 9,
                    notes: <NoteEvent>[NoteEvent(pitch: 60, startMs: 0)],
                  ),
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
                bestCandidate: pitchCandidate,
                candidates: <PitchOffsetCandidate>[pitchCandidate],
              ),
              trackSelection: TrackSelectionAnalysis(
                threshold: 0.5,
                recommendedTrackIndexes: <int>[1],
                recommendations: <TrackPlayabilityRecommendation>[
                  TrackPlayabilityRecommendation(
                    trackIndex: 0,
                    trackName: 'Drums',
                    isPercussion: true,
                    noteCount: 1,
                    playableNoteCount: 1,
                    playableRatio: 1,
                    overFlowedNoteCount: 0,
                    underFlowedNoteCount: 0,
                    roundedNoteCount: 0,
                    recommended: false,
                  ),
                  TrackPlayabilityRecommendation(
                    trackIndex: 1,
                    trackName: 'Lead',
                    isPercussion: false,
                    noteCount: 1,
                    playableNoteCount: 1,
                    playableRatio: 1,
                    overFlowedNoteCount: 0,
                    underFlowedNoteCount: 0,
                    roundedNoteCount: 0,
                    recommended: true,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [ConfigEditorCard(config: config)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('音轨选择'), findsOneWidget);
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Drums'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('Lead'), findsOneWidget);
    expect(find.text('推荐 · 可演奏 100% · 1/1 音符'), findsOneWidget);
    expect(find.textContaining('默认不推荐'), findsOneWidget);
  });

  testWidgets('track picker uses current pitch offset analysis', (
    tester,
  ) async {
    final config = SongConfig(
      fileName: 'demo.json',
      profileId: 'demo',
      variantId: 'default',
      layoutId: 'layout',
      steps: const <TransformStep>[
        TransformStep(
          type: 'mergeTracks',
          config: <String, Object?>{'skipPercussion': false},
        ),
        TransformStep(
          type: 'pitchOffset',
          config: <String, Object?>{'offset': 2},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(
            YamlAssetBundle(<String, String>{}),
          ),
          selectedFileProvider.overrideWith(
            () => _StaticSelectedFileNotifier(
              MusicFile(
                path: 'memory://demo.json',
                fileName: 'demo.json',
                formatId: 'json-score',
              ),
            ),
          ),
          selectedProfileProvider.overrideWith(
            () => _StaticProfileNotifier(profile),
          ),
          selectedVariantProvider.overrideWith(
            () => _StaticVariantNotifier(variant),
          ),
          selectedLayoutProvider.overrideWith(
            () => _StaticLayoutNotifier(layout),
          ),
          songConfigProvider.overrideWith(
            () => _StaticSongConfigNotifier(config),
          ),
          fileStoreProvider.overrideWithValue(
            _MemoryFileStore(<String, String>{
              'memory://demo.json': _dynamicTrackScoreJson,
            }),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [ConfigEditorCard(config: config)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();

    expect(find.text('NeedsNoOffset'), findsOneWidget);
    expect(find.text('NeedsPositiveOffset'), findsOneWidget);
    expect(find.text('推荐 · 可演奏 100% · 1/1 音符'), findsOneWidget);
    expect(find.text('可演奏 0% · 0/1 音符'), findsOneWidget);
  });
}

const _dynamicTrackScoreJson = '''
{
  "format": "jsonScore",
  "tracks": [
    {
      "name": "NeedsNoOffset",
      "channel": 0,
      "notes": [{"pitch": 60, "startMs": 0, "velocity": 100}]
    },
    {
      "name": "NeedsPositiveOffset",
      "channel": 1,
      "notes": [{"pitch": 58, "startMs": 0, "velocity": 100}]
    }
  ]
}
''';

class _StaticSelectedFileNotifier extends SelectedFileNotifier {
  _StaticSelectedFileNotifier(this._file);

  final MusicFile _file;

  @override
  MusicFile? build() => _file;
}

class _StaticProfileNotifier extends SelectedProfileNotifier {
  _StaticProfileNotifier(this._profile);

  final GameProfile _profile;

  @override
  GameProfile? build() => _profile;
}

class _StaticVariantNotifier extends SelectedVariantNotifier {
  _StaticVariantNotifier(this._variant);

  final InstrumentVariant _variant;

  @override
  InstrumentVariant? build() => _variant;
}

class _StaticLayoutNotifier extends SelectedLayoutNotifier {
  _StaticLayoutNotifier(this._layout);

  final KeyLayout _layout;

  @override
  KeyLayout? build() => _layout;
}

class _StaticSongConfigNotifier extends SongConfigNotifier {
  _StaticSongConfigNotifier(this._config);

  final SongConfig _config;

  @override
  Future<SongConfig?> build() async => _config;
}

class _MemoryFileStore implements PlatformFileStore {
  _MemoryFileStore(Map<String, String> files)
    : _files = files.map(
        (key, value) => MapEntry(key, Uint8List.fromList(value.codeUnits)),
      );

  final Map<String, Uint8List> _files;

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(path);
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(path);

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = 'memory://$fileName';
    _files[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    return Uint8List.fromList(_files[path]!);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _files[path] = Uint8List.fromList(bytes);
  }
}
