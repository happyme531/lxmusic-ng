import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/preview/preview_screen.dart';
import 'package:lxmusic_app/features/preview/providers/preview_provider.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
  test(
    'preview maps an effective pitch to its physical key and ignores stale attrs',
    () {
      const variant = InstrumentVariant(
        id: 'replacement',
        displayName: 'Replacement',
        noteDurationMode: NoteDurationMode.none,
        replacePitchMap: <int, int>{64: 63},
      );
      const layout = KeyLayout(
        id: 'layout',
        algorithm: LayoutAlgorithm.explicit,
        keys: <KeyDefinition>[
          KeyDefinition(id: 'E4', pitch: 64, normX: 0.5, normY: 0.5),
        ],
        pitchToKeyId: <int, String>{64: 'E4'},
      );
      const score = Score(
        format: SourceFormat.jsonScore,
        tracks: <Track>[
          Track(
            name: 'Main',
            channel: 0,
            notes: <NoteEvent>[
              NoteEvent(
                pitch: 63,
                startMs: 10,
                durationMs: 120,
                attrs: <String, Object?>{
                  'keyId': 'stale-key',
                  'mappedPitch': 64,
                  noteKeyMappingModeAttr: targetDerivedMappingMode,
                },
              ),
              NoteEvent(
                pitch: 64,
                startMs: 20,
                durationMs: 120,
                attrs: <String, Object?>{
                  'keyId': 'E4',
                  'mappedPitch': 63,
                  noteKeyMappingModeAttr: targetDerivedMappingMode,
                },
              ),
            ],
          ),
        ],
      );

      final notes = buildPreviewLaneNotes(
        score: score,
        variant: variant,
        layout: layout,
      );

      expect(notes, hasLength(1));
      expect(notes.single.keyId, 'E4');
      expect(notes.single.pitch, 63);
      expect(notes.single.startMs, 10);
    },
  );

  test('preview honors custom key mapping and sounds its physical key', () {
    const variant = InstrumentVariant(
      id: 'replacement',
      displayName: 'Replacement',
      noteDurationMode: NoteDurationMode.none,
      replacePitchMap: <int, int>{64: 63, 83: 82},
    );
    const layout = KeyLayout(
      id: 'layout',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'E4', pitch: 64, normX: 0.2, normY: 0.5),
        KeyDefinition(id: 'B5', pitch: 83, normX: 0.8, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{64: 'E4', 83: 'B5'},
    );
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 64, startMs: 10)],
        ),
      ],
    );

    final notes = buildPreviewLaneNotes(
      score: score,
      variant: variant,
      layout: layout,
      customPitchToKeyId: const <int, String>{64: 'B5'},
    );

    expect(notes.single.keyId, 'B5');
    expect(notes.single.pitch, 82);
  });

  test('preview does not let note attrs opt into custom mapping', () {
    const variant = InstrumentVariant(
      id: 'replacement',
      displayName: 'Replacement',
      noteDurationMode: NoteDurationMode.none,
      replacePitchMap: <int, int>{64: 63, 83: 82},
    );
    const layout = KeyLayout(
      id: 'layout',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'E4', pitch: 64, normX: 0.2, normY: 0.5),
        KeyDefinition(id: 'B5', pitch: 83, normX: 0.8, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{64: 'E4', 83: 'B5'},
    );
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(
              pitch: 63,
              startMs: 10,
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

    final notes = buildPreviewLaneNotes(
      score: score,
      variant: variant,
      layout: layout,
    );

    expect(notes.single.keyId, 'E4');
    expect(notes.single.pitch, 63);
  });

  test('preview rejects a stale custom mapping after a pitch change', () {
    const variant = InstrumentVariant(
      id: 'replacement',
      displayName: 'Replacement',
      noteDurationMode: NoteDurationMode.none,
      replacePitchMap: <int, int>{64: 63, 83: 82},
    );
    const layout = KeyLayout(
      id: 'layout',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'E4', pitch: 64, normX: 0.2, normY: 0.5),
        KeyDefinition(id: 'B5', pitch: 83, normX: 0.8, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{64: 'E4', 83: 'B5'},
    );
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(
              pitch: 63,
              startMs: 10,
              attrs: <String, Object?>{
                'keyId': 'B5',
                'mappedPitch': 64,
                noteKeyMappingModeAttr: customTargetMappingMode,
              },
            ),
          ],
        ),
      ],
    );

    final notes = buildPreviewLaneNotes(
      score: score,
      variant: variant,
      layout: layout,
      customPitchToKeyId: const <int, String>{64: 'B5'},
    );

    expect(notes, isEmpty);
  });

  test('preview sounds the canonical pitch for aliased layout keys', () {
    const variant = InstrumentVariant(
      id: 'default',
      displayName: 'Default',
      noteDurationMode: NoteDurationMode.none,
    );
    const layout = KeyLayout(
      id: 'aliased',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'C4', pitch: 60, normX: 0.5, normY: 0.5),
      ],
      pitchToKeyId: <int, String>{60: 'C4', 61: 'C4'},
    );
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[NoteEvent(pitch: 61, startMs: 10)],
        ),
      ],
    );

    final notes = buildPreviewLaneNotes(
      score: score,
      variant: variant,
      layout: layout,
    );

    expect(notes.single.keyId, 'C4');
    expect(notes.single.pitch, 60);
  });

  test('manual preview disables keys outside the variant range', () {
    const variant = InstrumentVariant(
      id: 'narrow',
      displayName: 'Narrow',
      noteDurationMode: NoteDurationMode.none,
      availablePitchRange: IntRange(48, 71),
    );

    expect(
      effectivePreviewPitchForLayoutKey(
        variant,
        const KeyDefinition(id: 'B4', pitch: 71, normX: 0, normY: 0),
      ),
      71,
    );
    expect(
      effectivePreviewPitchForLayoutKey(
        variant,
        const KeyDefinition(id: 'C5', pitch: 72, normX: 0, normY: 0),
      ),
      isNull,
    );
  });
}
