import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/file_store.dart';
import '../../../library/providers/music_library_provider.dart';
import '../models/muscriptor_transcription.dart';
import '../services/audio_pcm_decoder.dart';
import '../services/audio_pcm_decoder_factory.dart';
import '../services/muscriptor_model_repository.dart';
import '../services/muscriptor_model_repository_factory.dart';
import '../services/muscriptor_onnx_runner.dart';

final muscriptorModelRepositoryProvider = Provider<MuscriptorModelRepository>(
  (ref) => createDefaultMuscriptorModelRepository(),
);

final audioPcmDecoderProvider = Provider<AudioPcmDecoder>(
  (ref) => createAudioPcmDecoder(),
);

final muscriptorOnnxRunnerProvider = Provider<MuscriptorOnnxRunner>((ref) {
  final runner = MuscriptorOnnxRunner();
  ref.onDispose(() => unawaited(runner.close()));
  return runner;
});

final audioToMidiProvider =
    AsyncNotifierProvider<AudioToMidiNotifier, AudioToMidiState>(
      AudioToMidiNotifier.new,
    );

enum AudioToMidiTask {
  idle,
  downloadingModel,
  clearingModelCache,
  decodingAudio,
  transcribing,
  savingToLibrary,
}

class AudioToMidiState {
  const AudioToMidiState({
    required this.modelReady,
    required this.modelCachePresent,
    this.selectedAudioPath,
    this.selectedAudioName,
    this.rightsConfirmed = false,
    this.task = AudioToMidiTask.idle,
    this.progress = 0,
    this.statusMessage = '',
    this.result,
    this.savedMidiFileName,
    this.errorMessage,
  });

  final bool modelReady;
  final bool modelCachePresent;
  final String? selectedAudioPath;
  final String? selectedAudioName;
  final bool rightsConfirmed;
  final AudioToMidiTask task;
  final double progress;
  final String statusMessage;
  final MuscriptorTranscription? result;
  final String? savedMidiFileName;
  final String? errorMessage;

  bool get isBusy => task != AudioToMidiTask.idle;

  bool get isConverting => switch (task) {
    AudioToMidiTask.decodingAudio ||
    AudioToMidiTask.transcribing ||
    AudioToMidiTask.savingToLibrary => true,
    _ => false,
  };

  bool get canConvert =>
      modelReady && selectedAudioPath != null && rightsConfirmed && !isBusy;

