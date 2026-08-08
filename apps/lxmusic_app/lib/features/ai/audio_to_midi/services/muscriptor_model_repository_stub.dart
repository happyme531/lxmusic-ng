import 'muscriptor_model_repository.dart';

MuscriptorModelRepository createMuscriptorModelRepository() =>
    _UnsupportedMuscriptorModelRepository();

class _UnsupportedMuscriptorModelRepository
    implements MuscriptorModelRepository {
  Never _unsupported() => throw UnsupportedError('当前平台暂不支持下载或运行 MuScriptor 模型');

  @override
  Future<void> clearCache() async => _unsupported();

  @override
  Future<MuscriptorModelPaths> download({
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  }) async => _unsupported();

  @override
  Future<bool> hasCache() async => false;

  @override
  Future<bool> isReady() async => false;

  @override
  Future<MuscriptorModelPaths> paths() async => _unsupported();
}
