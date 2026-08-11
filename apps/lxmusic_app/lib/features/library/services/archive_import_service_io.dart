import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:charset/charset.dart' show gbk;
import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/music_import.dart';
import 'archive_import_service.dart';

ArchiveImportService createArchiveImportService() => IoArchiveImportService();

class IoArchiveImportService extends ArchiveImportService {
  IoArchiveImportService({
    Future<Directory> Function()? documentsDirectory,
    this.limits = const ArchiveImportLimits(),
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final ArchiveImportLimits limits;

  @override
  bool get isSupported => true;

  @override
  Future<ArchiveImportResult> importArchive({
    required String archiveFileName,
    required String? sourcePath,
    required Uint8List? bytes,
    required Set<String> knownFileNames,
    required MusicImportConflictResolver resolveConflict,
    required MusicImportProgressCallback onProgress,
    required MusicImportCancellationToken cancellationToken,
  }) async {
    if (sourcePath == null && bytes == null) {
      return _failedArchive(
        archiveFileName,
        MusicImportFailureKind.unreadableFile,
        '无法读取 ZIP 文件内容',
      );
    }

    final documents = await _documentsDirectory();
    final importsRoot = Directory(
      p.join(documents.path, 'music_library', 'imports'),
    );
    await importsRoot.create(recursive: true);
    final sessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32).toRadixString(16)}';
    final sessionRoot = Directory(p.join(importsRoot.path, sessionId));
    await sessionRoot.create(recursive: true);

    var workerSourcePath = sourcePath;
    File? temporarySource;
    if (workerSourcePath == null) {
      temporarySource = File(p.join(sessionRoot.path, '.source.zip'));
      await temporarySource.writeAsBytes(bytes!, flush: false);
      workerSourcePath = temporarySource.path;
    }

    final events = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final resultCompleter = Completer<Map<Object?, Object?>>();
    SendPort? controlPort;
    late final StreamSubscription<Object?> eventSubscription;
    late final StreamSubscription<Object?> errorSubscription;
    late final StreamSubscription<Object?> exitSubscription;

    void requestStop() {
      controlPort?.send(const <String, Object?>{'type': 'stop'});
    }

    cancellationToken.bind(requestStop);
    eventSubscription = events.listen((message) async {
      if (message is! Map) {
        return;
      }
      final event = Map<Object?, Object?>.from(message);
      switch (event['type']) {
        case 'ready':
          controlPort = event['port'] as SendPort;
          if (cancellationToken.isStopped) {
            requestStop();
          }
          break;
        case 'progress':
          try {
            onProgress(_progressFromMap(event));
          } catch (_) {}
          break;
        case 'conflict':
          final id = event['id'] as int;
          MusicImportConflictDecision decision;
          try {
            decision = await resolveConflict(
              MusicImportConflict(
                fileName: event['fileName'] as String,
                sourceLabel: event['sourceLabel'] as String,
                fromArchive: true,
              ),
            );
          } catch (_) {
            decision = const MusicImportConflictDecision(
              action: MusicImportConflictAction.stop,
            );
          }
          controlPort?.send(<String, Object?>{
            'type': 'conflictDecision',
            'id': id,
            'action': decision.action.name,
          });
          break;
        case 'done':
        case 'fatal':
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(event);
          }
          break;
      }
    });
    errorSubscription = errors.listen((message) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(<Object?, Object?>{
          'type': 'fatal',
          'kind': MusicImportFailureKind.invalidArchive.name,
          'message': 'ZIP 后台处理失败：$message',
        });
      }
    });
    exitSubscription = exits.listen((_) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(<Object?, Object?>{
            'type': 'fatal',
            'kind': MusicImportFailureKind.invalidArchive.name,
            'message': 'ZIP 后台处理进程意外退出',
          });
        }
      });
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(
        _archiveWorkerMain,
        <String, Object?>{
          'events': events.sendPort,
          'archiveFileName': archiveFileName,
          'sourcePath': workerSourcePath,
          'outputRoot': sessionRoot.path,
          'knownFileNames': knownFileNames.toList(growable: false),
          'maxEntryCount': limits.maxEntryCount,
          'maxScoreBytes': limits.maxScoreBytes,
          'maxTotalScoreBytes': limits.maxTotalScoreBytes,
          'maxCompressionRatio': limits.maxCompressionRatio,
        },
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'lxmusic_zip_import',
      );

      final result = await resultCompleter.future;

      if (result['type'] == 'fatal') {
        try {
          await discardStorage(sessionRoot.path);
        } catch (_) {}
        return _failedArchive(
          archiveFileName,
          MusicImportFailureKind.values.byName(
            result['kind'] as String? ??
                MusicImportFailureKind.invalidArchive.name,
          ),
          result['message'] as String? ?? 'ZIP 文件无效',
        );
      }

      final files = (result['files'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((raw) => _preparedFileFromMap(raw))
          .toList(growable: false);
      final failures = (result['failures'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((raw) => _failureFromMap(raw))
          .toList(growable: false);
      final storageRoot = files.isEmpty ? null : sessionRoot.path;
      if (storageRoot == null) {
        await discardStorage(sessionRoot.path);
      }
      return ArchiveImportResult(
        archiveFileName: archiveFileName,
        files: files,
        playlistFileNames:
            (result['playlistFileNames'] as List? ?? const <Object?>[])
                .whereType<String>()
                .toList(growable: false),
        failures: failures,
        storageRoot: storageRoot,
        reusedCount: result['reusedCount'] as int? ?? 0,
        skippedCount: result['skippedCount'] as int? ?? 0,
        ignoredCount: result['ignoredCount'] as int? ?? 0,
        stopped: result['stopped'] as bool? ?? false,
      );
    } catch (error) {
      try {
        await discardStorage(sessionRoot.path);
      } catch (_) {}
      return _failedArchive(
        archiveFileName,
        error is FileSystemException
            ? MusicImportFailureKind.storageError
            : MusicImportFailureKind.invalidArchive,
        'ZIP 处理失败：$error',
      );
    } finally {
      cancellationToken.unbind();
      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      events.close();
      errors.close();
      exits.close();
      isolate?.kill(priority: Isolate.immediate);
      if (temporarySource != null) {
        try {
          await temporarySource.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> discardStorage(String? storageRoot) async {
    if (storageRoot == null) {
      return;
    }
    final directory = Directory(storageRoot);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> cleanupUnreferencedStorage(Set<String> referencedPaths) async {
    final documents = await _documentsDirectory();
    final importsRoot = Directory(
      p.join(documents.path, 'music_library', 'imports'),
    );
    if (!await importsRoot.exists()) {
      return;
    }
    final referencedSessions = <String>{};
    for (final path in referencedPaths) {
      if (!p.isWithin(importsRoot.path, path)) {
        continue;
      }
      final relative = p.relative(path, from: importsRoot.path);
      final parts = p.split(relative);
      if (parts.isNotEmpty) {
        referencedSessions.add(parts.first);
      }
    }
    await for (final entity in importsRoot.list(followLinks: false)) {
      if (entity is Directory &&
          !referencedSessions.contains(p.basename(entity.path))) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  ArchiveImportResult _failedArchive(
    String archiveFileName,
    MusicImportFailureKind kind,
    String message,
  ) {
    return ArchiveImportResult(
      archiveFileName: archiveFileName,
      files: const <PreparedImportedMusicFile>[],
      playlistFileNames: const <String>[],
      failures: <MusicImportFailure>[
        MusicImportFailure(
          fileName: archiveFileName,
          kind: kind,
          message: message,
        ),
      ],
      storageRoot: null,
      reusedCount: 0,
      skippedCount: 0,
      ignoredCount: 0,
      stopped: false,
    );
  }
}

Future<void> _archiveWorkerMain(Map<String, Object?> arguments) async {
  final events = arguments['events']! as SendPort;
  final archiveFileName = arguments['archiveFileName']! as String;
  final sourcePath = arguments['sourcePath']! as String;
  final outputRoot = arguments['outputRoot']! as String;
  final limits = ArchiveImportLimits(
    maxEntryCount: arguments['maxEntryCount']! as int,
    maxScoreBytes: arguments['maxScoreBytes']! as int,
    maxTotalScoreBytes: arguments['maxTotalScoreBytes']! as int,
    maxCompressionRatio: arguments['maxCompressionRatio']! as int,
  );
  final reservedNames = (arguments['knownFileNames']! as List)
      .whereType<String>()
      .toSet();
  final control = ReceivePort();
  final pendingDecisions = <int, Completer<MusicImportConflictAction>>{};
  var stopRequested = false;
  var nextConflictId = 1;

  control.listen((message) {
    if (message is! Map) {
      return;
    }
    switch (message['type']) {
      case 'stop':
        stopRequested = true;
        for (final completer in pendingDecisions.values) {
          if (!completer.isCompleted) {
            completer.complete(MusicImportConflictAction.stop);
          }
        }
        break;
      case 'conflictDecision':
        final id = message['id'] as int;
        final completer = pendingDecisions.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(
            MusicImportConflictAction.values.byName(
              message['action'] as String,
            ),
          );
        }
        break;
    }
  });
  events.send(<String, Object?>{'type': 'ready', 'port': control.sendPort});

  InputFileStream? input;
  try {
    events.send(<String, Object?>{
      'type': 'progress',
      'stage': MusicImportStage.scanning.name,
      'sourceLabel': archiveFileName,
    });
    input = InputFileStream(sourcePath);
    final decoder = ZipDecoder();
    decoder.decodeStream(input);
    final headers = decoder.directory.fileHeaders;
    if (headers.isEmpty) {
      throw const _ArchiveImportException(
        MusicImportFailureKind.invalidArchive,
        'ZIP 文件为空或中央目录无效',
      );
    }
    final entryCountViolation = limits.validateArchive(
      entryCount: headers.length,
      declaredScoreBytes: 0,
    );
    if (entryCountViolation != null) {
      throw _ArchiveImportException(
        MusicImportFailureKind.unsafeArchive,
        entryCountViolation,
      );
    }

    final candidates = <_ZipCandidate>[];
    var ignoredCount = 0;
    var declaredTotalBytes = 0;
    for (final header in headers) {
      final decodedPath = _decodeZipEntryName(header, input);
      if (_shouldIgnoreEntry(decodedPath, header.externalFileAttributes)) {
        ignoredCount++;
        continue;
      }
      final fileName = _safeBaseName(decodedPath);
      if (fileName == null || !_isSupportedScoreName(fileName)) {
        ignoredCount++;
        continue;
      }
      declaredTotalBytes += header.uncompressedSize;
      candidates.add(_ZipCandidate(header: header, fileName: fileName));
    }
    final archiveViolation = limits.validateArchive(
      entryCount: headers.length,
      declaredScoreBytes: declaredTotalBytes,
    );
    if (archiveViolation != null) {
      throw _ArchiveImportException(
        MusicImportFailureKind.unsafeArchive,
        archiveViolation,
      );
    }

    final detector = const ScoreFormatDetector();
    final registry = createDefaultParserRegistry();
    final filesByName = <String, Map<String, Object?>>{};
    final playlistNames = <String>{};
    final failures = <Map<String, Object?>>[];
    var processedCount = 0;
    var reusedCount = 0;
    var skippedCount = 0;
    var actualTotalBytes = 0;
    var writtenIndex = 0;
    var stopped = false;
    final progressWatch = Stopwatch()..start();

    void sendProgress(String? currentName, {bool force = false}) {
      if (!force && progressWatch.elapsedMilliseconds < 100) {
        return;
      }
      progressWatch.reset();
      events.send(<String, Object?>{
        'type': 'progress',
        'stage': MusicImportStage.importing.name,
        'sourceLabel': archiveFileName,
        'currentFileName': currentName,
        'processedCount': processedCount,
        'totalCount': candidates.length,
        'importedCount': filesByName.length,
        'reusedCount': reusedCount,
        'skippedCount': skippedCount,
        'failedCount': failures.length,
        'ignoredCount': ignoredCount,
      });
    }

    sendProgress(null, force: true);
    for (final candidate in candidates) {
      await Future<void>.delayed(Duration.zero);
      if (stopRequested) {
        stopped = true;
        break;
      }
      final header = candidate.header;
      final fileName = candidate.fileName;
      Uint8List? scoreBytes;
      try {
        if ((header.generalPurposeBitFlag & 0x1) != 0) {
          throw const _EntryImportException(
            MusicImportFailureKind.encryptedArchive,
            '加密 ZIP 条目暂不支持',
          );
        }
        if (header.compressionMethod != 0 &&
            header.compressionMethod != 8 &&
            header.compressionMethod != 12) {
          throw _EntryImportException(
            MusicImportFailureKind.invalidArchive,
            '不支持的 ZIP 压缩方法 ${header.compressionMethod}',
          );
        }
        final entryViolation = limits.validateEntry(
          compressedBytes: header.compressedSize,
          uncompressedBytes: header.uncompressedSize,
        );
        if (entryViolation != null) {
          throw _EntryImportException(
            MusicImportFailureKind.unsafeArchive,
            entryViolation,
          );
        }

        final output = _LimitedOutputMemoryStream(limits.maxScoreBytes);
        header.file!.decompress(output);
        scoreBytes = output.getBytes();
        actualTotalBytes += scoreBytes.length;
        if (actualTotalBytes > limits.maxTotalScoreBytes) {
          throw _ArchiveImportException(
            MusicImportFailureKind.unsafeArchive,
            'ZIP 实际解压量超过 '
            '${limits.maxTotalScoreBytes ~/ (1024 * 1024 * 1024)} GiB 安全上限',
          );
        }
        if (header.crc32 != getCrc32(scoreBytes)) {
          throw const _EntryImportException(
            MusicImportFailureKind.invalidArchive,
            'ZIP 条目 CRC 校验失败',
          );
        }

        final detection = detector.detect(
          fileName: fileName,
          bytes: scoreBytes,
        );
        if (detection case RejectedScoreFormat()) {
          throw _EntryImportException(
            MusicImportFailureKind.formatDetectionFailed,
            detection.message,
          );
        }
        final formatId = (detection as DetectedScoreFormat).formatId;
        late final Score score;
        try {
          score = registry.parse(bytes: scoreBytes, formatId: formatId);
        } catch (error) {
          final detail = error is FormatException ? error.message : '文件结构不符合要求';
          throw _EntryImportException(
            MusicImportFailureKind.invalidFormat,
            '$formatId 文件内容无效：$detail',
          );
        }
        if (score.totalNoteCount == 0) {
          throw const _EntryImportException(
            MusicImportFailureKind.emptyScore,
            '乐谱中没有可播放音符',
          );
        }

        var targetName = fileName;
        var wasOverwrite = false;
        var wasRenamed = false;
        if (reservedNames.contains(targetName)) {
          final id = nextConflictId++;
          final completer = Completer<MusicImportConflictAction>();
          pendingDecisions[id] = completer;
          events.send(<String, Object?>{
            'type': 'conflict',
            'id': id,
            'fileName': targetName,
            'sourceLabel': '$archiveFileName / ${candidate.fileName}',
          });
          final action = await completer.future;
          pendingDecisions.remove(id);
          switch (action) {
            case MusicImportConflictAction.overwrite:
              wasOverwrite = true;
              break;
            case MusicImportConflictAction.skip:
              playlistNames.add(targetName);
              reusedCount++;
              processedCount++;
              sendProgress(fileName);
              continue;
            case MusicImportConflictAction.rename:
              targetName = nextAvailableMusicFileName(
                targetName,
                reservedNames,
              );
              wasRenamed = true;
              break;
            case MusicImportConflictAction.stop:
              stopped = true;
              stopRequested = true;
              break;
          }
          if (stopped) {
            break;
          }
        }

        writtenIndex++;
        final shard = ((writtenIndex - 1) ~/ 1000).toString().padLeft(3, '0');
        final outputDirectory = Directory(p.join(outputRoot, 'files', shard));
        await outputDirectory.create(recursive: true);
        final outputPath = p.join(
          outputDirectory.path,
          writtenIndex.toString().padLeft(8, '0'),
        );
        await File(outputPath).writeAsBytes(scoreBytes, flush: false);

        final superseded = filesByName[targetName];
        if (superseded != null) {
          try {
            await File(superseded['path']! as String).delete();
          } catch (_) {}
        }
        filesByName[targetName] = <String, Object?>{
          'path': outputPath,
          'fileName': targetName,
          'formatId': formatId,
          'trackCount': score.tracks.length,
          'durationMs': score.totalDurationMs,
          'noteCount': score.totalNoteCount,
          'wasOverwrite': wasOverwrite,
          'wasRenamed': wasRenamed,
        };
        reservedNames.add(targetName);
        playlistNames.add(targetName);
      } on _EntryImportException catch (error) {
        failures.add(<String, Object?>{
          'fileName': fileName,
          'kind': error.kind.name,
          'message': error.message,
        });
      } on _ArchiveImportException {
        rethrow;
      } catch (error) {
        failures.add(<String, Object?>{
          'fileName': fileName,
          'kind': MusicImportFailureKind.invalidArchive.name,
          'message': 'ZIP 条目读取失败：$error',
        });
      } finally {
        scoreBytes = null;
      }
      processedCount++;
      sendProgress(fileName);
    }

    sendProgress(null, force: true);
    events.send(<String, Object?>{
      'type': 'done',
      'files': filesByName.values.toList(growable: false),
      'playlistFileNames': playlistNames.toList(growable: false),
      'failures': failures,
      'reusedCount': reusedCount,
      'skippedCount': skippedCount,
      'ignoredCount': ignoredCount,
      'stopped': stopped,
    });
  } on _ArchiveImportException catch (error) {
    events.send(<String, Object?>{
      'type': 'fatal',
      'kind': error.kind.name,
      'message': error.message,
    });
  } catch (error) {
    events.send(<String, Object?>{
      'type': 'fatal',
      'kind': MusicImportFailureKind.invalidArchive.name,
      'message': 'ZIP 文件无效：$error',
    });
  } finally {
    input?.closeSync();
    control.close();
  }
}

class _ZipCandidate {
  const _ZipCandidate({required this.header, required this.fileName});

  final ZipFileHeader header;
  final String fileName;
}

class _LimitedOutputMemoryStream extends OutputMemoryStream {
  _LimitedOutputMemoryStream(this.limit) : super(size: 32 * 1024);

  final int limit;

  void _check(int additional) {
    if (length + additional > limit) {
      throw _EntryImportException(
        MusicImportFailureKind.unsafeArchive,
        '单曲实际解压后超过 ${limit ~/ (1024 * 1024)} MiB 安全上限',
      );
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}

class _ArchiveImportException implements Exception {
  const _ArchiveImportException(this.kind, this.message);

  final MusicImportFailureKind kind;
  final String message;
}

class _EntryImportException implements Exception {
  const _EntryImportException(this.kind, this.message);

  final MusicImportFailureKind kind;
  final String message;
}

bool _isSupportedScoreName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.mid') ||
      lower.endsWith('.midi') ||
      lower.endsWith('.dms') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.json');
}

bool _shouldIgnoreEntry(String path, int externalAttributes) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.endsWith('/')) {
    return true;
  }
  final mode = externalAttributes >> 16;
  if ((mode & 0xf000) == 0xa000) {
    return true;
  }
  final parts = normalized.split('/');
  return parts.contains('__MACOSX') ||
      parts.any((part) => part == '.DS_Store' || part.isEmpty);
}

String? _safeBaseName(String entryPath) {
  final normalized = entryPath.replaceAll('\\', '/').replaceAll('\u0000', '');
  final raw = normalized.split('/').last.trim();
  if (raw.isEmpty || raw == '.' || raw == '..') {
    return null;
  }
  final safe = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return safe.isEmpty ? null : safe;
}

String _decodeZipEntryName(ZipFileHeader header, InputFileStream input) {
  final rawName = _readLocalEntryName(header, input);
  final unicode = _unicodePathFromExtra(header.extraField, rawName);
  if (unicode != null) {
    return unicode;
  }
  if (rawName == null || rawName.every((byte) => byte < 0x80)) {
    return header.filename;
  }
  try {
    return utf8.decode(rawName, allowMalformed: false);
  } on FormatException {
    try {
      return gbk.decode(rawName, allowMalformed: false);
    } on FormatException {
      return header.filename;
    }
  }
}

Uint8List? _readLocalEntryName(ZipFileHeader header, InputFileStream input) {
  final previousPosition = input.position;
  try {
    input.setPosition(header.localHeaderOffset);
    if (input.readUint32() != ZipFile.zipSignature) {
      return null;
    }
    input.setPosition(header.localHeaderOffset + 26);
    final nameLength = input.readUint16();
    input.setPosition(header.localHeaderOffset + 30);
    final name = input.readBytes(nameLength).toUint8List();
    return name.length == nameLength ? name : null;
  } catch (_) {
    return null;
  } finally {
    input.setPosition(previousPosition);
  }
}

String? _unicodePathFromExtra(Uint8List? extra, Uint8List? rawName) {
  if (extra == null || extra.length < 9) {
    return null;
  }
  final data = ByteData.sublistView(extra);
  var offset = 0;
  while (offset + 4 <= extra.length) {
    final id = data.getUint16(offset, Endian.little);
    final size = data.getUint16(offset + 2, Endian.little);
    offset += 4;
    if (offset + size > extra.length) {
      return null;
    }
    if (id == 0x7075 && size >= 5 && extra[offset] == 1) {
      final expectedCrc = data.getUint32(offset + 1, Endian.little);
      if (rawName != null && expectedCrc != getCrc32(rawName)) {
        offset += size;
        continue;
      }
      try {
        return utf8.decode(extra.sublist(offset + 5, offset + size));
      } on FormatException {
        return null;
      }
    }
    offset += size;
  }
  return null;
}

MusicImportProgress _progressFromMap(Map<Object?, Object?> map) {
  return MusicImportProgress(
    stage: MusicImportStage.values.byName(map['stage'] as String),
    sourceLabel: map['sourceLabel'] as String,
    currentFileName: map['currentFileName'] as String?,
    processedCount: map['processedCount'] as int? ?? 0,
    totalCount: map['totalCount'] as int? ?? 0,
    importedCount: map['importedCount'] as int? ?? 0,
    reusedCount: map['reusedCount'] as int? ?? 0,
    skippedCount: map['skippedCount'] as int? ?? 0,
    failedCount: map['failedCount'] as int? ?? 0,
    ignoredCount: map['ignoredCount'] as int? ?? 0,
  );
}

PreparedImportedMusicFile _preparedFileFromMap(Map<Object?, Object?> raw) {
  return PreparedImportedMusicFile(
    path: raw['path'] as String,
    fileName: raw['fileName'] as String,
    formatId: raw['formatId'] as String,
    trackCount: raw['trackCount'] as int,
    durationMs: raw['durationMs'] as int,
    noteCount: raw['noteCount'] as int,
    wasOverwrite: raw['wasOverwrite'] as bool? ?? false,
    wasRenamed: raw['wasRenamed'] as bool? ?? false,
  );
}

MusicImportFailure _failureFromMap(Map<Object?, Object?> raw) {
  return MusicImportFailure(
    fileName: raw['fileName'] as String,
    kind: MusicImportFailureKind.values.byName(raw['kind'] as String),
    message: raw['message'] as String,
  );
}
