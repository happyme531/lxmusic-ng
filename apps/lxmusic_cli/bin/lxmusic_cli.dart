import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:lxmusic_assets/lxmusic_assets.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:yaml/yaml.dart';

const _commandSummaries = <String, String>{
  'analyze': '分析输入谱并生成推荐转换配置。',
  'convert': '执行转换并输出 JSON / MIDI / executable plan。',
  'list-formats': '列出支持的输入格式。',
  'list-passes': '列出已迁移的 transform passes。',
  'list-profiles': '列出已导入的 profile。',
  'validate-profiles': '校验 profile 与 layout 资产引用。',
  'inspect-profile': '查看单个 profile 的展开结果。',
};

const _topLevelConfigKeys = <String>{
  'version',
  'target',
  'analysis',
  'pipeline',
};

const _inputFormatIds = <String>[
  'domiso',
  'json-score',
  'midi',
  'skystudio-json',
  'tonejs-json',
];

const _outputFormatIds = <String>[
  'json',
  'score-json',
  'semantic-plan-json',
  'executable-plan-json',
  'midi',
];

const _transformStepTypes = <String>[
  'mergeTracks',
  'removeEmptyTracks',
  'pitchOffset',
  'legalizeTargetNoteRange',
  'noteToKey',
  'bindLyrics',
  'storeCurrentNoteTime',
  'mergeNearbyNotes',
  'foldFrequentSameNote',
  'estimateNoteDuration',
  'splitLongNote',
  'speedChange',
  'limitBlankDuration',
  'skipIntro',
  'singleKeyFrequencyLimit',
  'noteFrequencySoftLimit',
  'chordNoteCountLimit',
  'humanify',
];

const _exitUsage = 64;
const _exitDataError = 65;
const _exitNoInput = 66;
const _exitSoftware = 70;
const _exitCannotCreate = 73;

class _CliFailure implements Exception {
  const _CliFailure(this.message, {required this.exitCode});

  final String message;
  final int exitCode;
}

void main(List<String> arguments) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助')
    ..addCommand('list-formats')
    ..addCommand('list-passes')
    ..addCommand('list-profiles')
    ..addCommand('validate-profiles')
    ..addCommand('inspect-profile')
    ..addCommand('analyze')
    ..addCommand('convert');

  parser.commands['list-formats']!.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: '显示帮助',
  );
  parser.commands['list-passes']!.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: '显示帮助',
  );
  parser.commands['list-profiles']!.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: '显示帮助',
  );
  parser.commands['validate-profiles']!.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: '显示帮助',
  );

  parser.commands['inspect-profile']!
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助')
    ..addOption('profile', mandatory: true);

  parser.commands['analyze']!
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助')
    ..addOption('input', abbr: 'i', mandatory: true)
    ..addOption(
      'format',
      abbr: 'f',
      allowed: _inputFormatIds,
      help: '输入格式；省略时根据输入文件后缀和内容检测。',
    )
    ..addOption('profile', mandatory: true)
    ..addOption('layout')
    ..addOption('variant', defaultsTo: 'default')
    ..addOption(
      'track-disable-threshold',
      defaultsTo: '0.5',
      help: '多音轨自动推荐选轨阈值，范围 0-1；默认 0.5。',
    )
    ..addOption('output')
    ..addMultiOption(
      'option',
      abbr: 'o',
      help:
          '覆盖内部配置项，可多次传入，例如 '
          '--option legalizeTargetNoteRange.semiToneRoundingMode=floor',
    );

  parser.commands['convert']!
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助')
    ..addOption('input', abbr: 'i', mandatory: true)
    ..addOption(
      'format',
      abbr: 'f',
      allowed: _inputFormatIds,
      help: '输入格式；省略时根据后缀和内容检测，与参数位置无关。',
    )
    ..addOption('profile', help: '分析或 pipeline-only config 使用的目标 profile。')
    ..addOption('layout')
    ..addOption('variant', help: '目标 variant；需要 CLI 目标时默认 default。')
    ..addOption(
      'track-disable-threshold',
      defaultsTo: '0.5',
      help: '多音轨自动推荐选轨阈值，范围 0-1；默认 0.5。',
    )
    ..addOption(
      'config',
      help:
          '完整 conversion config，或仅含 steps/pipeline.steps 的 pipeline '
          'config；后者从 CLI 读取目标。',
    )
    ..addFlag('analyze', negatable: false, help: '显式重新分析；不能与 --config 同时使用。')
    ..addOption('output', help: '输出路径；也可作为唯一尾随参数传入。')
    ..addMultiOption(
      'option',
      abbr: 'o',
      help:
          '覆盖内部配置项，可多次传入，例如 '
          '--option legalizeTargetNoteRange.semiToneRoundingMode=floor',
    )
    ..addOption(
      'output-format',
      allowed: _outputFormatIds,
      help: '输出格式；省略时按输出路径后缀推断，否则默认 json。',
    )
    ..addOption('backend', defaultsTo: 'preview')
    ..addOption(
      'device',
      defaultsTo: 'sample-device',
      help: 'executable plan 使用的 calibration device id。',
    )
    ..addOption(
      'orientation',
      defaultsTo: 'portrait',
      help: 'executable plan 使用的 calibration orientation。',
    );

  ArgResults result;
  try {
    result = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('[lxmusic] ${error.message}');
    final commandName = _extractCommandName(arguments, parser);
    if (commandName != null) {
      _printCommandUsage(commandName, parser.commands[commandName]!, stderr);
    } else {
      _printUsage(parser, stderr);
    }
    exitCode = _exitUsage;
    return;
  }

  if (result['help'] as bool) {
    _printUsage(parser);
    return;
  }
  final command = result.command;
  if (command == null) {
    _printUsage(parser);
    exitCode = _exitUsage;
    return;
  }
  if ((command['help'] as bool?) ?? false) {
    _printCommandUsage(command.name!, parser.commands[command.name]!);
    return;
  }

  try {
    switch (command.name) {
      case 'list-formats':
        _runListFormats();
        return;
      case 'list-passes':
        _runListPasses();
        return;
      case 'list-profiles':
        _runListProfiles(command);
        return;
      case 'validate-profiles':
        _runValidate(command);
        return;
      case 'inspect-profile':
        _runInspect(command);
        return;
      case 'analyze':
        _runAnalyze(command);
        return;
      case 'convert':
        await _runConvert(command);
        return;
    }
  } on _CliFailure catch (error) {
    stderr.writeln('[lxmusic] ${error.message}');
    exitCode = error.exitCode;
  } on ArgumentError catch (error) {
    stderr.writeln('[lxmusic] ${_errorMessage(error)}');
    _printCommandUsage(command.name!, parser.commands[command.name]!, stderr);
    exitCode = _exitUsage;
  } on FileSystemException catch (error) {
    stderr.writeln('[lxmusic] ${_fileSystemErrorMessage(error)}');
    exitCode = _exitNoInput;
  } on FormatException catch (error) {
    stderr.writeln('[lxmusic] Invalid input data: ${error.message}');
    exitCode = _exitDataError;
  } on TypeError catch (error) {
    stderr.writeln('[lxmusic] Invalid input or config shape: $error');
    exitCode = _exitDataError;
  } on StateError catch (error) {
    stderr.writeln('[lxmusic] Invalid input or config state: ${error.message}');
    exitCode = _exitDataError;
  } catch (error) {
    stderr.writeln('[lxmusic] Internal error: $error');
    exitCode = _exitSoftware;
  }
}

