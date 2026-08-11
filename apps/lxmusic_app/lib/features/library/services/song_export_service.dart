import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../../core/service_locator.dart';
import '../../../core/platform/file_store.dart';
import '../../calibration/platform/calibration_platform.dart';
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

class PreparedExecutableSongPlan {
  const PreparedExecutableSongPlan({
    required this.config,
    required this.semanticPlan,
    required this.executablePlan,
    required this.calibration,
  });

  final SongConfig config;
  final SemanticPlan semanticPlan;
  final ExecutablePlan executablePlan;
  final Calibration calibration;
}

final songExportServiceProvider = Provider<SongExportService>((ref) {
  return SongExportService(
    songConfigService: ref.watch(songConfigServiceProvider),
    calibrationRepository: ref.watch(calibrationRepositoryProvider),
    calibrationPlatform: ref.watch(calibrationPlatformProvider),
    fileStore: ref.watch(fileStoreProvider),
  );
});

class SongExportService {
  const SongExportService({
    required this.songConfigService,
    required this.calibrationRepository,
    required this.calibrationPlatform,
    required this.fileStore,
  });

  final SongConfigService songConfigService;
  final CalibrationRepository calibrationRepository;
  final CalibrationPlatform calibrationPlatform;
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

    if (format == ExportFormat.executablePlanJson) {
      final prepared = await prepareExecutablePlan(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
      );
      return PreparedSongExport(
        format: format,
        fileName:
            '${_outputBaseName(file.fileName, profile, variant, layout)}.${format.extension}',
        bytes: Uint8List.fromList(
          prettyJson(prepared.executablePlan.toJson()).codeUnits,
        ),
        config: prepared.config,
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
        throw StateError('executable plan should be handled before parsing.');
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

  Future<PreparedExecutableSongPlan> prepareExecutablePlan({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    bool tapOnly = false,
    bool repeatLongNotes = false,
    NoteDurationMode? noteDurationModeOverride,
    int additionalPitchOffset = 0,
  }) async {
    final config = await songConfigService.ensureForTarget(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
    );
    final score = await songConfigService.parseFile(file);
    var executionSteps = additionalPitchOffset == 0
        ? config.steps
        : upsertRecommendedTransformStep(
            config.steps,
            TransformStep(
              type: 'pitchOffset',
              config: <String, Object?>{
                'offset': config.pitchOffset + additionalPitchOffset,
              },
            ),
          );
    if (repeatLongNotes) {
      executionSteps = upsertRecommendedTransformStep(
        executionSteps,
        const TransformStep(
          type: 'splitLongNote',
          config: <String, Object?>{
            'minDurationMs': 500,
            'splitDurationMs': 100,
          },
        ),
      );
    }
    final transformed = TransformPipeline(executionSteps).run(score);
    final platformState = await calibrationPlatform.getState();
    if (!platformState.canCalibrate) {
      throw const CalibrationUnavailableException('当前平台无法获取 Android 设备校准信息。');
    }
    final targetOrientation = platformState.targetOrientation;
    if (targetOrientation == null ||
        platformState.targetProfileId != profile.id ||
        platformState.targetLayoutId != layout.id) {
      throw TargetOrientationUnavailableException(
        profileId: profile.id,
        layoutId: layout.id,
      );
    }
    final calibrationKey = CalibrationKey(
      profileId: profile.id,
      layoutId: layout.id,
      deviceId: platformState.deviceId,
    );
    final calibration = calibrationRepository.load(calibrationKey);
    if (calibration == null) {
      throw MissingCalibrationException(calibrationKey);
    }
    if (calibration.orientation != targetOrientation) {
      throw CalibrationOrientationMismatchException(
        key: calibrationKey,
        calibrationOrientation: calibration.orientation,
        targetOrientation: targetOrientation,
      );
    }
    final semanticPlan = const PerformancePlanner().plan(
      transformed.score,
      PlanningContext(
        profile: profile,
        layout: layout,
        variant: variant,
        customPitchToKeyId: resolveCustomPitchToKeyId(executionSteps),
      ),
    );
    final executablePlan = const BackendCompiler().compile(
      semanticPlan,
      BackendContext(
        constraints: BackendConstraints(
          backendId: 'android-accessibility',
          supportsHold: !tapOnly,
          maxSimultaneousTouches: 5,
          minTapGapMs: 8,
          gestureBatchWindowMs: 32,
          supportedKinds: tapOnly
              ? const <String>{'touchPoints'}
              : const <String>{'touchGesture', 'touchPoints'},
          pressDurationMs: tapOnly ? 30 : 5,
        ),
        calibration: calibration,
        layout: layout,
        noteDurationMode: tapOnly
            ? NoteDurationMode.none
            : noteDurationModeOverride ?? variant.noteDurationMode,
      ),
    );
    return PreparedExecutableSongPlan(
      config: config,
      semanticPlan: semanticPlan,
      executablePlan: executablePlan,
      calibration: calibration,
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

abstract class CalibrationExportException implements Exception {
  const CalibrationExportException();

  String get profileId;
  String get layoutId;
}

class MissingCalibrationException extends CalibrationExportException {
  const MissingCalibrationException(this.key);

  final CalibrationKey key;

  @override
  String get profileId => key.profileId;

  @override
  String get layoutId => key.layoutId;

  @override
  String toString() => '当前设备缺少 ${key.profileId} / ${key.layoutId} 的键位校准。';
}

class CalibrationOrientationMismatchException
    extends CalibrationExportException {
  const CalibrationOrientationMismatchException({
    required this.key,
    required this.calibrationOrientation,
    required this.targetOrientation,
  });

  final CalibrationKey key;
  final String calibrationOrientation;
  final String targetOrientation;

  @override
  String get profileId => key.profileId;

  @override
  String get layoutId => key.layoutId;

  @override
  String toString() {
    final calibrated = calibrationOrientation == 'landscape' ? '横屏' : '竖屏';
    final current = targetOrientation == 'landscape' ? '横屏' : '竖屏';
    return '当前键位上次在$calibrated下校准，目标游戏现为$current。'
        '请重新校准，新结果会覆盖旧校准。';
  }
}

class TargetOrientationUnavailableException extends CalibrationExportException {
  const TargetOrientationUnavailableException({
    required this.profileId,
    required this.layoutId,
  });

  @override
  final String profileId;

  @override
  final String layoutId;

  @override
  String toString() => '还没有从目标游戏内确认横竖屏方向，请先完成一次键位校准。';
}

class CalibrationUnavailableException implements Exception {
  const CalibrationUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
