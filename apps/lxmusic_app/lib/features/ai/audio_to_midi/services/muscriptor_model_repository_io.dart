import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'muscriptor_model_repository.dart';

const muscriptorModelId = 'happyme531/muscriptor-medium-onnx';
const muscriptorModelRevision = '7d1a2cc14a335f3bbee445147286f215287ab2a4';
const muscriptorModelDownloadBytes = 223658440;
const _verificationStampFileName = '.verified-manifest';

const _defaultDownloadBases = <String>[
  'https://huggingface.co',
  'https://hf-mirror.com',
];

const _modelFiles = <_ModelFile>[
  _ModelFile(
    name: 'config.json',
    size: 1274,
    sha256: 'f96a1c3131459e32bd443325d39d963f0ea9a3cdd9dea8e6e2d9ab140f74302d',
  ),
  _ModelFile(
    name: 'conditioner.onnx',
    size: 6223112,
    sha256: 'c1ea7895ade9760538f42f63110a782bcc1606dee89f2ee434db2251434a3c7d',
  ),
  _ModelFile(
    name: 'decoder.onnx',
    size: 79814,
    sha256: '74e1181288fa5205754e9661cbccafc5182d035beadd4412da1ecd00515c3de9',
  ),
  _ModelFile(
    name: 'decoder.onnx.data',
    size: 217354240,
    sha256: '4bc6ac2807854632bacc0ef9b5e9e1871545e573194fe7fc197948730aa3c8ef',
  ),
];

MuscriptorModelRepository createMuscriptorModelRepository() =>
    MuscriptorModelRepositoryIo();

class MuscriptorModelRepositoryIo implements MuscriptorModelRepository {
  MuscriptorModelRepositoryIo({
    Future<Directory> Function()? directoryProvider,
    Future<Directory> Function()? cacheRootProvider,
    HttpClient? httpClient,
    List<String> downloadBases = _defaultDownloadBases,
    Duration responseHeaderTimeout = const Duration(seconds: 30),
    Duration downloadIdleTimeout = const Duration(seconds: 30),
  }) : _directoryProvider = directoryProvider ?? _defaultModelDirectory,
       _cacheRootProvider =
           cacheRootProvider ?? directoryProvider ?? _defaultModelCacheRoot,
       _httpClient = httpClient ?? HttpClient(),
       _downloadBases = List<String>.unmodifiable(downloadBases),
       _responseHeaderTimeout = responseHeaderTimeout,
       _downloadIdleTimeout = downloadIdleTimeout {
    _httpClient.connectionTimeout = const Duration(seconds: 30);
    // Keep transparent decoding enabled as a fallback for redirects/proxies
    // that ignore Accept-Encoding: identity.
    _httpClient.autoUncompress = true;
  }

  final Future<Directory> Function() _directoryProvider;
  final Future<Directory> Function() _cacheRootProvider;
  final HttpClient _httpClient;
  final List<String> _downloadBases;
  final Duration _responseHeaderTimeout;
  final Duration _downloadIdleTimeout;

  @override
  Future<bool> isReady() async {
    final directory = await _directoryProvider();
    for (final spec in _modelFiles) {
      final file = File(p.join(directory.path, spec.name));
      if (!await file.exists() || await file.length() != spec.size) {
        await _deleteVerificationStamp(directory);
        return false;
      }
      if (spec.name == 'config.json' && !await _hasExpectedDigest(file, spec)) {
        await _deleteVerificationStamp(directory);
        return false;
      }
    }
    if (await _hasCurrentVerificationStamp(directory)) return true;

    for (final spec in _modelFiles) {
      final file = File(p.join(directory.path, spec.name));
      if (!await _hasExpectedDigest(file, spec)) return false;
    }
    await _writeVerificationStamp(directory);
    return true;
  }

  @override
  Future<bool> hasCache() async {
    final directory = await _cacheRootProvider();
    if (!await directory.exists()) return false;
    return directory
        .list(recursive: true, followLinks: false)
        .any((entity) => entity is File);
  }

  @override
  Future<MuscriptorModelPaths> download({
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  }) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final trustExistingFiles = await _canTrustExistingFiles(directory);