String _errorMessage(ArgumentError error) {
  return error.message?.toString() ?? error.toString();
}

String _fileSystemErrorMessage(FileSystemException error) {
  final path = error.path;
  final detail = error.osError?.message ?? error.message;
  return path == null || path.isEmpty ? detail : '$detail: $path';
}

void _runListFormats() {
  final registry = _registry();
  stdout.writeln(prettyJson(registry.supportedFormats));
}

void _runListPasses() {
  stdout.writeln(prettyJson(_transformStepTypes));
}

void _runListProfiles(ArgResults command) {
  final assets = bundledYamlAssetBundle;
  final profileRepo = YamlGameProfileRepository(assets);
  final profiles = profileRepo
      .list()
      .map((profile) => profile.toJson())
      .toList();
  stdout.writeln(prettyJson(profiles));
}

void _runValidate(ArgResults command) {
  final assets = bundledYamlAssetBundle;
  final profileRepo = YamlGameProfileRepository(assets);
  final layoutRepo = YamlLayoutRepository(assets);
  final profiles = profileRepo.list();
  final layouts = layoutRepo.list();

  stdout.writeln('[lxmusic] validating profiles and layouts...');
  stdout.writeln(
    '[lxmusic] profiles: ${profiles.length}, layouts: ${layouts.length}',
  );

  for (final profile in profiles) {
    for (final binding in profile.layouts) {
      final layout = layoutRepo.load(binding.layoutId);
      if (layout.keys.isEmpty) {
        throw StateError(
          'Layout ${layout.id} referenced by profile ${profile.id} has no keys.',
        );
      }
      for (final variant in profile.variants) {
        final playablePitchToKeyId = variant.playablePitchToKeyId(layout);
        if (playablePitchToKeyId.isEmpty) {
          throw StateError(
            'Layout ${layout.id} has no playable keys for variant '
            '${profile.id}/${variant.id}.',
          );
        }
      }
    }
  }

  stdout.writeln('[lxmusic] validation passed.');
}

void _runInspect(ArgResults command) {
  final assets = bundledYamlAssetBundle;
  final profileRepo = YamlGameProfileRepository(assets);
  final profile = profileRepo.load(command['profile'] as String);
  stdout.writeln(prettyJson(profile.toJson()));
}

void _runAnalyze(ArgResults command) {
  final inputFile = File(command['input'] as String);
  final inputFormat = _resolveInputFormat(
    command,
    bytes: inputFile.readAsBytesSync(),
  );
  final analysis = _analyzeInput(command, inputFormatId: inputFormat);
  final outputPath = command['output'] as String?;
  if (outputPath != null && outputPath.isNotEmpty) {
    _writeTextFile(outputPath, _encodeConversionConfigYaml(analysis.config));
    stderr.writeln('[lxmusic] wrote conversion config to $outputPath');
  }
  stdout.writeln(
    prettyJson(<String, Object?>{
      'analysis': analysis.analysis,
      'config': analysis.config,
    }),
  );
}

