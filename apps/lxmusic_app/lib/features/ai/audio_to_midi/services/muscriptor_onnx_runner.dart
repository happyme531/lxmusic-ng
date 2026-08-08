import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/muscriptor_transcription.dart';
import 'muscriptor_audio_frontend.dart';
import 'muscriptor_model_repository.dart';
import 'muscriptor_token_decoder.dart';

class MuscriptorInferenceProgress {
  const MuscriptorInferenceProgress({
    required this.completedChunks,
    required this.totalChunks,
    required this.generatedTokensInChunk,
    required this.message,
  });

  final int completedChunks;
  final int totalChunks;
  final int generatedTokensInChunk;
  final String message;

  double get fraction {
    if (totalChunks <= 0) return 0;
    final partialChunk = generatedTokensInChunk <= 0
        ? 0.0
        : math.min(0.95, generatedTokensInChunk / 400.0);
    return ((completedChunks + partialChunk) / totalChunks).clamp(0.0, 1.0);
  }
}

typedef InferenceProgressCallback =
    void Function(MuscriptorInferenceProgress progress);

class MuscriptorOnnxRunner {
  MuscriptorOnnxRunner({this.maxTokensPerChunk = 1024})
    : assert(maxTokensPerChunk > 0);

  final int maxTokensPerChunk;
  final OnnxRuntime _runtime = OnnxRuntime();

  OrtSession? _conditioner;
  OrtSession? _decoder;
  String? _loadedModelKey;
  Map<String, OrtValue>? _reusableKvCaches;
  int? _reusableKvCacheLength;

  Future<MuscriptorTranscription> transcribe({
    required Float32List samples,
    required MuscriptorModelPaths model,
    InferenceProgressCallback? onProgress,
  }) async {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', '音频不能为空');
    }

    final chunkCount = (samples.length / muscriptorSegmentSamples).ceil();
    final audioDuration = Duration(
      microseconds:
          samples.length *
          Duration.microsecondsPerSecond ~/
          muscriptorSampleRate,
    );
    final stopwatch = Stopwatch()..start();
    final tokenDecoder = MuscriptorTokenDecoder();
    var generatedTokenCount = 0;

