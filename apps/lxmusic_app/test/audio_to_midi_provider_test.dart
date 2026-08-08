import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/platform/file_store.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/models/muscriptor_transcription.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/providers/audio_to_midi_provider.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/audio_pcm_decoder.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_model_repository.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_onnx_runner.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_token_decoder.dart';
import 'package:lxmusic_app/features/library/providers/music_library_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('only conversion tasks are reported as converting', () {
    const base = AudioToMidiState(modelReady: false, modelCachePresent: false);

    expect(
      base.copyWith(task: AudioToMidiTask.downloadingModel).isConverting,
      isFalse,
    );
    expect(
      base.copyWith(task: AudioToMidiTask.clearingModelCache).isConverting,
      isFalse,
    );
    expect(
      base.copyWith(task: AudioToMidiTask.decodingAudio).isConverting,
      isTrue,
    );
    expect(
      base.copyWith(task: AudioToMidiTask.transcribing).isConverting,
      isTrue,
    );
    expect(
      base.copyWith(task: AudioToMidiTask.savingToLibrary).isConverting,
      isTrue,
    );
  });

  test('conversion automatically imports MIDI without overwriting', () async {
    final fileStore = _MemoryFileStore();
    final container = ProviderContainer(
      overrides: [
        fileStoreProvider.overrideWithValue(fileStore),
        muscriptorModelRepositoryProvider.overrideWithValue(
          _ReadyModelRepository(),
        ),
        audioPcmDecoderProvider.overrideWithValue(_FakeAudioDecoder()),
        muscriptorOnnxRunnerProvider.overrideWithValue(_FakeOnnxRunner()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(audioToMidiProvider.future);
    final notifier = container.read(audioToMidiProvider.notifier)
      ..selectAudio(path: '/audio/demo.wav', name: 'demo.wav')
      ..setRightsConfirmed(true);

    await notifier.convert();
    expect(
      container.read(audioToMidiProvider).value!.savedMidiFileName,
      'demo.mid',
    );

    await notifier.convert();
    expect(
      container.read(audioToMidiProvider).value!.savedMidiFileName,
      'demo (1).mid',
    );

    final library = container.read(musicLibraryProvider).value!;
    expect(library.files.map((file) => file.fileName).toSet(), <String>{
      'demo.mid',
      'demo (1).mid',
    });
    expect(
      fileStore.files.keys,
      containsAll(<String>['memory://demo.mid', 'memory://demo (1).mid']),
    );
  });
}

class _ReadyModelRepository implements MuscriptorModelRepository {
  @override
  Future<void> clearCache() async {}

  @override
  Future<MuscriptorModelPaths> download({
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  }) async => paths();

  @override
  Future<bool> hasCache() async => true;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<MuscriptorModelPaths> paths() async => const MuscriptorModelPaths(
    directory: '/model',
    conditioner: '/model/conditioner.onnx',
    decoder: '/model/decoder.onnx',
  );
}

class _FakeAudioDecoder implements AudioPcmDecoder {
  @override
  Future<DecodedAudio> decode(String path) async {
    return DecodedAudio(samples: Float32List(160), sampleRate: 16000);
  }
}

class _FakeOnnxRunner extends MuscriptorOnnxRunner {
  @override
  Future<MuscriptorTranscription> transcribe({
    required Float32List samples,
    required MuscriptorModelPaths model,
    InferenceProgressCallback? onProgress,
  }) async {
    return const MuscriptorTranscription(
      notes: <MuscriptorDecodedNote>[
        MuscriptorDecodedNote(
          program: 0,
          pitch: 60,
          onsetSeconds: 0,
          offsetSeconds: 0.5,
        ),
      ],
      audioDuration: Duration(milliseconds: 500),
      chunkCount: 1,
      generatedTokenCount: 8,
      elapsed: Duration(milliseconds: 20),
    );
  }
}

class _MemoryFileStore implements PlatformFileStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<String> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = 'memory://$fileName';
    files[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<String> importFile({
    required String sourcePath,
    required String fileName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    return Uint8List.fromList(files[path]!);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    files[path] = Uint8List.fromList(bytes);
  }
}
