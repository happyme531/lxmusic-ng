// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html';
import 'dart:math';
import 'dart:typed_data';

import 'file_store.dart';

PlatformFileStore createPlatformFileStore() => const WebPlatformFileStore();

class WebPlatformFileStore implements PlatformFileStore {
  const WebPlatformFileStore();

  static const _databaseName = 'lxmusic_app_files';
  static const _storeName = 'music_library';
  static const _nonceUpperBound = 4294967296;

  @override
  Future<void> deleteFile(String path) async {
    final store = await _store('readwrite');
    await store.deleteObject(path);
  }

  @override
  Future<bool> exists(String path) async {
    final store = await _store('readonly');
    return await store.getObject(path) != null;
  }

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final fileId = _buildFileId(fileName);
    final store = await _store('readwrite');
    await store.put(_encodeBytes(bytes), fileId);
    return fileId;
  }

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) {
    throw UnsupportedError('Web 平台不支持按本地路径导入文件。');
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final store = await _store('readonly');
    final raw = await store.getObject(path);
    if (raw == null) {
      throw StateError('File not found: $path');
    }
    return _decodeBytes(raw);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) {
    throw UnsupportedError('Web 平台不支持按任意路径写入文件。');
  }

  Future<dynamic> _store(String mode) async {
    final database = await window.indexedDB!.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = (event.target as dynamic).result;
        if (!database.objectStoreNames!.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );
    return database.transaction(_storeName, mode).objectStore(_storeName);
  }

  String _buildFileId(String fileName) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final nonce = Random().nextInt(_nonceUpperBound).toRadixString(16);
    final sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return 'web:$micros:$nonce:$sanitized';
  }

  Uint8List _decodeBytes(Object raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is ByteBuffer) {
      return Uint8List.view(raw);
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    throw StateError('Unsupported IndexedDB payload type: ${raw.runtimeType}');
  }

  ByteBuffer _encodeBytes(Uint8List bytes) {
    return Uint8List.fromList(bytes).buffer;
  }
}
