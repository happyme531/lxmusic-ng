typedef DownloadProgressCallback =
    void Function(int receivedBytes, int totalBytes, String fileName);
typedef DownloadStatusCallback = void Function(String message);

class MuscriptorModelPaths {
  const MuscriptorModelPaths({
    required this.directory,
    required this.conditioner,
    required this.decoder,
  });

  final String directory;
  final String conditioner;
  final String decoder;
}

abstract class MuscriptorModelRepository {
  Future<bool> isReady();

  Future<bool> hasCache();

  Future<MuscriptorModelPaths> download({
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  });

  Future<void> clearCache();

  Future<MuscriptorModelPaths> paths();
}

MuscriptorModelRepository createMuscriptorModelRepository() =>
    throw UnsupportedError('当前平台不支持本地 MuScriptor 模型');