Future<void> _runConvert(ArgResults command) async {
  final assets = bundledYamlAssetBundle;
  final calibrationRepo = YamlCalibrationRepository(assets);
  final registry = _registry();
  final outputPath = _resolveConvertOutputPath(command);
  final inputFile = File(command['input'] as String);
  final inputBytes = inputFile.readAsBytesSync();
  final inputFormat = _resolveInputFormat(command, bytes: inputBytes);
  final score = registry.parse(bytes: inputBytes, formatId: inputFormat);
  stderr.writeln(
    '[lxmusic] parsed score: ${score.tracks.length} track(s), '
    '${score.totalNoteCount} note(s), ${score.totalDurationMs} ms',
  );

  final config = _resolveConversionConfig(
    command,
    inputFormatId: inputFormat,
    assets: assets,
  );
  final configOverrides = _commandOptions(command);
  _applyConfigOverrides(config, configOverrides);
  final target = _resolveTargetFromConfig(config, assets);
  _refreshConversionConfigTargetMapping(config, target);
  _applyConfigOverrides(
    config,
    configOverrides,
    markCustomTargetMappings: true,
  );
  _refreshConversionConfigTargetMapping(config, target);

  final transformSteps = _transformStepsFromConfig(config);
  final transformed = TransformPipeline(transformSteps).run(score);
  final ns = transformed.report.noteSummary!;
  stderr.writeln(
    '[lxmusic] converted score: ${transformed.score.tracks.length} track(s), '
    'steps=${transformed.report.stats.length}',
  );
  stderr.writeln(
    '[lxmusic] pipeline notes: in=${ns.inputNoteCount} out=${ns.outputNoteCount} '
    'added=${ns.pipelineNotesAdded} removed=${ns.pipelineNotesRemoved}',
  );
  _printPipelineNoteSummary(
    transformed.report.stats,
    ns.inputNoteCount,
    ns.outputNoteCount,
  );

  final semanticPlan = const PerformancePlanner().plan(
    transformed.score,
    PlanningContext(
      profile: target.profile,
      layout: target.layout,
      variant: target.variant,
      customPitchToKeyId: resolveCustomPitchToKeyId(transformSteps),
    ),
  );

  final result = <String, Object?>{
    'config': config,
    'transformReport': <String, Object?>{
      'stats': transformed.report.stats.map((stat) => stat.toJson()).toList(),
      'warnings': transformed.report.warnings,
      if (transformed.report.noteSummary != null)
        'noteSummary': transformed.report.noteSummary!.toJson(),
    },
    'semanticPlan': semanticPlan.toJson(),
  };

  final outputFormat = _resolveConvertOutputFormat(command, outputPath);

  if (outputFormat == 'executable-plan-json') {
    final deviceId = command['device'] as String;
    final orientation = command['orientation'] as String;
    final storedCalibration = calibrationRepo.load(
      CalibrationKey(
        profileId: target.profile.id,
        layoutId: target.layout.id,
        deviceId: deviceId,
      ),
    );
    final calibration = storedCalibration?.orientation == orientation
        ? storedCalibration
        : null;
    final executablePlan = const BackendCompiler().compile(
      semanticPlan,
      BackendContext(
        constraints: BackendConstraints(
          backendId: command['backend'] as String,
          supportsHold: true,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: <String>{
            'touchGesture',
            'touchPoints',
            'overlayHint',
          },
        ),
        calibration: calibration,
        layout: target.layout,
        noteDurationMode: target.variant.noteDurationMode,
      ),
    );
    result['executablePlan'] = executablePlan.toJson();
    if (calibration == null ||
        executablePlan.actions.any(
          (action) => action.kind == ExecutableActionKind.overlayHint,
        )) {
      stderr.writeln(
        '[lxmusic] warning: no executable calibration for '
        '${target.profile.id}/${target.layout.id}/$deviceId/$orientation; '
        'the plan contains overlayHint fallback and is not directly executable.',
      );
    }
  }

  switch (outputFormat) {
    case 'json':
      _writeTextOutput(
        outputPath: outputPath,
        contents: prettyJson(result),
        label: 'converted output',
      );
      return;
    case 'score-json':
      _writeTextOutput(
        outputPath: outputPath,
        contents: prettyJson(transformed.score.toJson()),
        label: 'converted score',
      );
      return;
    case 'semantic-plan-json':
      _writeTextOutput(
        outputPath: outputPath,
        contents: prettyJson(semanticPlan.toJson()),
        label: 'semantic plan',
      );
      return;
    case 'executable-plan-json':
      final executablePlan = result['executablePlan'];
      _writeTextOutput(
        outputPath: outputPath,
        contents: prettyJson(Map<String, Object?>.from(executablePlan as Map)),
        label: 'executable plan',
      );
      return;
    case 'midi':
      if (outputPath == null || outputPath.isEmpty) {
        throw ArgumentError('output-format midi requires --output.');
      }
      _writeBytesFile(
        outputPath,
        const MidiScoreEncoder().encode(transformed.score),
      );
      stderr.writeln('[lxmusic] wrote midi output to $outputPath');
      return;
    default:
      throw ArgumentError('Unsupported output format "$outputFormat".');
  }
}

String _resolveInputFormat(ArgResults command, {required Uint8List bytes}) {
  final explicit = command['format'] as String?;
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }
  final path = command['input'] as String;
  final detection = const ScoreFormatDetector().detect(
    fileName: path,
    bytes: bytes,
  );
  if (detection case DetectedScoreFormat(:final formatId)) {
    return formatId;
  }
  final rejected = detection as RejectedScoreFormat;
  throw _CliFailure(
    'Cannot detect input format for "$path": ${rejected.message}',
    exitCode: _exitDataError,
  );
}

