import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart' show gbk;
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/library/models/music_import.dart';
import 'package:lxmusic_app/features/library/services/archive_import_service.dart';
import 'package:lxmusic_app/features/library/services/archive_import_service_io.dart';

void main() {
  late Directory temporaryDirectory;
  late IoArchiveImportService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'lxmusic_zip_import_',
    );
    service = IoArchiveImportService(
      documentsDirectory: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'streams nested entries, ignores unrelated files, and decodes GBK names',
    () async {
      final zip =
          _writeZip(temporaryDirectory, 'collection.zip', <String, String>{
            'folder/天空.txt': '1 2 3',
            'folder/scale.dms.txt': 'bpm=120\n1',
            'cover.png': 'not a score',
          }, gbkFileNames: true);
      final progress = <MusicImportProgress>[];

      final result = await service.importArchive(
        archiveFileName: 'collection.zip',
        sourcePath: zip.path,
        bytes: null,
        knownFileNames: <String>{},
        resolveConflict: (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.rename,
        ),
        onProgress: progress.add,
        cancellationToken: MusicImportCancellationToken(),
      );

      expect(
        result.files.map((file) => file.fileName),
        containsAll(<String>['天空.txt', 'scale.dms.txt']),
      );
      expect(result.files, hasLength(2));
      expect(result.ignoredCount, 1);
      expect(result.failures, isEmpty);
      expect(result.playlistFileNames, hasLength(2));
      expect(progress.any((value) => value.totalCount == 2), isTrue);
      for (final file in result.files) {
        expect(await File(file.path).exists(), isTrue);
      }
    },
  );

  test('preserves standard UTF-8 names containing Latin characters', () async {
    final zip = _writeZip(temporaryDirectory, 'unicode.zip', <String, String>{
      'éé.txt': '1 2',
    });

    final result = await service.importArchive(
      archiveFileName: 'unicode.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.rename,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.files.single.fileName, 'éé.txt');
  });

  test('renames duplicate basenames with a compound suffix intact', () async {
    final zip = _writeZip(
      temporaryDirectory,
      'duplicates.zip',
      <String, String>{'a/song.dms.txt': '1 2', 'b/song.dms.txt': '3 4'},
    );

    final result = await service.importArchive(
      archiveFileName: 'duplicates.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.rename,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.files.map((file) => file.fileName).toSet(), <String>{
      'song.dms.txt',
      'song (2).dms.txt',
    });
    expect(result.files.where((file) => file.wasRenamed), hasLength(1));
  });

  test('skip reuses an existing track in the generated playlist', () async {
    final zip = _writeZip(temporaryDirectory, 'reuse.zip', <String, String>{
      'song.txt': '1 2',
    });

    final result = await service.importArchive(
      archiveFileName: 'reuse.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{'song.txt'},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.skip,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.files, isEmpty);
    expect(result.reusedCount, 1);
    expect(result.playlistFileNames, <String>['song.txt']);
  });

  test('stop keeps entries completed before the conflict', () async {
    final zip = _writeZip(temporaryDirectory, 'partial.zip', <String, String>{
      'first.txt': '1 2',
      'existing.txt': '3 4',
      'last.txt': '5 6',
    });

    final result = await service.importArchive(
      archiveFileName: 'partial.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{'existing.txt'},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.stop,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.stopped, isTrue);
    expect(result.files.map((file) => file.fileName), <String>['first.txt']);
    expect(result.playlistFileNames, <String>['first.txt']);
  });

  test('rejects encrypted entries without requesting a password', () async {
    final zip = _writeZip(temporaryDirectory, 'encrypted.zip', <String, String>{
      'secret.txt': '1 2',
    }, password: 'secret');

    final result = await service.importArchive(
      archiveFileName: 'encrypted.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.overwrite,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.files, isEmpty);
    expect(result.failures, hasLength(1));
    expect(
      result.failures.single.kind,
      MusicImportFailureKind.encryptedArchive,
    );
  });

  test('reports a corrupted score entry and continues the archive', () async {
    final zip = _writeZip(temporaryDirectory, 'corrupt.zip', <String, String>{
      'broken.txt': '1 2 3 4 5 6 7 8',
    });
    final bytes = zip.readAsBytesSync();
    final fileNameLength = bytes[26] | (bytes[27] << 8);
    final extraLength = bytes[28] | (bytes[29] << 8);
    final payloadOffset = 30 + fileNameLength + extraLength;
    bytes[payloadOffset] ^= 0xff;
    zip.writeAsBytesSync(bytes);

    final result = await service.importArchive(
      archiveFileName: 'corrupt.zip',
      sourcePath: zip.path,
      bytes: null,
      knownFileNames: <String>{},
      resolveConflict: (_) async => const MusicImportConflictDecision(
        action: MusicImportConflictAction.overwrite,
      ),
      onProgress: (_) {},
      cancellationToken: MusicImportCancellationToken(),
    );

    expect(result.files, isEmpty);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.kind, MusicImportFailureKind.invalidArchive);
  });

  test('wide safety limits cover entry count, size, total, and ratio', () {
    const limits = ArchiveImportLimits();

    expect(
      limits.validateArchive(entryCount: 50001, declaredScoreBytes: 0),
      contains('50000'),
    );
    expect(
      limits.validateArchive(
        entryCount: 1,
        declaredScoreBytes: 8 * 1024 * 1024 * 1024 + 1,
      ),
      contains('8 GiB'),
    );
    expect(
      limits.validateEntry(
        compressedBytes: 1,
        uncompressedBytes: 64 * 1024 * 1024 + 1,
      ),
      contains('64 MiB'),
    );
    expect(
      limits.validateEntry(
        compressedBytes: 64 * 1024 * 1024 + 1,
        uncompressedBytes: 1,
      ),
      contains('64 MiB'),
    );
    expect(
      limits.validateEntry(compressedBytes: 1, uncompressedBytes: 1001),
      contains('1000'),
    );
    expect(
      limits.validateEntry(compressedBytes: -1, uncompressedBytes: 1),
      contains('无效'),
    );
  });

  test(
    'service rejects an entry over its configured test size limit',
    () async {
      final zip = _writeZip(temporaryDirectory, 'limited.zip', <String, String>{
        'song.txt': '1 2',
      });
      service = IoArchiveImportService(
        documentsDirectory: () async => temporaryDirectory,
        limits: const ArchiveImportLimits(maxScoreBytes: 2),
      );

      final result = await service.importArchive(
        archiveFileName: 'limited.zip',
        sourcePath: zip.path,
        bytes: null,
        knownFileNames: <String>{},
        resolveConflict: (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.overwrite,
        ),
        onProgress: (_) {},
        cancellationToken: MusicImportCancellationToken(),
      );

      expect(result.files, isEmpty);
      expect(result.failures.single.kind, MusicImportFailureKind.unsafeArchive);
    },
  );

  test(
    'cancellation token stops a running archive and keeps completed entries',
    () async {
      final entries = <String, String>{
        for (var index = 0; index < 2000; index++)
          'song_${index.toString().padLeft(4, '0')}.txt': '1 2',
      };
      final zip = _writeZip(temporaryDirectory, 'cancel.zip', entries);
      final token = MusicImportCancellationToken();

      final result = await service.importArchive(
        archiveFileName: 'cancel.zip',
        sourcePath: zip.path,
        bytes: null,
        knownFileNames: <String>{},
        resolveConflict: (_) async => const MusicImportConflictDecision(
          action: MusicImportConflictAction.overwrite,
        ),
        onProgress: (value) {
          if (value.processedCount > 0) {
            token.stop();
          }
        },
        cancellationToken: token,
      );

      expect(result.stopped, isTrue);
      expect(result.files, isNotEmpty);
      expect(result.files.length, lessThan(2000));
      expect(result.playlistFileNames, hasLength(result.files.length));
    },
  );
}

File _writeZip(
  Directory directory,
  String name,
  Map<String, String> entries, {
  bool gbkFileNames = false,
  String? password,
}) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  final bytes = ZipEncoder(
    filenameEncoding: gbkFileNames ? gbk : const Utf8Codec(),
    password: password,
  ).encodeBytes(archive);
  return File('${directory.path}/$name')..writeAsBytesSync(bytes);
}
