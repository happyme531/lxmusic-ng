import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  group('variant-aware target mapping', () {
    test('builds effective pitches while retaining nominal wrap bounds', () {
      final target = _target();

      expect(target.supportedPitches, <int>[63, 82]);
      expect(target.playablePitchToKeyId, <int, String>{63: 'E4', 82: 'B5'});
      expect(target.nominalPlayablePitchRange.toJson(), <String, Object?>{
        'min': 64,
        'max': 83,
      });
    });

    test('recommended pipeline floors the nominal top key to its sound', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 83, startMs: 0)],
          ),
        ],
      );
      final target = _target();
      final analysis = analyzeScoreForTarget(
        score,
        target: target,
        fixedPitchOffset: 0,
      );

      final result = analysis.buildRecommendedPipeline().run(score);
      final note = result.score.tracks.single.notes.single;

      expect(analysis.pitchOffset.bestCandidate.overFlowedNoteCount, 0);
      expect(analysis.pitchOffset.bestCandidate.roundedNoteCount, 1);
      expect(note.pitch, 82);
      expect(note.attrs['keyId'], 'B5');
      expect(note.attrs[noteKeyMappingModeAttr], targetDerivedMappingMode);
      expect(
        analysis
            .buildRecommendedPipeline()
            .steps
            .singleWhere((step) => step.type == 'legalizeTargetNoteRange')
            .config['wrapPitchRange'],
        <int>[64, 83],
      );
    });

    test('analysis and recommended pipeline share higher-octave wrapping', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 95, startMs: 0)],
          ),
        ],
      );
      final analysis = analyzeScoreForTarget(
        score,
        target: _target(),
        fixedPitchOffset: 0,
      );

      final result = analysis.buildRecommendedPipeline().run(score);

      expect(analysis.pitchOffset.bestCandidate.overFlowedNoteCount, 0);
      expect(analysis.pitchOffset.bestCandidate.roundedNoteCount, 1);
      expect(result.score.tracks.single.notes.single.pitch, 82);
      expect(result.score.tracks.single.notes.single.attrs['keyId'], 'B5');
    });

    test('refreshes only recognized target-derived legacy mappings', () {
      final target = _target();
      const legacySteps = <TransformStep>[
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[64, 83],
            'semiToneRoundingMode': 'ceil',
            'futureOption': true,
          },
        ),
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': <String, String>{'64': 'E4', '83': 'B5'},
            'futureOption': 'kept',
          },
        ),
      ];

      final refreshed = refreshTargetMappingSteps(
        steps: legacySteps,
        target: target,
      );

      expect(refreshed.changed, isTrue);
      expect(refreshed.steps.first.config, <String, Object?>{
        'supportedPitches': <int>[63, 82],
        'semiToneRoundingMode': 'ceil',
        'futureOption': true,
        'wrapPitchRange': <int>[64, 83],
        'mappingSemanticsVersion': variantMappingSemanticsVersion,
        'mappingMode': targetDerivedMappingMode,
      });
      expect(refreshed.steps.last.config, <String, Object?>{
        'pitchToKeyId': <String, String>{'63': 'E4', '82': 'B5'},
        'futureOption': 'kept',
        'mappingSemanticsVersion': variantMappingSemanticsVersion,
        'mappingMode': targetDerivedMappingMode,
      });

      final secondRefresh = refreshTargetMappingSteps(
        steps: refreshed.steps,
        target: target,
      );
      expect(secondRefresh.changed, isFalse);
    });

    test('marks unrecognized mappings custom without overwriting them', () {
      final target = _target();
      const customSteps = <TransformStep>[
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[60],
            'wrapHigherOctave': 3,
          },
        ),
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': <String, String>{'60': 'custom-key'},
          },
        ),
      ];

      final refreshed = refreshTargetMappingSteps(
        steps: customSteps,
        target: target,
      );

      expect(refreshed.changed, isTrue);
      expect(refreshed.steps.first.config, <String, Object?>{
        'supportedPitches': <int>[60],
        'wrapHigherOctave': 3,
        'mappingMode': customTargetMappingMode,
      });
      expect(refreshed.steps.last.config, <String, Object?>{
        'pitchToKeyId': <String, String>{'60': 'custom-key'},
        'mappingMode': customTargetMappingMode,
      });
      expect(
        refreshTargetMappingSteps(
          steps: refreshed.steps,
          target: target,
        ).changed,
        isFalse,
      );
    });

    test('does not partially migrate a mixed target/custom mapping pair', () {
      final target = _target();
      const mixedSteps = <TransformStep>[
        TransformStep(
          type: 'legalizeTargetNoteRange',
          config: <String, Object?>{
            'supportedPitches': <int>[64, 83],
            'semiToneRoundingMode': 'floor',
          },
        ),
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': <String, String>{'64': 'B5'},
          },
        ),
      ];

      final refreshed = refreshTargetMappingSteps(
        steps: mixedSteps,
        target: target,
      );

      expect(refreshed.changed, isTrue);
      expect(refreshed.steps.first.config, <String, Object?>{
        'supportedPitches': <int>[64, 83],
        'semiToneRoundingMode': 'floor',
        'mappingMode': customTargetMappingMode,
      });
      expect(refreshed.steps.last.config, <String, Object?>{
        'pitchToKeyId': <String, String>{'64': 'B5'},
        'mappingMode': customTargetMappingMode,
      });
    });

    test('preserves an unmarked mapping step without its domain pair', () {
      final refreshed = refreshTargetMappingSteps(
        steps: const <TransformStep>[
          TransformStep(
            type: 'noteToKey',
            config: <String, Object?>{
              'pitchToKeyId': <String, String>{'64': 'E4', '83': 'B5'},
            },
          ),
        ],
        target: _target(),
      );

      expect(refreshed.changed, isTrue);
      expect(refreshed.steps.single.config, <String, Object?>{
        'pitchToKeyId': <String, String>{'64': 'E4', '83': 'B5'},
        'mappingMode': customTargetMappingMode,
      });
    });

    test('planner honors a custom NoteToKey mapping provenance', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
        ],
      );
      const pipeline = TransformPipeline(<TransformStep>[
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': <String, String>{'64': 'B5'},
            'mappingMode': customTargetMappingMode,
          },
        ),
      ]);
      final target = _target();

      final transformed = pipeline.run(score).score;
      final plan = const PerformancePlanner().plan(
        transformed,
        PlanningContext(
          profile: target.profile,
          layout: target.layout,
          variant: target.variant,
          customPitchToKeyId: resolveCustomPitchToKeyId(pipeline.steps),
        ),
      );

      expect(
        transformed.tracks.single.notes.single.attrs[noteKeyMappingModeAttr],
        customTargetMappingMode,
      );
      expect(transformed.tracks.single.notes.single.attrs['mappedPitch'], 64);
      expect(plan.actions.single.keyIds, <String>['B5']);
      expect(plan.warnings, isEmpty);
    });

    test('planner does not let note attrs opt into custom mapping', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 63,
                startMs: 0,
                attrs: <String, Object?>{
                  'keyId': 'B5',
                  'mappedPitch': 63,
                  noteKeyMappingModeAttr: customTargetMappingMode,
                },
              ),
            ],
          ),
        ],
      );
      final target = _target();

      final plan = const PerformancePlanner().plan(
        score,
        PlanningContext(
          profile: target.profile,
          layout: target.layout,
          variant: target.variant,
        ),
      );

      expect(plan.actions.single.keyIds, <String>['E4']);
      expect(plan.warnings.single.code, 'stale_key_mapping');
    });

    test('planner rejects a stale custom mapping after a pitch change', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
        ],
      );
      const pipeline = TransformPipeline(<TransformStep>[
        TransformStep(
          type: 'noteToKey',
          config: <String, Object?>{
            'pitchToKeyId': <String, String>{'64': 'B5'},
            'mappingMode': customTargetMappingMode,
          },
        ),
        TransformStep(
          type: 'pitchOffset',
          config: <String, Object?>{'offset': -1},
        ),
      ]);
      final target = _target();

      final transformed = pipeline.run(score).score;
      final transformedNote = transformed.tracks.single.notes.single;
      final plan = const PerformancePlanner().plan(
        transformed,
        PlanningContext(
          profile: target.profile,
          layout: target.layout,
          variant: target.variant,
          customPitchToKeyId: resolveCustomPitchToKeyId(pipeline.steps),
        ),
      );

      expect(transformedNote.pitch, 63);
      expect(transformedNote.attrs['mappedPitch'], 64);
      expect(plan.actions, isEmpty);
      expect(plan.warnings.single.code, 'missing_key_mapping');
    });

    test('analysis counts unsupported middle pitches as unplayable', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
        ],
      );

      final candidate = evaluateFixedPitchOffset(
        score: score,
        supportedPitches: const <int>[63, 82],
        wrapPitchRange: const IntRange(64, 83),
        roundingMode: SemiToneRoundingMode.ceil,
        offset: 0,
      ).bestCandidate;

      expect(candidate.middleFailedNoteCount, 1);
      expect(candidate.outRangedWeight, 1);
      expect(candidate.toJson()['middleFailedNoteCount'], 1);
    });

    test('pitch inference avoids failed legalization in a sparse map', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
        ],
      );

      final inference = inferBestPitchOffset(
        score: score,
        supportedPitches: const <int>[63, 82],
        wrapPitchRange: const IntRange(64, 83),
        roundingMode: SemiToneRoundingMode.ceil,
      );

      expect(inference.bestOffset, -1);
      expect(inference.bestCandidate.middleFailedNoteCount, 0);
      expect(inference.bestCandidate.outRangedWeight, 0);
    });

    test('track selection excludes notes that fail middle legalization', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'FailsCeil',
            channel: 0,
            notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 0)],
          ),
          Track(
            name: 'Playable',
            channel: 1,
            notes: <NoteEvent>[NoteEvent(pitch: 63, startMs: 0)],
          ),
        ],
      );

      final analysis = analyzeScoreForTarget(
        score,
        target: _target(),
        roundingMode: SemiToneRoundingMode.ceil,
        fixedPitchOffset: 0,
      );

      expect(analysis.trackSelection!.recommendedTrackIndexes, <int>[1]);
      expect(
        analysis.trackSelection!.recommendations
            .map((entry) => (entry.playableRatio, entry.middleFailedNoteCount))
            .toList(),
        <(double, int)>[(0, 1), (1, 0)],
      );
    });

    test('planner ignores stale annotations and uses the effective map', () {
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Lead',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 63,
                startMs: 0,
                attrs: <String, Object?>{
                  'keyId': 'stale-key',
                  'mappedPitch': 64,
                  noteKeyMappingModeAttr: targetDerivedMappingMode,
                },
              ),
            ],
          ),
        ],
      );
      final target = _target();

      final plan = const PerformancePlanner().plan(
        score,
        PlanningContext(
          profile: target.profile,
          layout: target.layout,
          variant: target.variant,
        ),
      );

      expect(plan.actions.single.keyIds, <String>['E4']);
      expect(plan.warnings.single.code, 'stale_key_mapping');
    });

    test('rejects effective-pitch collisions', () {
      const collidingLayout = KeyLayout(
        id: 'collision',
        algorithm: LayoutAlgorithm.explicit,
        keys: <KeyDefinition>[
          KeyDefinition(id: 'D#4', pitch: 63, normX: 0.2, normY: 0.8),
          KeyDefinition(id: 'E4', pitch: 64, normX: 0.3, normY: 0.8),
        ],
        pitchToKeyId: <int, String>{63: 'D#4', 64: 'E4'},
      );

      expect(
        () => _variant.playablePitchToKeyId(collidingLayout),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('multiple keys'),
          ),
        ),
      );
    });
  });
}

AnalysisTarget _target() {
  return const AnalysisTarget(
    profile: _profile,
    variant: _variant,
    layout: _layout,
  );
}

const _variant = InstrumentVariant(
  id: 'old-like',
  displayName: 'Old-like',
  noteDurationMode: NoteDurationMode.none,
  replacePitchMap: <int, int>{64: 63, 83: 82},
);

const _profile = GameProfile(
  id: 'demo',
  displayName: 'Demo',
  packageNameHints: <String>[],
  defaultLayoutId: 'layout',
  layouts: <LayoutBinding>[LayoutBinding(layoutId: 'layout', isDefault: true)],
  variants: <InstrumentVariant>[_variant],
  sameKeyMinIntervalMs: 20,
);

const _layout = KeyLayout(
  id: 'layout',
  algorithm: LayoutAlgorithm.explicit,
  keys: <KeyDefinition>[
    KeyDefinition(id: 'E4', pitch: 64, normX: 0.2, normY: 0.8),
    KeyDefinition(id: 'B5', pitch: 83, normX: 0.8, normY: 0.2),
  ],
  pitchToKeyId: <int, String>{64: 'E4', 83: 'B5'},
);
