import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('target mapping CLI overrides', () {
    for (final options in <List<String>>[
      <String>[
        r'noteToKey.pitchToKeyId={"60":"R1"}',
        'noteToKey.mappingMode=target',
      ],
      <String>[
        'noteToKey.mappingMode=target',
        r'noteToKey.pitchToKeyId={"60":"R1"}',
      ],
      <String>['legalizeTargetNoteRange.mappingSemanticsVersion=1'],
    ]) {
      test('rejects internal metadata for ${options.join(' then ')}', () async {
        final result = await _runAnalyze(options);

        expect(result.exitCode, 64);
        expect(
          result.stderr as String,
          contains('is internal target-mapping metadata'),
        );
      });
    }

    test('normalizes a whole-pipeline override after applying it', () async {
      final result = await _runAnalyze(<String>[
        'pipeline.steps=[{"type":"noteToKey"}]',
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      final output = Map<String, Object?>.from(
        jsonDecode(result.stdout as String) as Map,
      );
      final config = Map<String, Object?>.from(output['config'] as Map);
      final pipeline = Map<String, Object?>.from(config['pipeline'] as Map);
      final steps = (pipeline['steps'] as List).cast<Map>();
      final step = Map<String, Object?>.from(steps.single);
      final stepConfig = Map<String, Object?>.from(step['config'] as Map);

      expect(step['type'], 'noteToKey');
      expect(stepConfig['mappingMode'], 'custom');
    });
  });
}

Future<ProcessResult> _runAnalyze(List<String> options) {
  final packageRoot = _packageRoot();
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/lxmusic_cli.dart',
    'analyze',
    '--input',
    '$packageRoot/../../examples/domiso/scale.dms.txt',
    '--format',
    'domiso',
    '--profile',
    'generic_demo',
    for (final option in options) ...<String>['--option', option],
  ], workingDirectory: packageRoot);
}

String _packageRoot() {
  if (File('bin/lxmusic_cli.dart').existsSync()) {
    return Directory.current.absolute.path;
  }
  return Directory('apps/lxmusic_cli').absolute.path;
}