    onProgress?.call(
      MuscriptorInferenceProgress(
        completedChunks: 0,
        totalChunks: chunkCount,
        generatedTokensInChunk: 0,
        message: '正在加载量化模型…',
      ),
    );
    final sessionWatch = Stopwatch()..start();
    final reusedSessions = await _ensureSessions(model);
    sessionWatch.stop();
    _perfLog(
      'sessions ${reusedSessions ? 'reused' : 'loaded'} '
      'in ${sessionWatch.elapsedMilliseconds} ms',
    );
    final conditioner = _conditioner!;
    final decoder = _decoder!;

    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      final chunk = Float32List(muscriptorSegmentSamples);
      final start = chunkIndex * muscriptorSegmentSamples;
      final available = math.min(
        muscriptorSegmentSamples,
        samples.length - start,
      );
      chunk.setRange(0, available, samples, start);
      onProgress?.call(
        MuscriptorInferenceProgress(
          completedChunks: chunkIndex,
          totalChunks: chunkCount,
          generatedTokensInChunk: 0,
          message: '正在分析第 ${chunkIndex + 1}/$chunkCount 个音频片段…',
        ),
      );
      final frontendWatch = Stopwatch()..start();
      final logMel = await compute(buildMuscriptorLogMel, chunk);
      frontendWatch.stop();
      _perfLog(
        'chunk=${chunkIndex + 1}/$chunkCount log-mel '
        '${frontendWatch.elapsedMilliseconds} ms',
      );
      tokenDecoder.beginChunk(
        seekTime: chunkIndex * 5.0,
        nextSeekTime: chunkIndex + 1 < chunkCount
            ? (chunkIndex + 1) * 5.0
            : null,
      );
      final forcedPrelude = chunkIndex == 0
          ? const <int>[]
          : tokenDecoder.forcedTiePreludeTokens;
      final generated = await _runChunk(
        chunkIndex: chunkIndex,
        logMel: logMel,
        promptTokens: forcedPrelude,
        conditioner: conditioner,
        decoder: decoder,
        onToken: (tokenIndex, token) {
          tokenDecoder.feed(token);
          final generatedInChunk = tokenIndex - forcedPrelude.length;
          if (generatedInChunk <= 0) return;
          generatedTokenCount++;
          if (generatedInChunk == 1 || generatedInChunk % 10 == 0) {
            onProgress?.call(
              MuscriptorInferenceProgress(
                completedChunks: chunkIndex,
                totalChunks: chunkCount,
                generatedTokensInChunk: generatedInChunk,
                message:
                    '第 ${chunkIndex + 1}/$chunkCount 段：'
                    '已生成 $generatedInChunk 个音乐 token',
              ),
            );
          }
        },
      );
      onProgress?.call(
        MuscriptorInferenceProgress(
          completedChunks: chunkIndex + 1,
          totalChunks: chunkCount,
          generatedTokensInChunk: 0,
          message: generated.hitLimit
              ? '第 ${chunkIndex + 1} 段达到 token 上限，继续处理下一段…'
              : '已完成第 ${chunkIndex + 1}/$chunkCount 段',
        ),
      );
    }

    final notes = tokenDecoder.finish();
    stopwatch.stop();
    return MuscriptorTranscription(
      notes: notes,
      audioDuration: audioDuration,
      chunkCount: chunkCount,
      generatedTokenCount: generatedTokenCount,
      elapsed: stopwatch.elapsed,
    );
  }

  Future<void> close() async {
    final decoder = _decoder;
    final conditioner = _conditioner;
    final kvCaches = _reusableKvCaches;
    _decoder = null;
    _conditioner = null;
    _loadedModelKey = null;
    _reusableKvCaches = null;
    _reusableKvCacheLength = null;
    await Future.wait(<Future<void>>[
      if (kvCaches != null) _disposeValues(kvCaches.values),
      if (decoder != null) decoder.close(),
      if (conditioner != null) conditioner.close(),
    ]);
  }

  Future<bool> _ensureSessions(MuscriptorModelPaths model) async {
    final key = '${model.conditioner}\n${model.decoder}';
    if (_loadedModelKey == key && _conditioner != null && _decoder != null) {
      return true;
    }
    await close();
    final options = OrtSessionOptions(
      intraOpNumThreads: 4,
      interOpNumThreads: 1,
      providers: const <OrtProvider>[OrtProvider.CPU],
      useArena: true,
    );
    OrtSession? conditioner;
    OrtSession? decoder;
    try {
      conditioner = await _runtime.createSession(
        model.conditioner,
        options: options,
      );
      decoder = await _runtime.createSession(model.decoder, options: options);
      _conditioner = conditioner;
      _decoder = decoder;
      _loadedModelKey = key;
      return false;
    } catch (_) {
      if (_conditioner != null || _decoder != null) {
        await close();
      } else {
        await decoder?.close();
        await conditioner?.close();
      }
      rethrow;
    }
  }

  Future<_ChunkGenerationResult> _runChunk({
    required int chunkIndex,
    required Float32List logMel,
    required List<int> promptTokens,
    required OrtSession conditioner,
    required OrtSession decoder,
    required void Function(int tokenIndex, int token) onToken,
  }) async {
    final uploadWatch = Stopwatch()..start();
    final logMelTensor = await OrtValue.fromList(logMel, const <int>[
      1,
      muscriptorFramesPerChunk,
      muscriptorMelBins,
    ]);
    uploadWatch.stop();
    _perfLog(
      'chunk=${chunkIndex + 1} log-mel upload '
      '${uploadWatch.elapsedMicroseconds / 1000.0} ms',
    );
    final instrumentIds = await OrtValue.fromList(
      Int64List.fromList(const <int>[-1]),
      const <int>[1, 1],
    );
    final datasetIds = await OrtValue.fromList(
      Int64List.fromList(const <int>[-1]),
      const <int>[1, 1],
    );

    late OrtValue condition;
    final conditionerWatch = Stopwatch()..start();
    try {
      final outputs = await conditioner.run(<String, OrtValue>{
        'log_mel': logMelTensor,
        'instrument_ids': instrumentIds,
        'dataset_ids': datasetIds,
      });
      final output = outputs.remove('condition_embeddings');
      if (output == null) {
        await _disposeValues(outputs.values);
        throw StateError('conditioner 未返回 condition_embeddings');
      }
      condition = output;
      await _disposeValues(outputs.values);
    } finally {
      await logMelTensor.dispose();
      await instrumentIds.dispose();
      await datasetIds.dispose();
    }
    conditionerWatch.stop();
    _perfLog(
      'chunk=${chunkIndex + 1} conditioner+cleanup '
      '${conditionerWatch.elapsedMicroseconds / 1000.0} ms',
    );

    if (condition.shape.length != 3 ||
        condition.shape[0] != 1 ||
        condition.shape[1] <= 0 ||
        condition.shape[2] != _conditionDimension) {
      await condition.dispose();
      throw StateError('condition_embeddings 形状不符合预期：${condition.shape}');
    }
    final conditionLength = condition.shape[1];
    if (promptTokens.length >= maxTokensPerChunk) {
      await condition.dispose();
      throw StateError(
        '跨块 tie prompt 长度 ${promptTokens.length} '
        '已达到 token 上限 $maxTokensPerChunk',
      );
    }
    final cacheLength = conditionLength + maxTokensPerChunk + 1;
    if (cacheLength > _maxPositionLength) {
      await condition.dispose();
      throw StateError('KV cache 长度 $cacheLength 超过模型上限 $_maxPositionLength');
    }

    final cacheWatch = Stopwatch()..start();
    late _KvCacheLease cacheLease;
    try {
      cacheLease = await _leaseKvCaches(cacheLength);
    } catch (_) {
      await condition.dispose();
      rethrow;
    }
    var caches = cacheLease.values;
    cacheWatch.stop();
    _perfLog(
      'chunk=${chunkIndex + 1} '
      '${cacheLease.reused ? 'reused' : 'allocated'} '
      '${_kvCacheMiB(cacheLength)} MiB '
      'FP32 KV cache in ${cacheWatch.elapsedMilliseconds} ms',
    );

    try {
      final emptyCondition = await OrtValue.fromList(
        Float32List(0),
        const <int>[1, 0, _conditionDimension],
      );
      var nextToken = muscriptorInitialToken;
      var emittedEos = false;
      var measuredSteps = 0;
      var setupMicrosTotal = 0;
      var runMicrosTotal = 0;
      var logitsMicrosTotal = 0;
      var cleanupMicrosTotal = 0;

      try {
        for (var index = 0; index < promptTokens.length; index++) {
          onToken(index + 1, promptTokens[index]);
        }
        final generationBudget = maxTokensPerChunk - promptTokens.length;
        final initialInputLength = promptTokens.length + 1;
        for (var step = 0; step < generationBudget; step++) {
          final stepWatch = Stopwatch()..start();
          final prefix = step == 0 ? condition : emptyCondition;
          final inputTokenValues = step == 0
              ? <int>[muscriptorInitialToken, ...promptTokens]
              : <int>[nextToken];
          final queryLength = prefix.shape[1] + inputTokenValues.length;
          final pastLength = step == 0
              ? 0
              : conditionLength + initialInputLength + step - 1;
          final totalLength = pastLength + queryLength;
          if (totalLength > cacheLength) {
            throw StateError('解码序列长度 $totalLength 超过 KV cache 容量 $cacheLength');
          }
          final setupWatch = Stopwatch()..start();
          final inputIds = await OrtValue.fromList(
            Int64List.fromList(inputTokenValues),
            <int>[1, inputTokenValues.length],
          );
          final positionIds = await OrtValue.fromList(
            Int64List.fromList(
              List<int>.generate(
                queryLength,
                (index) => pastLength + index,
                growable: false,
              ),
            ),
            <int>[1, queryLength],
          );
          final sequenceLengths = await OrtValue.fromList(
            Int32List.fromList(<int>[totalLength - 1]),
            const <int>[1],
          );
          final totalSequenceLength = await OrtValue.fromList(
            Int32List.fromList(<int>[totalLength]),
            const <int>[],
          );
          setupWatch.stop();

          late Map<String, OrtValue> outputs;
          final runWatch = Stopwatch()..start();
          var inputCleanupMicros = 0;
          try {
            outputs = await decoder.run(
              <String, OrtValue>{
                ...caches,
                'input_ids': inputIds,
                'condition_embeddings': prefix,
                'position_ids': positionIds,
                'seqlens_k': sequenceLengths,
                'total_sequence_length': totalSequenceLength,
              },
              requestedOutputs: const <String>{'logits'},
              pinnedOutputs: _pinnedKvOutputs(caches),
            );
          } finally {
            runWatch.stop();
            final inputCleanupWatch = Stopwatch()..start();
            await inputIds.dispose();
            await positionIds.dispose();
            await sequenceLengths.dispose();
            await totalSequenceLength.dispose();
            inputCleanupWatch.stop();
            inputCleanupMicros = inputCleanupWatch.elapsedMicroseconds;
          }

          final logits = outputs.remove('logits');
          if (logits == null) {
            await _disposeValues(outputs.values);
            throw StateError('decoder 未返回 logits');
          }
          final logitsWatch = Stopwatch()..start();
          late int bestToken;
          try {
            final values = await logits.asFlattenedList();
            if (values.length < muscriptorFirstReservedToken) {
              throw StateError('logits 长度不足：${values.length}');
            }
            bestToken = 0;
            var bestValue = double.negativeInfinity;
            for (var token = 0; token < muscriptorFirstReservedToken; token++) {
              final value = (values[token] as num).toDouble();
              if (value > bestValue) {
                bestValue = value;
                bestToken = token;
              }
            }
          } finally {
            await logits.dispose();
          }
          logitsWatch.stop();

          final returnedCaches = await _takeReturnedKvCaches(outputs);
          if (returnedCaches != null) {
            if (cacheLease.reusable) {
              await _disposeValues(returnedCaches.values);
              await _disposeValues(outputs.values);
              outputs.clear();
              throw StateError('Android decoder 未使用预分配的原地 KV 输出');
            }
            await _disposeValues(caches.values);
            caches = returnedCaches;
          }
          await _disposeValues(outputs.values);

          stepWatch.stop();
          measuredSteps++;
          final setupMicros = setupWatch.elapsedMicroseconds;
          final runMicros = runWatch.elapsedMicroseconds;
          final logitsMicros = logitsWatch.elapsedMicroseconds;
          final cleanupMicros = inputCleanupMicros;
          setupMicrosTotal += setupMicros;
          runMicrosTotal += runMicros;
          logitsMicrosTotal += logitsMicros;
          cleanupMicrosTotal += cleanupMicros;
          if (step == 0 ||
              measuredSteps % 10 == 0 ||
              bestToken == muscriptorEosToken) {
            _perfLog(
              'chunk=${chunkIndex + 1} step=$measuredSteps past=$pastLength '
              'setup=${_ms(setupMicros)} run=${_ms(runMicros)} '
              'logits=${_ms(logitsMicros)} cleanup=${_ms(cleanupMicros)} '
              'total=${_ms(stepWatch.elapsedMicroseconds)} token=$bestToken',
            );
          }

          if (bestToken == muscriptorEosToken) {
            emittedEos = true;
            break;
          }
          nextToken = bestToken;
          onToken(promptTokens.length + step + 1, bestToken);
        }
      } finally {
        await emptyCondition.dispose();
      }

      if (measuredSteps > 0) {
        _perfLog(
          'chunk=${chunkIndex + 1} summary steps=$measuredSteps '
          'avg_setup=${_ms(setupMicrosTotal ~/ measuredSteps)} '
          'avg_run=${_ms(runMicrosTotal ~/ measuredSteps)} '
          'avg_logits=${_ms(logitsMicrosTotal ~/ measuredSteps)} '
          'avg_cleanup=${_ms(cleanupMicrosTotal ~/ measuredSteps)}',
        );
      }
      return _ChunkGenerationResult(hitLimit: !emittedEos);
    } finally {
      if (!cacheLease.reusable) await _disposeValues(caches.values);
      await condition.dispose();
    }
  }

  Future<_KvCacheLease> _leaseKvCaches(int cacheLength) async {
    if (!_supportsReusableKvCache) {
      return _KvCacheLease(
        values: await _createKvCaches(cacheLength),
        reusable: false,
        reused: false,
      );
    }

    final existing = _reusableKvCaches;
    if (existing != null && _reusableKvCacheLength == cacheLength) {
      return _KvCacheLease(values: existing, reusable: true, reused: true);
    }
    _reusableKvCaches = null;
    _reusableKvCacheLength = null;
    if (existing != null) await _disposeValues(existing.values);

    final created = await _createKvCaches(cacheLength);
    _reusableKvCaches = created;
    _reusableKvCacheLength = cacheLength;
    return _KvCacheLease(values: created, reusable: true, reused: false);
  }
}

