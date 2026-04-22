import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('builds semantic plan from score and layout', () {
    const score = Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Main',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 0, durationMs: 100),
            NoteEvent(pitch: 64, startMs: 0, durationMs: 100),
            NoteEvent(pitch: 67, startMs: 200, durationMs: 120),
          ],
        ),
      ],
    );

    const profile = GameProfile(
      id: 'demo',
      displayName: 'Demo',
      packageNameHints: <String>[],
      defaultLayoutId: 'layout',
      layouts: <LayoutBinding>[
        LayoutBinding(layoutId: 'layout', isDefault: true),
      ],
      variants: <InstrumentVariant>[
        InstrumentVariant(
          id: 'default',
          displayName: '默认',
          noteDurationMode: NoteDurationMode.none,
        ),
      ],
      sameKeyMinIntervalMs: 20,
    );

    const layout = KeyLayout(
      id: 'layout',
      algorithm: LayoutAlgorithm.explicit,
      keys: <KeyDefinition>[
        KeyDefinition(id: 'C4', pitch: 60, normX: 0.1, normY: 0.8),
        KeyDefinition(id: 'E4', pitch: 64, normX: 0.2, normY: 0.8),
        KeyDefinition(id: 'G4', pitch: 67, normX: 0.3, normY: 0.8),
      ],
      pitchToKeyId: <int, String>{60: 'C4', 64: 'E4', 67: 'G4'},
    );

    final plan = const PerformancePlanner().plan(
      score,
      PlanningContext(
        profile: profile,
        layout: layout,
        variant: profile.variants.first,
      ),
    );

    expect(plan.actions, hasLength(2));
    expect(plan.actions.first.keyIds, <String>['C4', 'E4']);
    expect(plan.actions.first.durationMs, 100);
    expect(plan.actions.last.keyIds, <String>['G4']);
  });
}