    var completedBytes = 0;
    for (final spec in _modelFiles) {
      final destination = File(p.join(directory.path, spec.name));
      if (await destination.exists() &&
          await destination.length() == spec.size &&
          (trustExistingFiles || await _hasExpectedDigest(destination, spec))) {
        completedBytes += spec.size;
        onProgress?.call(
          completedBytes,
          muscriptorModelDownloadBytes,
          spec.name,
        );
        continue;
      }

      await _downloadFile(
        directory: directory,
        spec: spec,
        completedBytes: completedBytes,
        onProgress: onProgress,
        onStatus: onStatus,
      );
      completedBytes += spec.size;
    }

    await _writeVerificationStamp(directory);
    return paths();
  }

  Future<bool> _hasExpectedDigest(File file, _ModelFile spec) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == spec.sha256;
  }

  Future<bool> _hasCurrentVerificationStamp(Directory directory) async {
    final stamp = File(p.join(directory.path, _verificationStampFileName));
    if (!await stamp.exists()) return false;
    try {
      return await stamp.readAsString() == _verificationStamp;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _canTrustExistingFiles(Directory directory) async {
    if (!await _hasCurrentVerificationStamp(directory)) return false;
    final config = _modelFiles.first;
    final file = File(p.join(directory.path, config.name));
    if (await file.exists() &&
        await file.length() == config.size &&
        await _hasExpectedDigest(file, config)) {
      return true;
    }
    await _deleteVerificationStamp(directory);
    return false;
  }

  Future<void> _writeVerificationStamp(Directory directory) async {
    final stamp = File(p.join(directory.path, _verificationStampFileName));
    final partial = File('${stamp.path}.part');
    await partial.writeAsString(_verificationStamp, flush: true);
    if (await stamp.exists()) await stamp.delete();
    await partial.rename(stamp.path);
  }

  Future<void> _deleteVerificationStamp(Directory directory) async {
    for (final name in <String>[
      _verificationStampFileName,
      '$_verificationStampFileName.part',
    ]) {
      final file = File(p.join(directory.path, name));
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _downloadFile({
    required Directory directory,
    required _ModelFile spec,
    required int completedBytes,
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  }) async {
    final destination = File(p.join(directory.path, spec.name));
    final partial = File('${destination.path}.part');
    if (await _promoteCompletePartial(
      partial: partial,
      destination: destination,
      spec: spec,
      completedBytes: completedBytes,
      onProgress: onProgress,
    )) {
      return;
    }

    final failures = <String>[];

    for (var index = 0; index < _downloadBases.length; index++) {
      final base = _downloadBases[index];
      final source = _sourceLabel(base);
      if (index == 0) onStatus?.call('正在连接 $source…');
      try {
        await _downloadFrom(
          base: base,
          partial: partial,
          spec: spec,
          completedBytes: completedBytes,
          onProgress: onProgress,
        );
        final actualSize = await partial.length();
        if (actualSize != spec.size) {
          throw FormatException('下载文件大小不匹配（实际 $actualSize，预期 ${spec.size}）');
        }
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString() != spec.sha256) {
          throw const FormatException('下载文件 SHA-256 校验失败');
        }
        if (await destination.exists()) {
          await destination.delete();
        }
        await partial.rename(destination.path);
        return;
      } catch (error) {
        if (error is FormatException && await partial.exists()) {
          await partial.delete();
        }
        failures.add('$source：$error');
        if (index + 1 < _downloadBases.length) {
          onStatus?.call(
            '$source 下载失败，正在切换到 ${_sourceLabel(_downloadBases[index + 1])}…',
          );
        }
      }
    }

    throw HttpException('模型文件 ${spec.name} 下载失败：${failures.join('；')}');
  }

  Future<bool> _promoteCompletePartial({
    required File partial,
    required File destination,
    required _ModelFile spec,
    required int completedBytes,
    DownloadProgressCallback? onProgress,
  }) async {
    if (!await partial.exists() || await partial.length() != spec.size) {
      return false;
    }
    final digest = await sha256.bind(partial.openRead()).first;
    if (digest.toString() != spec.sha256) {
      await partial.delete();
      return false;
    }
    if (await destination.exists()) await destination.delete();
    await partial.rename(destination.path);
    onProgress?.call(
      completedBytes + spec.size,
      muscriptorModelDownloadBytes,
      spec.name,
    );
    return true;
  }

  Future<void> _downloadFrom({
    required String base,
    required File partial,
    required _ModelFile spec,
    required int completedBytes,
    DownloadProgressCallback? onProgress,
  }) async {
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > spec.size) {
      await partial.delete();
      offset = 0;
    }

    final uri = Uri.parse(
      '$base/$muscriptorModelId/resolve/$muscriptorModelRevision/'
      'onnx/w4a32_optimized/${spec.name}?download=true',
    );
    final request = await _httpClient.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'LxMusic-NG/0.1 MuScriptorModelDownloader',
    );
    // Model artifacts must be transferred byte-for-byte: size/SHA checks and
    // Range offsets are defined against the repository file, not a gzip body.
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }

    late final HttpClientResponse response;
    try {
      response = await request.close().timeout(_responseHeaderTimeout);
    } on TimeoutException catch (error, stackTrace) {
      request.abort(error, stackTrace);
      throw TimeoutException('等待 ${uri.host} 响应超时', _responseHeaderTimeout);
    }
    if (response.statusCode == HttpStatus.ok) {
      offset = 0;
    } else if (response.statusCode == HttpStatus.partialContent) {
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      if (contentRange == null || !contentRange.startsWith('bytes $offset-')) {
        await _cancelResponse(response);
        throw const FormatException('服务器返回的断点范围不匹配');
      }
    } else {
      await _cancelResponse(response);
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    debugPrint(
      '[MuScriptorDownload] ${spec.name} ${uri.host} '
      'status=${response.statusCode} offset=$offset '
      'contentLength=${response.contentLength} '
      'contentEncoding=${response.headers.value(HttpHeaders.contentEncodingHeader)}',
    );

    final sink = await partial.open(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var received = offset;
    try {
      await for (final chunk in response.timeout(_downloadIdleTimeout)) {
        await sink.writeFrom(chunk);
        received += chunk.length;
        if (received > spec.size) {
          throw const FormatException('服务器返回的数据超过预期大小');
        }
        onProgress?.call(
          completedBytes + received,
          muscriptorModelDownloadBytes,
          spec.name,
        );
      }
      await sink.flush();
      debugPrint(
        '[MuScriptorDownload] ${spec.name} ${uri.host} '
        'received=$received expected=${spec.size}',
      );
    } finally {
      await sink.close();
    }
  }

  Future<void> _cancelResponse(HttpClientResponse response) async {
    await response.listen(null).cancel();
  }

  String _sourceLabel(String base) {
    final host = Uri.tryParse(base)?.host;
    return switch (host) {
      'huggingface.co' => 'Hugging Face',
      'hf-mirror.com' => 'hf-mirror',
      final String value when value.isNotEmpty => value,
      _ => base,
    };
  }

  @override
  Future<MuscriptorModelPaths> paths() async {
    final directory = await _directoryProvider();
    return MuscriptorModelPaths(
      directory: directory.path,
      conditioner: p.join(directory.path, 'conditioner.onnx'),
      decoder: p.join(directory.path, 'decoder.onnx'),
    );
  }

  @override
  Future<void> clearCache() async {
    final directory = await _cacheRootProvider();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static Future<Directory> _defaultModelDirectory() async {
    final root = await _defaultModelCacheRoot();
    return Directory(
      p.join(root.path, 'muscriptor-medium-onnx', 'w4a32-optimized'),
    );
  }

  static Future<Directory> _defaultModelCacheRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'models'));
  }
}

class _ModelFile {
  const _ModelFile({
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String name;
  final int size;
  final String sha256;
}

String get _verificationStamp => <String>[
  muscriptorModelRevision,
  for (final spec in _modelFiles) '${spec.name}:${spec.size}:${spec.sha256}',
].join('\n');