void _perfLog(String message) {
  if (kDebugMode) debugPrint('[MuScriptorPerf] $message');
}

String _ms(int microseconds) =>
    '${(microseconds / 1000.0).toStringAsFixed(1)}ms';

const _layerCount = 24;
const _attentionHeads = 16;
const _headDimension = 64;
const _conditionDimension = 1024;
const _maxPositionLength = 4096;

Future<Map<String, OrtValue>> _createKvCaches(int cacheLength) async {
  final caches = <String, OrtValue>{};
  try {
    for (var layer = 0; layer < _layerCount; layer++) {
      caches['past_key.$layer'] = await _zeroFloatTensor(<int>[
        1,
        _attentionHeads,
        cacheLength,
        _headDimension,
      ]);
      caches['past_value.$layer'] = await _zeroFloatTensor(<int>[
        1,
        _attentionHeads,
        cacheLength,
        _headDimension,
      ]);
    }
    return caches;
  } catch (_) {
    await _disposeValues(caches.values);
    rethrow;
  }
}

Future<OrtValue> _zeroFloatTensor(List<int> shape) {
  if (_supportsReusableKvCache) {
    return OrtValue.zeros(OrtDataType.float32, shape);
  }
  final elementCount = shape.fold<int>(1, (value, item) => value * item);
  return OrtValue.fromList(Float32List(elementCount), shape);
}

