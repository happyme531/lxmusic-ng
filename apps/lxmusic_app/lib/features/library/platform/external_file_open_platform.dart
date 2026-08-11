import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalFileOpenPlatformProvider = Provider<ExternalFileOpenPlatform>((
  ref,
) {
  final platform = MethodChannelExternalFileOpenPlatform();
  ref.onDispose(platform.dispose);
  return platform;
});

typedef ExternalFilesAvailableHandler = Future<void> Function();

class ExternalOpenedFile {
  const ExternalOpenedFile({
    required this.fileName,
    this.path,
    this.errorMessage,
  });

  final String fileName;
  final String? path;
  final String? errorMessage;

  bool get isReadable => path != null && errorMessage == null;

  factory ExternalOpenedFile.fromMap(Map<Object?, Object?> map) {
    return ExternalOpenedFile(
      fileName: map['fileName'] as String? ?? '外部文件',
      path: map['path'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

abstract interface class ExternalFileOpenPlatform {
  Future<List<ExternalOpenedFile>> consumePendingFiles();

  Future<void> releaseCachedFiles(Iterable<String> paths);

  void setFilesAvailableHandler(ExternalFilesAvailableHandler? handler);

  void dispose();
}

class MethodChannelExternalFileOpenPlatform
    implements ExternalFileOpenPlatform {
  MethodChannelExternalFileOpenPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const channelName =
      'dev.happyme531.clxmidiplayer.ng/external_file_open';

  final MethodChannel channel;
  ExternalFilesAvailableHandler? _filesAvailableHandler;

  @override
  Future<List<ExternalOpenedFile>> consumePendingFiles() async {
    final result =
        await channel.invokeListMethod<Object?>('consumePendingFiles') ??
        const <Object?>[];
    return result
        .whereType<Map>()
        .map(
          (raw) => ExternalOpenedFile.fromMap(Map<Object?, Object?>.from(raw)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> releaseCachedFiles(Iterable<String> paths) async {
    final values = paths.toSet().toList(growable: false);
    if (values.isEmpty) return;
    await channel.invokeMethod<void>('releaseCachedFiles', <String, Object?>{
      'paths': values,
    });
  }

  @override
  void setFilesAvailableHandler(ExternalFilesAvailableHandler? handler) {
    _filesAvailableHandler = handler;
    channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'externalFilesAvailable') {
      await _filesAvailableHandler?.call();
    }
    return null;
  }

  @override
  void dispose() {
    _filesAvailableHandler = null;
    channel.setMethodCallHandler(null);
  }
}
