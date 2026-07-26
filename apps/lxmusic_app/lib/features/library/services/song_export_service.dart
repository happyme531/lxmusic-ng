import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../core/service_locator.dart';
import '../../../core/platform/file_store.dart';
import '../../workbench/models/song_config.dart';
import '../../workbench/services/song_config_service.dart';
import '../models/music_file.dart';

enum ExportFormat { midi, executablePlanJson, originalFile }

extension ExportFormatLabel on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.midi:
        return '导出为 MIDI';
      case ExportFormat.executablePlanJson:
        return '导出为 executable-plan-json';
      case ExportFormat.originalFile:
        return '导出原文件';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.midi:
        return 'mid';
      case ExportFormat.executablePlanJson:
        return 'json';
      case ExportFormat.originalFile:
        return 'bin';
    }
  }
}

class PreparedSongExport {
  const PreparedSongExport({
    required this.format,
    required this.fileName,
    required this.bytes,
    this.config,
  });

  final ExportFormat format;
  final String fileName;
  final Uint8List bytes;
  final SongConfig? config;
}

final songExportServiceProvider = Provider<SongExportService>((ref) {
  return SongExportService(
    songConfigService: ref.watch(songConfigServiceProvider),
    calibrationRepository: ref.watch(calibrationRepositoryProvider),
    fileStore: ref.watch(fileStoreProvider),
  );
});

class SongExportService {
  const SongExportService({
    required this.songConfigService,
    required this.calibrationRepository,
    required this.fileStore,
  });

  final SongConfigService songConfigService;
  final CalibrationRepository calibrationRepository;
  final PlatformFileStore fileStore;

  Future<PreparedSongExport> prepareExport({
    required MusicFile file,
    required ExportFormat format,
    GameProfile? profile,
    InstrumentVariant? variant,
    KeyLayout? layout,
  }) async {
    if (format == ExportFormat.originalFile) {
      return PreparedSongExport(
        format: format,
        fileName: file.fileName,
        bytes: await fileStore.readBytes(file.path),
      );
    }

    if (profile == null || variant == null || layout == null) {
      throw ArgumentError(
        'profile, variant and layout are required for optimized exports.',
      );
    }

    final config = await songConfigService.ensureForTarget(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
    );
    final score = await songConfigService.parseFile(file);
    final transformed = TransformPipeline(config.steps).run(score);
    final fileName =
        '${_outputBaseName(file.fileName, profile, variant, layout)}.${format.extension}';
    late final Uint8List bytes;

    switch (format) {
      case ExportFormat.midi:
        bytes = const MidiScoreEncoder().encode(transformed.score);
        break;
      case ExportFormat.executablePlanJson:
        final semanticPlan = const PerformancePlanner().plan(
          transformed.score,
          PlanningContext(
            profile: profile,
            layout: layout,
            variant: variant,
            customPitchToKeyId: resolveCustomPitchToKeyId(config.steps),
          ),
        );
        final calibration = calibrationRepository.load(
          CalibrationKey(
            profileId: profile.id,
            layoutId: layout.id,
            deviceId: 'default-device',
            orientation: 'portrait',
          ),
        );
        final executablePlan = const BackendCompiler().compile(
          semanticPlan,
          BackendContext(
            constraints: const BackendConstraints(
              backendId: 'preview',
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
            layout: layout,
            noteDurationMode: variant.noteDurationMode,
          ),
        );
        bytes = Uint8List.fromList(
          prettyJson(executablePlan.toJson()).codeUnits,
        );
        break;
      case ExportFormat.originalFile:
        throw StateError('originalFile should be handled before optimization.');
    }

    return PreparedSongExport(
      format: format,
      fileName: fileName,
      bytes: bytes,
      config: config,
    );
  }

  Future<List<String>> writePreparedExportsToDirectory({
    required List<PreparedSongExport> exports,
    required String directoryPath,
  }) async {
    final writtenPaths = <String>[];
    for (final prepared in exports) {
      final targetPath = await _resolveUniqueOutputPath(
        directoryPath,
        prepared.fileName,
      );
      await fileStore.writeBytes(targetPath, prepared.bytes);
      writtenPaths.add(targetPath);
    }
    return writtenPaths;
  }

  String _outputBaseName(
    String fileName,
    GameProfile profile,
    InstrumentVariant variant,
    KeyLayout layout,
  ) {
    final dot = fileName.lastIndexOf('.');
    final baseName = dot >= 0 ? fileName.substring(0, dot) : fileName;
    return [
      _sanitizePathSegment(baseName),
      _sanitizePathSegment(profile.id),
      _sanitizePathSegment(variant.id),
      _sanitizePathSegment(layout.id),
    ].join('__');
  }

  String _sanitizePathSegment(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<String> _resolveUniqueOutputPath(
    String directoryPath,
    String fileName,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final baseName = dot >= 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot >= 0 ? fileName.substring(dot) : '';
    var candidate = '$directoryPath/$fileName';
    var index = 2;
    while (await fileStore.exists(candidate)) {
      candidate = '$directoryPath/$baseName ($index)$extension';
      index++;
    }
    return candidate;
  }
}
