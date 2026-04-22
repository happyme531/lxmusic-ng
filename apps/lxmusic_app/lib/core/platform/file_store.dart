import 'dart:typed_data';

class PickedFileData {
  const PickedFileData({
    required this.fileName,
    this.sourcePath,
    this.bytes,
  });

  final String fileName;
  final String? sourcePath;
  final Uint8List? bytes;

  bool get hasReadableContent => bytes != null || sourcePath != null;
}

abstract class PlatformFileStore {
  Future<Uint8List> readBytes(String path);

  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  });

  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  });

  Future<bool> exists(String path);

  Future<void> writeBytes(String path, Uint8List bytes);

  Future<void> deleteFile(String path);
}
