import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/preview/models/preview_models.dart';
import 'package:lxmusic_app/features/preview/preview_screen.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
  test('semantic highlights expire independently for an uneven chord', () {
    final plan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 400,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 0,
          durationMsByKeyId: <String, int?>{'C4': 100, 'E4': 400},
        ),
      ],
    );

    expect(activeSemanticKeyIdsAt(plan, 50), <String>{'C4', 'E4'});
    expect(activeSemanticKeyIdsAt(plan, 100), <String>{'E4'});
    expect(activeSemanticKeyIdsAt(plan, 150), <String>{'E4'});
    expect(activeSemanticKeyIdsAt(plan, 450), isEmpty);
  });

  test('semantic highlights retain the point-note visual fallback', () {
    final plan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 0,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 0,
          durationMsByKeyId: <String, int?>{'C4': null},
        ),
      ],
    );

    expect(activeSemanticKeyIdsAt(plan, 100), <String>{'C4'});
    expect(activeSemanticKeyIdsAt(plan, 120), isEmpty);
    expect(activeSemanticKeyIdsAt(plan, 121), isEmpty);
    expect(semanticPreviewTotalDurationMs(plan), 120);
  });

  test('mixed durations use each key instead of the scalar envelope', () {
    final plan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 0,
      actions: <SemanticAction>[
        SemanticAction.perKey(
          atMs: 0,
          durationMsByKeyId: <String, int?>{'C4': null, 'E4': 20},
        ),
      ],
    );

    expect(activeSemanticKeyIdsAt(plan, 50), <String>{'C4'});
    expect(semanticPreviewTotalDurationMs(plan), 120);
  });

  test('preview total includes lane notes omitted from semantic actions', () {
    const plan = SemanticPlan(
      profileId: 'demo',
      layoutId: 'layout',
      variantId: 'hold',
      totalDurationMs: 110,
      actions: <SemanticAction>[
        SemanticAction(atMs: 0, durationMs: 100, keyIds: <String>['C4']),
      ],
    );
    const laneNotes = <PreviewLaneNote>[
      PreviewLaneNote(
        keyId: 'C4',
        pitch: 60,
        startMs: 0,
        durationMs: 100,
        velocity: 100,
        isPoint: false,
      ),
      PreviewLaneNote(
        keyId: 'C4',
        pitch: 60,
        startMs: 110,
        durationMs: 80,
        velocity: 100,
        isPoint: true,
      ),
    ];

    expect(previewTotalDurationMs(plan, laneNotes), 190);
  });
}
