import 'dart:typed_data';

import 'file_store.dart';

PlatformFileStore createPlatformFileStore() => const UnsupportedPlatformFileStore();

class UnsupportedPlatformFileStore implements PlatformFileStore {
  const UnsupportedPlatformFileStore();

  @override
  Future<void> deleteFile(String path) => _unsupported();

  @override
  Future<bool> exists(String path) => _unsupported();

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) => _unsupported();

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) => _unsupported();

  @override
  Future<Uint8List> readBytes(String path) => _unsupported();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) => _unsupported();

  Never _unsupported<T>() {
    throw UnsupportedError('文件系统操作暂不支持当前平台。');
  }
}