String? _resolveConvertOutputPath(ArgResults command) {
  final explicit = command['output'] as String?;
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }
  final rest = command.rest;
  if (rest.isEmpty) {
    return null;
  }
  if (rest.length > 1) {
    throw ArgumentError(
      'convert: unexpected trailing arguments: ${rest.join(' ')}. '
      'Use at most one output path after options (or --output).',
    );
  }
  return rest.single;
}

String _resolveConvertOutputFormat(ArgResults command, String? outputPath) {
  final cli = command['output-format'] as String?;
  if (cli != null && cli.isNotEmpty) {
    return cli;
  }
  if (outputPath != null && outputPath.isNotEmpty) {
    final inferred = _inferOutputFormatFromPath(outputPath);
    if (inferred != null) {
      return inferred;
    }
  }
  return 'json';
}

String? _inferOutputFormatFromPath(String filePath) {
  final lower = filePath.toLowerCase().replaceAll('\\', '/');
  if (lower.endsWith('.mid')) {
    return 'midi';
  }
  if (lower.endsWith('.json')) {
    return 'json';
  }
  return null;
}

ParserRegistry _registry() {
  return ParserRegistry(<String, ScoreParser>{
    'domiso': DoMiSoScoreParser(),
    'json-score': const JsonScoreParser(),
    'midi': const MidiScoreParser(),
    'skystudio-json': const SkyStudioJsonScoreParser(),
    'tonejs-json': ToneJsJsonScoreParser(),
  });
}

void _printUsage(ArgParser parser, [IOSink? sink]) {
  sink ??= stdout;
  sink.writeln('LxMusic-NG CLI');
  sink.writeln();
  sink.writeln('用法: lxmusic_cli <command> [options]');
  sink.writeln();
  sink.writeln('主要命令:');
  sink.writeln('  analyze            ${_commandSummaries['analyze']}');
  sink.writeln('  convert            ${_commandSummaries['convert']}');
  sink.writeln();
  sink.writeln('辅助命令:');
  sink.writeln('  list-formats       ${_commandSummaries['list-formats']}');
  sink.writeln('  list-passes        ${_commandSummaries['list-passes']}');
  sink.writeln('  list-profiles      ${_commandSummaries['list-profiles']}');
  sink.writeln(
    '  validate-profiles  ${_commandSummaries['validate-profiles']}',
  );
  sink.writeln('  inspect-profile    ${_commandSummaries['inspect-profile']}');
  sink.writeln();
  sink.writeln('示例:');
  sink.writeln(
    '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart analyze '
    '--input examples/domiso/scale.dms.txt --format domiso --profile generic_demo',
  );
  sink.writeln(
    '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart convert '
    '--input examples/json_score/simple_score.json --format json-score '
    '--profile generic_demo --analyze '
    '--option legalizeTargetNoteRange.semiToneRoundingMode=floor '
    '--output out.json',
  );
  sink.writeln();
  sink.writeln('更多帮助:');
  sink.writeln(
    '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart <command> --help',
  );
  sink.writeln();
  sink.writeln(parser.usage);
}

void _printCommandUsage(String commandName, ArgParser parser, [IOSink? sink]) {
  sink ??= stdout;
  sink.writeln('LxMusic-NG CLI');
  sink.writeln();
  sink.writeln('$commandName: ${_commandSummaries[commandName] ?? ''}');
  sink.writeln();
  sink.writeln('用法:');
  sink.writeln(switch (commandName) {
    'analyze' =>
      '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart analyze '
          '--input <file> --profile <profile> [options]',
    'convert' =>
      '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart convert '
          '--input <file> [--config <file>] [--profile <profile>] [options]',
    'inspect-profile' =>
      '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart inspect-profile '
          '--profile <profile> [options]',
    _ =>
      '  dart run apps/lxmusic_cli/bin/lxmusic_cli.dart $commandName [options]',
  });
  sink.writeln();
  final example = _commandExample(commandName);
  if (example != null) {
    sink.writeln('示例:');
    sink.writeln('  $example');
    sink.writeln();
  }
  sink.writeln(parser.usage);
}

String? _extractCommandName(List<String> arguments, ArgParser parser) {
  for (final arg in arguments) {
    if (parser.commands.containsKey(arg)) {
      return arg;
    }
  }
  return null;
}

String? _commandExample(String commandName) {
  return switch (commandName) {
    'analyze' =>
      'dart run apps/lxmusic_cli/bin/lxmusic_cli.dart analyze '
          '--input examples/domiso/scale.dms.txt --format domiso '
          '--profile generic_demo',
    'convert' =>
      'dart run apps/lxmusic_cli/bin/lxmusic_cli.dart convert '
          '--input examples/json_score/simple_score.json --format json-score '
          '--profile generic_demo --analyze '
          '--option legalizeTargetNoteRange.semiToneRoundingMode=floor '
          '--output out.json',
    'inspect-profile' =>
      'dart run apps/lxmusic_cli/bin/lxmusic_cli.dart inspect-profile '
          '--profile generic_demo',
    'list-profiles' =>
      'dart run apps/lxmusic_cli/bin/lxmusic_cli.dart list-profiles',
    'validate-profiles' =>
      'dart run apps/lxmusic_cli/bin/lxmusic_cli.dart validate-profiles',
    _ => null,
  };
}

