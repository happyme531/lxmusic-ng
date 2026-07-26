import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  test('legacy SemanticAction keeps its JSON shape and duration fallback', () {
    const action = SemanticAction(
      atMs: 100,
      durationMs: 120,
      keyIds: <String>['C4', 'E4'],
    );

    expect(action.durationMsForKey('C4'), 120);
    expect(action.durationMsForKey('E4'), 120);
    expect(action.durationMsForKey('G4'), isNull);
    expect(action.toJson(), <String, Object?>{
      'atMs': 100,
      'durationMs': 120,
      'keyIds': <String>['C4', 'E4'],
    });
  });

  test('per-key action sorts keys and retains different durations', () {
    final action = SemanticAction.perKey(
      atMs: 100,
      durationMsByKeyId: <String, int?>{'E4': 400, 'C4': 100},
    );

    expect(action.keyIds, <String>['C4', 'E4']);
    expect(action.durationMs, 400);
    expect(action.durationMsForKey('C4'), 100);
    expect(action.durationMsForKey('E4'), 400);
    expect(action.toJson(), <String, Object?>{
      'atMs': 100,
      'durationMs': 400,
      'keyIds': <String>['C4', 'E4'],
      'durationMsByKeyId': <String, int?>{'C4': 100, 'E4': 400},
    });
  });

  test('per-key action distinguishes unknown and zero durations', () {
    final action = SemanticAction.perKey(
      atMs: 0,
      durationMsByKeyId: <String, int?>{'C4': null, 'E4': 0},
    );

    expect(action.durationMs, 0);
    expect(action.durationMsForKey('C4'), isNull);
    expect(action.durationMsForKey('E4'), 0);
    expect(action.durationMsByKeyId, <String, int?>{'C4': null, 'E4': 0});
    expect(action.toJson()['durationMsByKeyId'], <String, int?>{
      'C4': null,
      'E4': 0,
    });
  });

  test('per-key action normalizes every negative duration to zero', () {
    final uniformAction = SemanticAction.perKey(
      atMs: 0,
      durationMsByKeyId: <String, int?>{'C4': -5},
    );
    final mixedAction = SemanticAction.perKey(
      atMs: 0,
      durationMsByKeyId: <String, int?>{'C4': -5, 'E4': 100},
    );

    expect(uniformAction.durationMs, 0);
    expect(uniformAction.durationMsForKey('C4'), 0);
    expect(mixedAction.durationMsByKeyId, <String, int?>{'C4': 0, 'E4': 100});
    expect(mixedAction.durationMsForKey('C4'), 0);
  });

  test('uniform known durations keep the legacy compact representation', () {
    final action = SemanticAction.perKey(
      atMs: 0,
      durationMsByKeyId: <String, int?>{'E4': 100, 'C4': 100},
    );

    expect(action.keyIds, <String>['C4', 'E4']);
    expect(action.durationMs, 100);
    expect(action.durationMsByKeyId, isEmpty);
    expect(action.durationMsForKey('C4'), 100);
  });
}
