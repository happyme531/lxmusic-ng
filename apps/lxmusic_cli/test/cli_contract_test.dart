import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('convert format contract', () {
    test(
      '--format is always the input format regardless of position',
      () async {
        final result = await _runCli(<String>[
          'convert',
          '--input',
          _workspacePath('examples/json_score/simple_score.json'),
          '--format',
          'json-score',
          '--profile',
          'generic_demo',
          '--output-format',
          'semantic-plan-json',
        ]);

        expect(result.exitCode, 0, reason: result.stderr as String);
        final output = Map<String, Object?>.from(
          jsonDecode(result.stdout as String) as Map,
        );
        expect(output['profileId'], 'generic_demo');
        expect(result.stderr as String, contains('[lxmusic] parsed score'));
      },
    );

    test('the documented convert example executes successfully', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_help_');
      addTearDown(() => temp.delete(recursive: true));
      final output = '${temp.path}/out.json';

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/json_score/simple_score.json'),
        '--format',
        'json-score',
        '--profile',
        'generic_demo',
        '--analyze',
        '--option',
        'legalizeTargetNoteRange.semiToneRoundingMode=floor',
        '--output',
        output,
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(File(output).existsSync(), isTrue);
      expect(File(output).readAsStringSync(), contains('"semanticPlan"'));
    });

    test('help no longer describes positional format semantics', () async {
      final result = await _runCli(<String>['convert', '--help']);

      expect(result.exitCode, 0);
      expect(result.stdout as String, contains('与参数位置无关'));
      expect(result.stdout as String, isNot(contains('before --input')));
    });
  });

  group('conversion config contract', () {
    test(
      'accepts the repository pipeline-only config with a CLI target',
      () async {
        final result = await _runCli(<String>[
          'convert',
          '--input',
          _workspacePath('examples/domiso/scale.dms.txt'),
          '--format',
          'domiso',
          '--profile',
          'generic_demo',
          '--config',
          _workspacePath('examples/pipelines/demo_plan.yaml'),
          '--output-format',
          'semantic-plan-json',
        ]);

        expect(result.exitCode, 0, reason: result.stderr as String);
        final output = Map<String, Object?>.from(
          jsonDecode(result.stdout as String) as Map,
        );
        expect(output['profileId'], 'generic_demo');
      },
    );

    test('accepts a full config without redundant target arguments', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_config_');
      addTearDown(() => temp.delete(recursive: true));
      final configPath = '${temp.path}/conversion.yaml';

      final analyze = await _runCli(<String>[
        'analyze',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--format',
        'domiso',
        '--profile',
        'generic_demo',
        '--output',
        configPath,
      ]);
      expect(analyze.exitCode, 0, reason: analyze.stderr as String);

      final convert = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--format',
        'domiso',
        '--config',
        configPath,
        '--output-format',
        'semantic-plan-json',
      ]);

      expect(convert.exitCode, 0, reason: convert.stderr as String);
      final output = Map<String, Object?>.from(
        jsonDecode(convert.stdout as String) as Map,
      );
      expect(output['profileId'], 'generic_demo');
    });

    test('rejects target arguments that conflict with a full config', () async {
      final temp = await Directory.systemTemp.createTemp(
        'lxmusic_cli_conflict_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final configPath = '${temp.path}/conversion.yaml';

      final analyze = await _runCli(<String>[
        'analyze',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--output',
        configPath,
      ]);
      expect(analyze.exitCode, 0, reason: analyze.stderr as String);

      final convert = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--config',
        configPath,
        '--profile',
        'genshin',
      ]);

      _expectFailure(
        convert,
        exitCode: 64,
        containing: 'conflicts with config',
      );
    });

    test('requires a CLI target for a pipeline-only config', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--config',
        _workspacePath('examples/pipelines/demo_plan.yaml'),
      ]);

      _expectFailure(result, exitCode: 64, containing: '--profile is required');
    });

    test('rejects --analyze together with --config', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--config',
        _workspacePath('examples/pipelines/demo_plan.yaml'),
        '--analyze',
      ]);

      _expectFailure(result, exitCode: 64, containing: 'mutually exclusive');
    });
  });

  group('stable failures and executable fallback', () {
    test('missing input returns EX_NOINPUT without a stack trace', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/does-not-exist.dms.txt'),
        '--profile',
        'generic_demo',
      ]);

      _expectFailure(result, exitCode: 66, containing: 'No such file');
    });

    test('malformed YAML returns EX_DATAERR without a stack trace', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_yaml_');
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/broken.yaml')
        ..writeAsStringSync('pipeline: [');

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--config',
        config.path,
      ]);

      _expectFailure(result, exitCode: 65, containing: 'Invalid input data');
    });

    test('invalid config shape returns EX_DATAERR', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_shape_');
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/broken.yaml')
        ..writeAsStringSync('steps: not-a-list\n');

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--config',
        config.path,
      ]);

      _expectFailure(result, exitCode: 65, containing: 'pipeline.steps');
    });

    test('ambiguous pipeline config returns EX_DATAERR', () async {
      final temp = await Directory.systemTemp.createTemp(
        'lxmusic_cli_ambiguous_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/ambiguous.yaml')
        ..writeAsStringSync('pipeline:\n  steps: []\nsteps: []\n');

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--config',
        config.path,
      ]);

      _expectFailure(
        result,
        exitCode: 65,
        containing: 'both "pipeline" and top-level "steps"',
      );
    });

    test('malformed JSON score returns EX_DATAERR', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_json_');
      addTearDown(() => temp.delete(recursive: true));
      final input = File('${temp.path}/broken.json')
        ..writeAsStringSync('{not-json');

      final result = await _runCli(<String>[
        'convert',
        '--input',
        input.path,
        '--format',
        'json-score',
        '--profile',
        'generic_demo',
      ]);

      _expectFailure(result, exitCode: 65, containing: 'Invalid input data');
    });

    test('unknown target in a full config returns EX_DATAERR', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_target_');
      addTearDown(() => temp.delete(recursive: true));
      final config = File('${temp.path}/unknown-target.yaml')
        ..writeAsStringSync('''
target:
  profileId: missing-profile
  variantId: default
  layoutId: generic_3x7_demo
pipeline:
  steps: []
''');

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--config',
        config.path,
      ]);

      _expectFailure(
        result,
        exitCode: 65,
        containing: 'Invalid conversion config target',
      );
    });

    test('unwritable output returns EX_CANTCREAT', () async {
      final temp = await Directory.systemTemp.createTemp('lxmusic_cli_output_');
      addTearDown(() => temp.delete(recursive: true));

      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--output',
        '${temp.path}/missing/out.json',
      ]);

      _expectFailure(result, exitCode: 73, containing: 'Cannot create output');
    });

    test('warns when executable output falls back to overlay hints', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--output-format',
        'executable-plan-json',
        '--device',
        'missing-device',
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      final output = Map<String, Object?>.from(
        jsonDecode(result.stdout as String) as Map,
      );
      final actions = (output['actions'] as List).cast<Map>();
      expect(actions, isNotEmpty);
      expect(actions.first['kind'], 'overlayHint');
      expect(result.stderr as String, contains('not directly executable'));
    });

    test('known calibration produces directly executable actions', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--output-format',
        'executable-plan-json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      final output = Map<String, Object?>.from(
        jsonDecode(result.stdout as String) as Map,
      );
      final actions = (output['actions'] as List).cast<Map>();
      expect(actions, isNotEmpty);
      expect(actions.any((action) => action['kind'] == 'overlayHint'), isFalse);
      expect(
        result.stderr as String,
        isNot(contains('not directly executable')),
      );
    });

    test('orientation mismatch does not reuse the only calibration', () async {
      final result = await _runCli(<String>[
        'convert',
        '--input',
        _workspacePath('examples/domiso/scale.dms.txt'),
        '--profile',
        'generic_demo',
        '--output-format',
        'executable-plan-json',
        '--orientation',
        'landscape',
      ]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      final output = Map<String, Object?>.from(
        jsonDecode(result.stdout as String) as Map,
      );
      final actions = (output['actions'] as List).cast<Map>();
      expect(actions, isNotEmpty);
      expect(actions.first['kind'], 'overlayHint');
      expect(result.stderr as String, contains('not directly executable'));
    });
  });
}

void _expectFailure(
  ProcessResult result, {
  required int exitCode,
  required String containing,
}) {
  final stderrText = result.stderr as String;
  expect(result.exitCode, exitCode, reason: stderrText);
  expect(stderrText, contains(containing));
  expect(stderrText, isNot(contains('Unhandled exception')));
  expect(stderrText, isNot(contains('#0')));
}

Future<ProcessResult> _runCli(List<String> arguments) {
  final packageRoot = _packageRoot();
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/lxmusic_cli.dart',
    ...arguments,
  ], workingDirectory: packageRoot);
}

String _workspacePath(String relativePath) {
  return '${_packageRoot()}/../../$relativePath';
}

String _packageRoot() {
  if (File('bin/lxmusic_cli.dart').existsSync()) {
    return Directory.current.absolute.path;
  }
  return Directory('apps/lxmusic_cli').absolute.path;
}