List<String> _commandOptions(ArgResults command) {
  final values = command['option'] as List<String>?;
  return values ?? const <String>[];
}

SemiToneRoundingMode _resolveSemiToneRoundingMode(ArgResults command) {
  for (final option in _commandOptions(command)) {
    final parsed = _parseOptionAssignment(option);
    if (parsed.path.length == 2 &&
        parsed.path[0] == 'legalizeTargetNoteRange' &&
        parsed.path[1] == 'semiToneRoundingMode') {
      return _parseSemiToneRoundingMode(parsed.rawValue);
    }
  }
  return SemiToneRoundingMode.floor;
}

void _applyConfigOverrides(
  Map<String, Object?> config,
  List<String> options, {
  bool markCustomTargetMappings = false,
}) {
  for (final option in options) {
    final parsed = _parseOptionAssignment(option);
    if (parsed.path.isEmpty) {
      throw ArgumentError('Invalid --option "$option".');
    }
    if (parsed.path.first == 'target') {
      throw ArgumentError(
        'target.* cannot be changed with --option because target-dependent '
        'analysis would become stale. Use --profile/--variant/--layout when '
        'analyzing, or update the complete conversion config.',
      );
    }
    if (_overridesTargetMappingMetadata(
      parsed.path.first,
      parsed.path.skip(1),
    )) {
      throw ArgumentError(
        '${parsed.path.first}.${parsed.path[1]} is internal target-mapping '
        'metadata and cannot be changed with --option.',
      );
    }
    if (_topLevelConfigKeys.contains(parsed.path.first)) {
      _setNestedConfigValue(
        config,
        parsed.path,
        _parseOptionValue(parsed.rawValue),
      );
      continue;
    }
    _setPipelineStepConfigValue(
      config,
      stepType: parsed.path.first,
      path: parsed.path.skip(1).toList(),
      value: _parseOptionValue(parsed.rawValue),
    );
    if (markCustomTargetMappings &&
        _overridesTargetMapping(parsed.path.first, parsed.path.skip(1))) {
      _markPipelineTargetMappingsCustom(config);
    }
  }
}

bool _overridesTargetMappingMetadata(String stepType, Iterable<String> path) {
  final fields = path.toList();
  if (fields.isEmpty ||
      (stepType != 'legalizeTargetNoteRange' && stepType != 'noteToKey')) {
    return false;
  }
  return fields.first == 'mappingMode' ||
      fields.first == 'mappingSemanticsVersion';
}

bool _overridesTargetMapping(String stepType, Iterable<String> path) {
  final field = path.first;
  return switch (stepType) {
    'legalizeTargetNoteRange' =>
      field == 'supportedPitches' || field == 'wrapPitchRange',
    'noteToKey' => field == 'pitchToKeyId',
    _ => false,
  };
}

void _markPipelineTargetMappingsCustom(Map<String, Object?> config) {
  final pipeline = Map<String, Object?>.from(
    config['pipeline'] as Map? ?? const <String, Object?>{},
  );
  config['pipeline'] = pipeline;
  final steps = (pipeline['steps'] as List<Object?>? ?? const <Object?>[])
      .map((item) => Map<String, Object?>.from(item! as Map))
      .toList();
  pipeline['steps'] = steps;
  for (final step in steps) {
    final type = step['type'];
    if (type != 'legalizeTargetNoteRange' && type != 'noteToKey') {
      continue;
    }
    final stepConfig = Map<String, Object?>.from(
      step['config'] as Map? ?? const <String, Object?>{},
    );
    stepConfig['mappingMode'] = customTargetMappingMode;
    step['config'] = stepConfig;
  }
}

({List<String> path, String rawValue}) _parseOptionAssignment(String input) {
  final index = input.indexOf('=');
  if (index <= 0 || index == input.length - 1) {
    throw ArgumentError(
      'Invalid --option "$input". Expected dotted.path=value.',
    );
  }
  final key = input.substring(0, index).trim();
  final value = input.substring(index + 1).trim();
  final path = key
      .split('.')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (path.isEmpty) {
    throw ArgumentError(
      'Invalid --option "$input". Expected dotted.path=value.',
    );
  }
  return (path: path, rawValue: value);
}

Object? _parseOptionValue(String raw) {
  if (raw == 'true') {
    return true;
  }
  if (raw == 'false') {
    return false;
  }
  if (raw == 'null') {
    return null;
  }
  final asInt = int.tryParse(raw);
  if (asInt != null) {
    return asInt;
  }
  final asDouble = double.tryParse(raw);
  if (asDouble != null) {
    return asDouble;
  }
  if ((raw.startsWith('{') && raw.endsWith('}')) ||
      (raw.startsWith('[') && raw.endsWith(']'))) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      throw ArgumentError('Invalid JSON option value: ${error.message}');
    }
  }
  return raw;
}

void _setNestedConfigValue(
  Map<String, Object?> root,
  List<String> path,
  Object? value,
) {
  if (path.isEmpty) {
    throw ArgumentError('Config override path must not be empty.');
  }
  Map<String, Object?> current = root;
  for (final key in path.take(path.length - 1)) {
    final next = current[key];
    if (next is Map<String, Object?>) {
      current = next;
      continue;
    }
    if (next is Map) {
      current[key] = Map<String, Object?>.from(next);
      current = current[key] as Map<String, Object?>;
      continue;
    }
    final created = <String, Object?>{};
    current[key] = created;
    current = created;
  }
  current[path.last] = value;
}

