import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_store.dart';

PlatformFileStore createPlatformFileStore() => const IoPlatformFileStore();

class IoPlatformFileStore implements PlatformFileStore {
  const IoPlatformFileStore();

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }

    final destinationPath = await _newLibraryFilePath(fileName);
    await sourceFile.copy(destinationPath);
    return destinationPath;
  }

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final destinationPath = await _newLibraryFilePath(fileName);
    final destinationFile = File(destinationPath);
    await destinationFile.writeAsBytes(bytes, flush: true);
    return destinationPath;
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    return Uint8List.fromList(await File(path).readAsBytes());
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<Directory> _ensureMusicLibraryDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final libraryDir = Directory('${appDir.path}/music_library');
    if (!await libraryDir.exists()) {
      await libraryDir.create(recursive: true);
    }
    return libraryDir;
  }

  Future<String> _newLibraryFilePath(String fileName) async {
    final libraryDir = await _ensureMusicLibraryDirectory();
    final singles = Directory(p.join(libraryDir.path, 'imports', 'single'));
    await singles.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final nonce = Random().nextInt(1 << 32).toRadixString(16);
    return p.join(
      singles.path,
      '${DateTime.now().microsecondsSinceEpoch}_${nonce}_$safeName',
    );
  }
}
