import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../library/models/music_file.dart';
import '../../library/services/song_export_service.dart';
import '../../workbench/models/song_config.dart';
import '../models/game_player_snapshot.dart';

final gamePlaybackPlanServiceProvider = Provider<GamePlaybackPlanService>((
  ref,
) {
  return DefaultGamePlaybackPlanService(
    songExportService: ref.watch(songExportServiceProvider),
  );
});

String gamePlaybackCacheKey({
  required MusicFile file,
  required GameProfile profile,
  required InstrumentVariant variant,
  required KeyLayout layout,
  required SongConfig config,
  int additionalPitchOffset = 0,
  GamePlayerDurationMode durationMode = GamePlayerDurationMode.shortPress,
}) {
  return <String>[
    file.path,
    profile.id,
    variant.id,
    layout.id,
    additionalPitchOffset.toString(),
    durationMode.name,
    jsonEncode(_canonicalJsonValue(config.toJson())),
  ].join('|');
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return value;
}

class PreparedGamePlayback {
  const PreparedGamePlayback({
    required this.fileName,
    required this.cacheKey,
    required this.config,
    required this.executablePlan,
    required this.orientation,
    required this.targetPackageName,
    required this.physicalWidthPx,
    required this.physicalHeightPx,
    required this.displayRotation,
    required this.viewportPx,
    this.tapDurationMs = 12,
  });

  final String fileName;
  final String cacheKey;
  final SongConfig config;
  final ExecutablePlan executablePlan;
  final String orientation;
  final String? targetPackageName;
  final int physicalWidthPx;
  final int physicalHeightPx;
  final int displayRotation;
  final ({double left, double top, double right, double bottom}) viewportPx;
  final int tapDurationMs;
}

abstract interface class GamePlaybackPlanService {
  Future<PreparedGamePlayback> prepare({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    int additionalPitchOffset = 0,
    GamePlayerDurationMode durationMode = GamePlayerDurationMode.shortPress,
  });
}

class DefaultGamePlaybackPlanService implements GamePlaybackPlanService {
  const DefaultGamePlaybackPlanService({required this.songExportService});

  final SongExportService songExportService;

  @override
  Future<PreparedGamePlayback> prepare({
    required MusicFile file,
    required GameProfile profile,
    required InstrumentVariant variant,
    required KeyLayout layout,
    int additionalPitchOffset = 0,
    GamePlayerDurationMode durationMode = GamePlayerDurationMode.shortPress,
  }) async {
    final prepared = await songExportService.prepareExecutablePlan(
      file: file,
      profile: profile,
      variant: variant,
      layout: layout,
      tapOnly: durationMode != GamePlayerDurationMode.longPress,
      repeatLongNotes: durationMode == GamePlayerDurationMode.repeatedTap,
      noteDurationModeOverride: durationMode == GamePlayerDurationMode.longPress
          ? NoteDurationMode.nativeHold
          : null,
      additionalPitchOffset: additionalPitchOffset,
    );
    final calibratedPackage =
        prepared.calibration.metadata['foregroundPackage'] as String?;
    final normalizedPackage = calibratedPackage?.trim();
    final targetPackageName =
        normalizedPackage == null || normalizedPackage.isEmpty
        ? null
        : normalizedPackage;
    final physicalWidthPx =
        (prepared.calibration.metadata['physicalWidthPx'] as num?)?.toInt();
    final physicalHeightPx =
        (prepared.calibration.metadata['physicalHeightPx'] as num?)?.toInt();
    final displayRotation =
        (prepared.calibration.metadata['displayRotation'] as num?)?.toInt();
    final viewportPx = prepared.calibration.viewportPx;
    if (physicalWidthPx == null ||
        physicalWidthPx <= 0 ||
        physicalHeightPx == null ||
        physicalHeightPx <= 0 ||
        displayRotation == null ||
        !const <int>{0, 1, 2, 3}.contains(displayRotation) ||
        viewportPx == null) {
      throw StateError('当前键位校准缺少屏幕参数，请重新校准。');
    }
    return PreparedGamePlayback(
      fileName: file.fileName,
      cacheKey: gamePlaybackCacheKey(
        file: file,
        profile: profile,
        variant: variant,
        layout: layout,
        config: prepared.config,
        additionalPitchOffset: additionalPitchOffset,
        durationMode: durationMode,
      ),
      config: prepared.config,
      executablePlan: prepared.executablePlan,
      orientation: prepared.calibration.orientation,
      targetPackageName: targetPackageName,
      physicalWidthPx: physicalWidthPx,
      physicalHeightPx: physicalHeightPx,
      displayRotation: displayRotation,
      viewportPx: viewportPx,
    );
  }
}