void _setPipelineStepConfigValue(
  Map<String, Object?> config, {
  required String stepType,
  required List<String> path,
  required Object? value,
}) {
  if (path.isEmpty) {
    throw ArgumentError(
      'Pipeline step override "$stepType" requires a config path after the step type.',
    );
  }
  final pipeline = Map<String, Object?>.from(
    config['pipeline'] as Map? ?? const <String, Object?>{},
  );
  config['pipeline'] = pipeline;
  final steps = (pipeline['steps'] as List<Object?>? ?? const <Object?>[])
      .map((item) => Map<String, Object?>.from(item! as Map))
      .toList();
  pipeline['steps'] = steps;

  Map<String, Object?>? matched;
  for (final step in steps) {
    if (step['type'] == stepType) {
      matched = step;
      break;
    }
  }
  if (matched == null) {
    throw ArgumentError('Pipeline step "$stepType" not found in config.');
  }

  final stepConfig = Map<String, Object?>.from(
    matched['config'] as Map? ?? const <String, Object?>{},
  );
  matched['config'] = stepConfig;
  _setNestedConfigValue(stepConfig, path, value);
}

Map<String, Object?> _resolveConversionConfig(
  ArgResults command, {
  required String inputFormatId,
  required YamlAssetBundle assets,
}) {
  final configPath = command['config'] as String?;
  if (configPath == null || configPath.isEmpty) {
    return _analyzeInput(command, inputFormatId: inputFormatId).config;
  }
  if (command['analyze'] as bool) {
    throw ArgumentError(
      '--analyze and --config are mutually exclusive. Remove --config to '
      'generate a fresh configuration.',
    );
  }

  return _normalizeLoadedConversionConfig(
    _loadConversionConfig(configPath),
    command: command,
    assets: assets,
  );
}

Map<String, Object?> _normalizeLoadedConversionConfig(
  Map<String, Object?> loaded, {
  required ArgResults command,
  required YamlAssetBundle assets,
}) {
  final config = Map<String, Object?>.from(loaded);
  final rawPipeline = config['pipeline'];
  if (rawPipeline != null && config.containsKey('steps')) {
    throw const _CliFailure(
      'Conversion config cannot contain both "pipeline" and top-level "steps".',
      exitCode: _exitDataError,
    );
  }
  if (rawPipeline == null && config.containsKey('steps')) {
    config['pipeline'] = <String, Object?>{'steps': config.remove('steps')};
  } else if (rawPipeline is Map) {
    config['pipeline'] = Map<String, Object?>.from(rawPipeline);
  } else if (rawPipeline == null) {
    throw const _CliFailure(
      'Conversion config must contain pipeline.steps or top-level steps.',
      exitCode: _exitDataError,
    );
  } else {
    throw const _CliFailure(
      'Conversion config field "pipeline" must be a mapping.',
      exitCode: _exitDataError,
    );
  }

  // Validate the pipeline shape before resolving or refreshing target data.
  _transformStepsFromConfig(config);

  if (config['target'] == null) {
    final target = _resolveAnalysisTargetFromArgs(command);
    config['target'] = <String, Object?>{
      'profileId': target.profile.id,
      'variantId': target.variant.id,
      'layoutId': target.layout.id,
    };
  } else {
    final target = _resolveTargetFromConfig(config, assets);
    _validateExplicitTargetArgs(command, target);
    if (command.wasParsed('track-disable-threshold')) {
      throw ArgumentError(
        '--track-disable-threshold only applies when generating a fresh '
        'analysis config.',
      );
    }
  }

  config['version'] ??= variantMappingSemanticsVersion;
  return config;
}

void _validateExplicitTargetArgs(
  ArgResults command,
  ({GameProfile profile, InstrumentVariant variant, KeyLayout layout}) target,
) {
  final expected = <String, String>{
    'profile': target.profile.id,
    'variant': target.variant.id,
    'layout': target.layout.id,
  };
  for (final entry in expected.entries) {
    if (!command.wasParsed(entry.key)) {
      continue;
    }
    final actual = command[entry.key] as String?;
    if (actual != entry.value) {
      throw ArgumentError(
        '--${entry.key}=$actual conflicts with config target '
        '${entry.key}=${entry.value}.',
      );
    }
  }
}

({Map<String, Object?> analysis, Map<String, Object?> config}) _analyzeInput(
  ArgResults command, {
  required String inputFormatId,
}) {
  final registry = _registry();
  final target = _resolveAnalysisTargetFromArgs(command);
  final inputFile = File(command['input'] as String);
  final score = registry.parse(
    bytes: inputFile.readAsBytesSync(),
    formatId: inputFormatId,
  );
  final roundingMode = _resolveSemiToneRoundingMode(command);
  final analysis = analyzeScoreForTarget(
    score,
    target: target,
    roundingMode: roundingMode,
    trackDisableThreshold: _parseTrackDisableThreshold(command),
  );
  final config = analysis.toConfigJson(roundingMode: roundingMode);
  final configOverrides = _commandOptions(command);
  _applyConfigOverrides(config, configOverrides);
  final configuredTarget = _resolveTargetFromConfig(
    config,
    bundledYamlAssetBundle,
  );
  _refreshConversionConfigTargetMapping(config, configuredTarget);
  _applyConfigOverrides(
    config,
    configOverrides,
    markCustomTargetMappings: true,
  );
  _refreshConversionConfigTargetMapping(config, configuredTarget);

  return (analysis: analysis.toAnalysisJson(), config: config);
}