  AudioToMidiState copyWith({
    bool? modelReady,
    bool? modelCachePresent,
    Object? selectedAudioPath = _unset,
    Object? selectedAudioName = _unset,
    bool? rightsConfirmed,
    AudioToMidiTask? task,
    double? progress,
    String? statusMessage,
    Object? result = _unset,
    Object? savedMidiFileName = _unset,
    Object? errorMessage = _unset,
  }) {
    return AudioToMidiState(
      modelReady: modelReady ?? this.modelReady,
      modelCachePresent: modelCachePresent ?? this.modelCachePresent,
      selectedAudioPath: identical(selectedAudioPath, _unset)
          ? this.selectedAudioPath
          : selectedAudioPath as String?,
      selectedAudioName: identical(selectedAudioName, _unset)
          ? this.selectedAudioName
          : selectedAudioName as String?,
      rightsConfirmed: rightsConfirmed ?? this.rightsConfirmed,
      task: task ?? this.task,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      result: identical(result, _unset)
          ? this.result
          : result as MuscriptorTranscription?,
      savedMidiFileName: identical(savedMidiFileName, _unset)
          ? this.savedMidiFileName
          : savedMidiFileName as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _unset = Object();

class AudioToMidiNotifier extends AsyncNotifier<AudioToMidiState> {
  static const _runtimeIdleTimeout = Duration(minutes: 1);

  Timer? _runtimeReleaseTimer;

  @override
  Future<AudioToMidiState> build() async {
    ref.onDispose(() => _runtimeReleaseTimer?.cancel());
    final repository = ref.read(muscriptorModelRepositoryProvider);
    final ready = await repository.isReady();
    final cachePresent = await repository.hasCache();
    return AudioToMidiState(modelReady: ready, modelCachePresent: cachePresent);
  }

  void selectAudio({required String path, required String name}) {
    final current = state.value;
    if (current == null || current.isBusy) return;
    state = AsyncData(
      current.copyWith(
        selectedAudioPath: path,
        selectedAudioName: name,
        result: null,
        savedMidiFileName: null,
        errorMessage: null,
        progress: 0,
        statusMessage: '',
      ),
    );
  }

  void setRightsConfirmed(bool value) {
    final current = state.value;
    if (current == null || current.isBusy) return;
    state = AsyncData(current.copyWith(rightsConfirmed: value));
  }

  Future<void> downloadModel() async {
    final current = state.value;
    if (current == null || current.isBusy || current.modelReady) return;
    state = AsyncData(
      current.copyWith(
        task: AudioToMidiTask.downloadingModel,
        progress: 0,
        statusMessage: '准备下载 MuScriptor Medium W4A32…',
        errorMessage: null,
      ),
    );

    try {
      await ref
          .read(muscriptorModelRepositoryProvider)
          .download(
            onStatus: (message) {
              final latest = state.value;
              if (latest == null) return;
              state = AsyncData(latest.copyWith(statusMessage: message));
            },
            onProgress: (received, total, fileName) {
              final latest = state.value;
              if (latest == null) return;
              state = AsyncData(
                latest.copyWith(
                  progress: total == 0 ? 0 : received / total,
                  modelCachePresent: received > 0 || latest.modelCachePresent,
                  statusMessage: '正在下载 $fileName',
                ),
              );
            },
          );
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          modelReady: true,
          modelCachePresent: true,
          task: AudioToMidiTask.idle,
          progress: 1,
          statusMessage: '模型已下载并通过 SHA-256 校验',
          errorMessage: null,
        ),
      );
    } catch (error) {
      var fallback = state.value ?? current;
      try {
        fallback = fallback.copyWith(
          modelCachePresent: await ref
              .read(muscriptorModelRepositoryProvider)
              .hasCache(),
        );
      } catch (_) {}
      _fail(error, fallback: fallback);
    }
  }

  Future<bool> clearModelCache() async {
    final current = state.value;
    if (current == null || current.isBusy || !current.modelCachePresent) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        task: AudioToMidiTask.clearingModelCache,
        progress: 0,
        statusMessage: '正在清除 AI 模型缓存…',
        errorMessage: null,
      ),
    );

