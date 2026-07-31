import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/features/calibration/platform/calibration_platform.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/library/services/song_export_service.dart';
import 'package:lxmusic_app/features/workbench/services/song_config_service.dart';
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const layout = KeyLayout(
    id: 'layout',
    algorithm: LayoutAlgorithm.explicit,
    keys: <KeyDefinition>[
      KeyDefinition(id: 'C4', pitch: 60, normX: 0.5, normY: 0.5),
    ],
    pitchToKeyId: <int, String>{60: 'C4'},
  );
  const variant = InstrumentVariant(
    id: 'default',
    displayName: '默认',
    noteDurationMode: NoteDurationMode.none,
  );
  const profile = GameProfile(
    id: 'profile',
    displayName: '测试游戏',
    packageNameHints: <String>[],
    layouts: <LayoutBinding>[
      LayoutBinding(layoutId: 'layout', displayName: '测试布局'),
    ],
    variants: <InstrumentVariant>[variant],
    sameKeyMinIntervalMs: 20,
  );
  final file = MusicFile(
    path: '/test/song.fake',
    fileName: 'song.fake',
    formatId: 'fake',
  );
  const platformState = CalibrationPlatformState(
    supported: true,
    accessibilityEnabled: true,
    apiLevel: 36,
    deviceId: 'android-test',
    deviceDisplayName: 'Android Test',
    viewportWidthPx: 100,
    viewportHeightPx: 200,
    density: 1,
    displayRotation: 0,
    targetOrientation: 'portrait',
    targetProfileId: 'profile',
    targetLayoutId: 'layout',
  );
  const calibrationKey = CalibrationKey(
    profileId: 'profile',
    layoutId: 'layout',
    deviceId: 'android-test',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  SongExportService buildService(Calibration? calibration) {
    final fileStore = _MemoryFileStore();
    return SongExportService(
      songConfigService: SongConfigService(
        parserRegistry: ParserRegistry(<String, ScoreParser>{
          'fake': const _FakeScoreParser(),
        }),
        configStore: const SongConfigStore(),
        fileStore: fileStore,
      ),
      calibrationRepository: _MemoryCalibrationRepository(calibration),
      calibrationPlatform: const _FakeCalibrationPlatform(platformState),
      fileStore: fileStore,
    );
  }

  test('missing current device calibration blocks executable export', () async {
    final service = buildService(null);

    await expectLater(
      service.prepareExport(
        file: file,
        format: ExportFormat.executablePlanJson,
        profile: profile,
        variant: variant,
        layout: layout,
      ),
      throwsA(
        isA<MissingCalibrationException>().having(
          (error) => error.key,
          'key',
          calibrationKey,
        ),
      ),
    );
  });

  test('calibrated executable export contains touch points only', () async {
    final service = buildService(
      Calibration(
        key: calibrationKey,
        orientation: 'portrait',
        leftTopPx: (10, 20),
        rightBottomPx: (90, 180),
        viewportPx: (left: 0, top: 0, right: 100, bottom: 200),
        capturedAt: DateTime.utc(2026, 7, 30),
      ),
    );

    final prepared = await service.prepareExport(
      file: file,
      format: ExportFormat.executablePlanJson,
      profile: profile,
      variant: variant,
      layout: layout,
    );
    final json =
        jsonDecode(utf8.decode(prepared.bytes)) as Map<String, Object?>;
    final actions = json['actions'] as List<Object?>;

    expect(actions, isNotEmpty);
    expect(
      actions.cast<Map<String, Object?>>().map((action) => action['kind']),
      everyElement(isNot('overlayHint')),
    );
    final firstAction = actions.first as Map<String, Object?>;
    expect(firstAction['kind'], 'touchPoints');
    final payload = firstAction['payload'] as Map<String, Object?>;
    final point =
        (payload['points'] as List<Object?>).first as Map<String, Object?>;
    expect(point['x'], 50.0);
    expect(point['y'], 100.0);
  });

  test(
    'orientation change requires recalibration instead of a second record',
    () async {
      final service = buildService(
        Calibration(
          key: calibrationKey,
          orientation: 'landscape',
          leftTopPx: (10, 20),
          rightBottomPx: (90, 180),
          viewportPx: (left: 0, top: 0, right: 100, bottom: 200),
          capturedAt: DateTime.utc(2026, 7, 30),
        ),
      );

      await expectLater(
        service.prepareExport(
          file: file,
          format: ExportFormat.executablePlanJson,
          profile: profile,
          variant: variant,
          layout: layout,
        ),
        throwsA(
          isA<CalibrationOrientationMismatchException>()
              .having(
                (error) => error.calibrationOrientation,
                'calibrationOrientation',
                'landscape',
              )
              .having(
                (error) => error.targetOrientation,
                'targetOrientation',
                'portrait',
              ),
        ),
      );
    },
  );
}

class _FakeScoreParser implements ScoreParser {
  const _FakeScoreParser();

  @override
  String get formatId => 'fake';

  @override
  Score parse(Uint8List bytes) {
    return const Score(
      format: SourceFormat.jsonScore,
      tracks: <Track>[
        Track(
          name: 'Track 1',
          channel: 0,
          notes: <NoteEvent>[
            NoteEvent(pitch: 60, startMs: 100, durationMs: 50),
          ],
        ),
      ],
    );
  }
}

class _MemoryCalibrationRepository implements CalibrationRepository {
  _MemoryCalibrationRepository(Calibration? calibration)
    : _calibration = calibration;

  final Calibration? _calibration;

  @override
  Calibration? load(CalibrationKey key) =>
      _calibration?.key == key ? _calibration : null;

  @override
  List<Calibration> list() => <Calibration>[
    if (_calibration != null) _calibration,
  ];
}

class _FakeCalibrationPlatform implements CalibrationPlatform {
  const _FakeCalibrationPlatform(this.state);

  final CalibrationPlatformState state;

  @override
  Future<CalibrationPlatformState> getState() async => state;

  @override
  Future<void> cancelSession() async {}

  @override
  Future<CalibrationSessionResult?> consumePendingResult() async => null;

  @override
  Future<List<LaunchableCalibrationTarget>> findLaunchableTargets(
    List<String> packageNameHints,
  ) async => const <LaunchableCalibrationTarget>[];

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<CalibrationSessionResult> startSession(
    CalibrationSessionRequest request,
  ) async =>
      const CalibrationSessionResult(status: CalibrationSessionStatus.started);
}

class _MemoryFileStore implements PlatformFileStore {
  @override
  Future<Uint8List> readBytes(String path) async => Uint8List(0);

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async => fileName;

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) async => fileName;

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {}
}