double _parseTrackDisableThreshold(ArgResults command) {
  final raw = command['track-disable-threshold'] as String? ?? '0.5';
  final value = double.tryParse(raw);
  if (value == null || value < 0 || value > 1) {
    throw ArgumentError(
      'track-disable-threshold must be a number between 0 and 1.',
    );
  }
  return value;
}

AnalysisTarget _resolveAnalysisTargetFromArgs(ArgResults command) {
  final assets = bundledYamlAssetBundle;
  final profileRepo = YamlGameProfileRepository(assets);
  final layoutRepo = YamlLayoutRepository(assets);
  final profileId = command['profile'] as String?;
  if (profileId == null || profileId.isEmpty) {
    throw ArgumentError(
      '--profile is required when analyzing or using a pipeline-only config.',
    );
  }
  final profile = profileRepo.load(profileId);
  final variantId = command['variant'] as String? ?? 'default';
  final variant = profile.variantById(variantId);
  if (variant == null) {
    throw ArgumentError(
      'Variant "$variantId" not found in profile ${profile.id}.',
    );
  }
  final layoutId =
      (command['layout'] as String?) ??
      profile.defaultLayoutId ??
      profile.layouts.first.layoutId;
  final layout = layoutRepo.load(layoutId);
  return AnalysisTarget(profile: profile, variant: variant, layout: layout);
}

({GameProfile profile, InstrumentVariant variant, KeyLayout layout})
_resolveTargetFromConfig(Map<String, Object?> config, YamlAssetBundle assets) {
  final profileRepo = YamlGameProfileRepository(assets);
  final layoutRepo = YamlLayoutRepository(assets);
  final rawTarget = config['target'];
  if (rawTarget is! Map) {
    throw const _CliFailure(
      'Conversion config field "target" must be a mapping.',
      exitCode: _exitDataError,
    );
  }
  final target = Map<String, Object?>.from(rawTarget);
  final profileId = target['profileId'];
  final variantId = target['variantId'];
  final layoutId = target['layoutId'];
  if (profileId is! String ||
      profileId.isEmpty ||
      variantId is! String ||
      variantId.isEmpty ||
      layoutId is! String ||
      layoutId.isEmpty) {
    throw const _CliFailure(
      'Conversion config target requires non-empty profileId, variantId, '
      'and layoutId strings.',
      exitCode: _exitDataError,
    );
  }

  try {
    final profile = profileRepo.load(profileId);
    final variant = profile.variantById(variantId);
    if (variant == null) {
      throw ArgumentError(
        'Variant "$variantId" not found in profile ${profile.id}.',
      );
    }
    final layout = layoutRepo.load(layoutId);
    return (profile: profile, variant: variant, layout: layout);
  } on ArgumentError catch (error) {
    throw _CliFailure(
      'Invalid conversion config target: ${_errorMessage(error)}',
      exitCode: _exitDataError,
    );
  }
}

List<TransformStep> _transformStepsFromConfig(Map<String, Object?> config) {
  final rawPipeline = config['pipeline'];
  if (rawPipeline is! Map) {
    throw const _CliFailure(
      'Conversion config field "pipeline" must be a mapping.',
      exitCode: _exitDataError,
    );
  }
  final pipeline = Map<String, Object?>.from(rawPipeline);
  final rawSteps = pipeline['steps'];
  if (rawSteps is! List) {
    throw const _CliFailure(
      'Conversion config field "pipeline.steps" must be a list.',
      exitCode: _exitDataError,
    );
  }

  final steps = <TransformStep>[];
  for (var index = 0; index < rawSteps.length; index++) {
    final rawStep = rawSteps[index];
    if (rawStep is! Map) {
      throw _CliFailure(
        'Conversion config pipeline.steps[$index] must be a mapping.',
        exitCode: _exitDataError,
      );
    }
    final step = Map<String, Object?>.from(rawStep);
    final type = step['type'];
    final rawConfig = step['config'];
    if (type is! String || type.isEmpty) {
      throw _CliFailure(
        'Conversion config pipeline.steps[$index].type must be a '
        'non-empty string.',
        exitCode: _exitDataError,
      );
    }
    if (!_transformStepTypes.contains(type)) {
      throw _CliFailure(
        'Conversion config pipeline.steps[$index] has unknown type "$type".',
        exitCode: _exitDataError,
      );
    }
    if (rawConfig != null && rawConfig is! Map) {
      throw _CliFailure(
        'Conversion config pipeline.steps[$index].config must be a mapping.',
        exitCode: _exitDataError,
      );
    }
    steps.add(
      TransformStep(
        type: type,
        config: Map<String, Object?>.from(
          rawConfig as Map? ?? const <String, Object?>{},
        ),
      ),
    );
  }
  return steps;
}

void _refreshConversionConfigTargetMapping(
  Map<String, Object?> config,
  ({GameProfile profile, InstrumentVariant variant, KeyLayout layout}) target,
) {
  final refreshed = refreshTargetMappingSteps(
    steps: _transformStepsFromConfig(config),
    target: AnalysisTarget(
      profile: target.profile,
      variant: target.variant,
      layout: target.layout,
    ),
  );
  if (!refreshed.changed) {
    return;
  }

  final pipeline = Map<String, Object?>.from(config['pipeline'] as Map);
  pipeline['steps'] = refreshed.steps
      .map(
        (step) => <String, Object?>{'type': step.type, 'config': step.config},
      )
      .toList();
  config['pipeline'] = pipeline;
  config['version'] = variantMappingSemanticsVersion;
}

