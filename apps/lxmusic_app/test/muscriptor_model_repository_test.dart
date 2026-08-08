import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_model_repository_io.dart';

void main() {
  test(
    'clearCache removes complete, partial, and nested model files',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'lxmusic-muscriptor-cache-',
      );
      final cacheRoot = Directory(p.join(temporaryDirectory.path, 'models'));
      final modelDirectory = Directory(p.join(cacheRoot.path, 'current-model'));
      final httpClient = HttpClient();
      addTearDown(() async {
        httpClient.close(force: true);
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });

      final repository = MuscriptorModelRepositoryIo(
        directoryProvider: () async => modelDirectory,
        cacheRootProvider: () async => cacheRoot,
        httpClient: httpClient,
      );

      expect(await repository.hasCache(), isFalse);

      await modelDirectory.create(recursive: true);
      expect(await repository.hasCache(), isFalse);
      await File(
        p.join(modelDirectory.path, 'decoder.onnx.data.part'),
      ).writeAsBytes(const <int>[1, 2, 3]);
      final nestedDirectory = Directory(p.join(cacheRoot.path, 'old-model'));
      await nestedDirectory.create();
      await File(
        p.join(nestedDirectory.path, 'config.json'),
      ).writeAsString('{}');
      expect(await repository.hasCache(), isTrue);

      await repository.clearCache();

      expect(await cacheRoot.exists(), isFalse);
      expect(await repository.hasCache(), isFalse);
      await repository.clearCache();
    },
  );

  test('same-sized corrupt config is not treated as a ready model', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'lxmusic-muscriptor-validation-',
    );
    final httpClient = HttpClient();
    addTearDown(() async {
      httpClient.close(force: true);
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    await File(
      p.join(temporaryDirectory.path, 'config.json'),
    ).writeAsBytes(List<int>.filled(1274, 0));

    final repository = MuscriptorModelRepositoryIo(
      directoryProvider: () async => temporaryDirectory,
      httpClient: httpClient,
    );

    expect(await repository.isReady(), isFalse);
  });

  test('download switches to fallback when the primary body stalls', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'lxmusic-muscriptor-fallback-',
    );
    final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fallback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final httpClient = HttpClient();
    var primaryRequests = 0;
    var fallbackRequests = 0;
    Uri? primaryUri;
    String? primaryAcceptEncoding;
    primary.listen((request) async {
      primaryRequests++;
      primaryUri = request.uri;
      primaryAcceptEncoding = request.headers.value(
        HttpHeaders.acceptEncodingHeader,
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = 1274;
      await request.response.flush();
    });
    fallback.listen((request) async {
      fallbackRequests++;
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    addTearDown(() async {
      httpClient.close(force: true);
      await primary.close(force: true);
      await fallback.close(force: true);
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final statuses = <String>[];
    final repository = MuscriptorModelRepositoryIo(
      directoryProvider: () async => temporaryDirectory,
      httpClient: httpClient,
      downloadBases: <String>[
        'http://${primary.address.host}:${primary.port}',
        'http://${fallback.address.host}:${fallback.port}',
      ],
      responseHeaderTimeout: const Duration(milliseconds: 200),
      downloadIdleTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      repository.download(onStatus: statuses.add),
      throwsA(isA<HttpException>()),
    );

    expect(primaryRequests, 1);
    expect(fallbackRequests, 1);
    expect(statuses, contains(contains('正在切换到')));
    expect(
      primaryUri?.path,
      '/$muscriptorModelId/resolve/$muscriptorModelRevision/'
      'onnx/w4a32_optimized/config.json',
    );
    expect(primaryUri?.queryParameters['download'], 'true');
    expect(primaryAcceptEncoding, 'identity');
  });

  test('fallback restarts after a corrupt primary response', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'lxmusic-muscriptor-restart-',
    );
    final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fallback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final httpClient = HttpClient();
    String? fallbackRange;
    primary.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.add(const <int>[1, 2, 3]);
      await request.response.close();
    });
    fallback.listen((request) async {
      fallbackRange = request.headers.value(HttpHeaders.rangeHeader);
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    addTearDown(() async {
      httpClient.close(force: true);
      await primary.close(force: true);
      await fallback.close(force: true);
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final repository = MuscriptorModelRepositoryIo(
      directoryProvider: () async => temporaryDirectory,
      httpClient: httpClient,
      downloadBases: <String>[
        'http://${primary.address.host}:${primary.port}',
        'http://${fallback.address.host}:${fallback.port}',
      ],
      responseHeaderTimeout: const Duration(milliseconds: 200),
      downloadIdleTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(repository.download(), throwsA(isA<HttpException>()));

    expect(fallbackRange, isNull);
    expect(
      await File(p.join(temporaryDirectory.path, 'config.json.part')).exists(),
      isFalse,
    );
  });

  test(
    'decompresses a gzip response even when identity was requested',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'lxmusic-muscriptor-gzip-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final httpClient = HttpClient();
      String? acceptEncoding;
      server.listen((request) async {
        acceptEncoding = request.headers.value(
          HttpHeaders.acceptEncodingHeader,
        );
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.add(gzip.encode(List<int>.filled(1274, 0)));
        await request.response.close();
      });
      addTearDown(() async {
        httpClient.close(force: true);
        await server.close(force: true);
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });

      final repository = MuscriptorModelRepositoryIo(
        directoryProvider: () async => temporaryDirectory,
        httpClient: httpClient,
        downloadBases: <String>['http://${server.address.host}:${server.port}'],
      );

      await expectLater(
        repository.download(),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('SHA-256'),
            'a SHA-256 error after transparent gzip decompression',
          ),
        ),
      );
      expect(acceptEncoding, 'identity');
    },
  );
}
