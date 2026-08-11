import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/library/models/music_import.dart';
import 'package:lxmusic_app/features/library/services/archive_import_service_io.dart';

void main() {
  test(
    'imports 10000 valid score entries with bounded working data',
    () async {
      if (Platform.environment['LXMUSIC_RUN_ZIP_STRESS'] != '1') {
        return;
      }

      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'lxmusic_zip_stress_',
      );
      addTearDown(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
      final archive = Archive();
      for (var index = 0; index < 10000; index++) {
        archive.add(
          ArchiveFile.string(
            'folder/song_${index.toString().padLeft(5, '0')}.txt',
            '1 2',
          ),
        );
      }
      final zipFile = File('${temporaryDirectory.path}/ten_thousand.zip')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final service = IoArchiveImportService(
        documentsDirectory: () async => temporaryDirectory,
      );
      MusicImportProgress? latestProgress;
      final stopwatch = Stopwatch()..start();

      final result = await service.importArchive(
        archiveFileName: 'ten_thousand.zip',
        sourcePath: zipFile.path,
        bytes: null,
        knownFileNames: <String>{},
        resolveConflict: (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.rename,
        ),
        onProgress: (value) => latestProgress = value,
        cancellationToken: MusicImportCancellationToken(),
      );
      stopwatch.stop();

      expect(result.files, hasLength(10000));
      expect(result.playlistFileNames, hasLength(10000));
      expect(result.failures, isEmpty);
      expect(latestProgress?.totalCount, 10000);
      expect(stopwatch.elapsed, lessThan(const Duration(minutes: 2)));
      // Visible in the opt-in benchmark output and useful alongside /usr/bin/time.
      // ignore: avoid_print
      print(
        'ZIP_STRESS elapsed_ms=${stopwatch.elapsedMilliseconds} files=10000',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