Map<String, Object?> _loadConversionConfig(String path) {
  final yaml = loadYaml(File(path).readAsStringSync());
  if (yaml is! YamlMap) {
    throw const _CliFailure(
      'Conversion config root must be a YAML mapping.',
      exitCode: _exitDataError,
    );
  }
  return _yamlToObjectMap(yaml);
}

Map<String, Object?> _yamlToObjectMap(YamlMap yaml) {
  return Map<String, Object?>.fromEntries(
    yaml.entries.map(
      (entry) =>
          MapEntry(entry.key.toString(), _yamlValueToObject(entry.value)),
    ),
  );
}

Object? _yamlValueToObject(Object? value) {
  if (value is YamlMap) {
    return _yamlToObjectMap(value);
  }
  if (value is YamlList) {
    return value.map(_yamlValueToObject).toList();
  }
  return value;
}

SemiToneRoundingMode _parseSemiToneRoundingMode(String value) {
  return SemiToneRoundingMode.values.byName(value);
}

String _encodeConversionConfigYaml(Map<String, Object?> config) {
  final buffer = StringBuffer();
  _writeYamlValue(buffer, config, 0);
  return buffer.toString();
}

void _writeYamlValue(StringBuffer buffer, Object? value, int indent) {
  final prefix = '  ' * indent;
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (entry.value is Map || entry.value is List) {
        buffer.writeln('$prefix${entry.key}:');
        _writeYamlValue(buffer, entry.value, indent + 1);
      } else {
        buffer.writeln('$prefix${entry.key}: ${_yamlScalar(entry.value)}');
      }
    }
    return;
  }
  if (value is List<Object?>) {
    for (final item in value) {
      if (item is Map<String, Object?>) {
        buffer.writeln('$prefix-');
        _writeYamlValue(buffer, item, indent + 1);
      } else if (item is List<Object?>) {
        buffer.writeln('$prefix-');
        _writeYamlValue(buffer, item, indent + 1);
      } else {
        buffer.writeln('$prefix- ${_yamlScalar(item)}');
      }
    }
    return;
  }
  buffer.writeln('$prefix${_yamlScalar(value)}');
}

String _yamlScalar(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  final text = value.toString().replaceAll("'", "''");
  return "'$text'";
}

void _printPipelineNoteSummary(
  List<PassStat> stats,
  int inputNoteCount,
  int outputNoteCount,
) {
  T? getStat<T>(String passName, String key) {
    for (final s in stats) {
      if (s.name == passName) {
        return s.values[key] as T?;
      }
    }
    return null;
  }

  String pct(int count, int total) =>
      total > 0 ? (count / total * 100).toStringAsFixed(2) : '0.00';

  final overFlowed =
      getStat<int>('LegalizeTargetNoteRangePass', 'overFlowedNoteCount') ?? 0;
  final underFlowed =
      getStat<int>('LegalizeTargetNoteRangePass', 'underFlowedNoteCount') ?? 0;
  final rounded =
      getStat<int>('LegalizeTargetNoteRangePass', 'roundedNoteCount') ?? 0;
  final droppedFreq =
      getStat<int>('SingleKeyFrequencyLimitPass', 'droppedNoteCount') ?? 0;
  final droppedSame =
      getStat<int>('MergeNearbyNotesPass', 'droppedSameNoteCount') ?? 0;
  final outRanged = overFlowed + underFlowed;
  final dropped = droppedFreq + droppedSame;

  stderr.writeln('[lxmusic] note summary:');
  stderr.writeln('[lxmusic]   total: $inputNoteCount -> $outputNoteCount');
  stderr.writeln(
    '[lxmusic]   out-of-range discarded: $outRanged '
    '(+$overFlowed, -$underFlowed) (${pct(outRanged, inputNoteCount)}%)',
  );
  stderr.writeln(
    '[lxmusic]   semitone-rounded: $rounded (${pct(rounded, inputNoteCount)}%)',
  );
  stderr.writeln(
    '[lxmusic]   too-dense discarded: $dropped (${pct(dropped, outputNoteCount)}%)',
  );
}

void _writeTextOutput({
  required String? outputPath,
  required String contents,
  required String label,
}) {
  if (outputPath != null && outputPath.isNotEmpty) {
    _writeTextFile(outputPath, contents);
    stderr.writeln('[lxmusic] wrote $label to $outputPath');
    return;
  }
  stdout.writeln(contents);
}

void _writeTextFile(String path, String contents) {
  try {
    File(path).writeAsStringSync(contents);
  } on FileSystemException catch (error) {
    throw _CliFailure(
      'Cannot create output: ${_fileSystemErrorMessage(error)}',
      exitCode: _exitCannotCreate,
    );
  }
}

void _writeBytesFile(String path, List<int> contents) {
  try {
    File(path).writeAsBytesSync(contents);
  } on FileSystemException catch (error) {
    throw _CliFailure(
      'Cannot create output: ${_fileSystemErrorMessage(error)}',
      exitCode: _exitCannotCreate,
    );
  }
}