    try {
      _runtimeReleaseTimer?.cancel();
      await ref.read(muscriptorOnnxRunnerProvider).close();
      await ref.read(muscriptorModelRepositoryProvider).clearCache();
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          modelReady: false,
          modelCachePresent: false,
          task: AudioToMidiTask.idle,
          progress: 0,
          statusMessage: '',
          errorMessage: null,
        ),
      );
      return true;
    } catch (error) {
      _fail(error, fallback: current);
      return false;
    }
  }

  Future<void> convert() async {
    final current = state.value;
    if (current == null || !current.canConvert) return;
    _runtimeReleaseTimer?.cancel();
    state = AsyncData(
      current.copyWith(
        task: AudioToMidiTask.decodingAudio,
        progress: 0.01,
        statusMessage: '正在解码为 16 kHz 单声道音频…',
        result: null,
        savedMidiFileName: null,
        errorMessage: null,
      ),
    );

    try {
      final decoded = await ref
          .read(audioPcmDecoderProvider)
          .decode(current.selectedAudioPath!);
      if (decoded.sampleRate != 16000) {
        throw StateError('音频解码采样率异常：${decoded.sampleRate} Hz');
      }
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          task: AudioToMidiTask.transcribing,
          progress: 0.05,
          statusMessage: '音频解码完成，正在启动 ONNX Runtime…',
        ),
      );

      final model = await ref.read(muscriptorModelRepositoryProvider).paths();
      final result = await ref
          .read(muscriptorOnnxRunnerProvider)
          .transcribe(
            samples: decoded.samples,
            model: model,
            onProgress: (inference) {
              final value = state.value;
              if (value == null) return;
              state = AsyncData(
                value.copyWith(
                  task: AudioToMidiTask.transcribing,
                  progress: 0.05 + inference.fraction * 0.95,
                  statusMessage: inference.message,
                ),
              );
            },
          );
      final midiFileName = muscriptorMidiFileName(current.selectedAudioName);
      final readyToSave = state.value ?? current;
      state = AsyncData(
        readyToSave.copyWith(
          task: AudioToMidiTask.savingToLibrary,
          progress: 0.99,
          statusMessage: '转换完成，正在保存 $midiFileName 到曲库…',
          result: result,
          savedMidiFileName: null,
          errorMessage: null,
        ),
      );
      final savedMidiFileName = await _importResult(result, midiFileName);
      final finished = state.value ?? readyToSave;
      state = AsyncData(
        finished.copyWith(
          task: AudioToMidiTask.idle,
          progress: 1,
          statusMessage: '已自动保存到曲库：$savedMidiFileName',
          result: result,
          savedMidiFileName: savedMidiFileName,
          errorMessage: null,
        ),
      );
    } catch (error) {
      _fail(error, fallback: current);
    } finally {
      _scheduleRuntimeRelease();
    }
  }

  Future<bool> saveCurrentResultToLibrary() async {
    final current = state.value;
    final result = current?.result;
    if (current == null || result == null || current.isBusy) return false;
    final midiFileName = muscriptorMidiFileName(current.selectedAudioName);
    state = AsyncData(
      current.copyWith(
        task: AudioToMidiTask.savingToLibrary,
        progress: 0.99,
        statusMessage: '正在保存 $midiFileName 到曲库…',
        savedMidiFileName: null,
        errorMessage: null,
      ),
    );
    try {
      final savedMidiFileName = await _importResult(result, midiFileName);
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          task: AudioToMidiTask.idle,
          progress: 1,
          statusMessage: '已自动保存到曲库：$savedMidiFileName',
          savedMidiFileName: savedMidiFileName,
          errorMessage: null,
        ),
      );
      return true;
    } catch (error) {
      _fail(error, fallback: current);
      return false;
    }
  }

  Future<String> _importResult(
    MuscriptorTranscription result,
    String preferredMidiFileName,
  ) async {
    final library = await ref.read(musicLibraryProvider.future);
    final midiFileName = uniqueMuscriptorMidiFileName(
      preferredMidiFileName,
      library.files.map((file) => file.fileName),
    );
    final imported = await ref.read(musicLibraryProvider.notifier).importFiles(
      <PickedFileData>[
        PickedFileData(fileName: midiFileName, bytes: result.toMidiBytes()),
      ],
    );
    if (imported != 1) {
      throw StateError('无法将 $midiFileName 写入曲库');
    }
    return midiFileName;
  }

  void clearError() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(errorMessage: null));
  }

  void _scheduleRuntimeRelease() {
    _runtimeReleaseTimer?.cancel();
    _runtimeReleaseTimer = Timer(_runtimeIdleTimeout, () {
      _runtimeReleaseTimer = null;
      unawaited(ref.read(muscriptorOnnxRunnerProvider).close());
    });
  }

  void _fail(Object error, {required AudioToMidiState fallback}) {
    final latest = state.value ?? fallback;
    var message = error.toString();
    for (final prefix in const <String>[
      'Exception: ',
      'StateError: ',
      'FormatException: ',
    ]) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length);
        break;
      }
    }
    state = AsyncData(
      latest.copyWith(
        task: AudioToMidiTask.idle,
        progress: 0,
        statusMessage: '',
        errorMessage: message,
      ),
    );
  }
}

String muscriptorMidiFileName(String? sourceName) {
  final normalized = (sourceName ?? '').trim().replaceAll('\\', '/');
  final leaf = normalized.substring(normalized.lastIndexOf('/') + 1);
  final dot = leaf.lastIndexOf('.');
  final baseName = (dot > 0 ? leaf.substring(0, dot) : leaf).trim();
  return '${baseName.isEmpty ? 'transcription' : baseName}.mid';
}

String uniqueMuscriptorMidiFileName(
  String preferredName,
  Iterable<String> existingNames,
) {
  final occupied = existingNames.map((name) => name.toLowerCase()).toSet();
  if (!occupied.contains(preferredName.toLowerCase())) return preferredName;

  final dot = preferredName.lastIndexOf('.');
  final baseName = dot > 0 ? preferredName.substring(0, dot) : preferredName;
  final extension = dot > 0 ? preferredName.substring(dot) : '';
  for (var index = 1; ; index++) {
    final candidate = '$baseName ($index)$extension';
    if (!occupied.contains(candidate.toLowerCase())) return candidate;
  }
}