bool get _supportsReusableKvCache =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Map<String, OrtValue> _pinnedKvOutputs(Map<String, OrtValue> caches) {
  return <String, OrtValue>{
    for (var layer = 0; layer < _layerCount; layer++) ...<String, OrtValue>{
      'present_key.$layer': caches['past_key.$layer']!,
      'present_value.$layer': caches['past_value.$layer']!,
    },
  };
}

Future<Map<String, OrtValue>?> _takeReturnedKvCaches(
  Map<String, OrtValue> outputs,
) async {
  final returned = <String, OrtValue>{};
  for (var layer = 0; layer < _layerCount; layer++) {
    for (final kind in const <String>['key', 'value']) {
      final value = outputs.remove('present_$kind.$layer');
      if (value != null) returned['past_$kind.$layer'] = value;
    }
  }
  if (returned.isEmpty) return null;
  if (returned.length != _layerCount * 2) {
    await _disposeValues(returned.values);
    await _disposeValues(outputs.values);
    outputs.clear();
    throw StateError(
      'decoder 只返回了 ${returned.length}/${_layerCount * 2} 个 KV cache',
    );
  }
  return returned;
}

Future<void> _disposeValues(Iterable<OrtValue> values) async {
  for (final value in values) {
    await value.dispose();
  }
}

String _kvCacheMiB(int cacheLength) {
  final bytes =
      _layerCount * 2 * _attentionHeads * cacheLength * _headDimension * 4;
  return (bytes / (1024 * 1024)).toStringAsFixed(1);
}

class _ChunkGenerationResult {
  const _ChunkGenerationResult({required this.hitLimit});

  final bool hitLimit;
}

class _KvCacheLease {
  const _KvCacheLease({
    required this.values,
    required this.reusable,
    required this.reused,
  });

  final Map<String, OrtValue> values;
  final bool reusable;
  final bool reused;
}
