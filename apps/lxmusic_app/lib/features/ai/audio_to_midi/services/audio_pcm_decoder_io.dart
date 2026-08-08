import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_pcm_decoder.dart';

AudioPcmDecoder createAudioPcmDecoder() => NativeAudioPcmDecoder();

class NativeAudioPcmDecoder implements AudioPcmDecoder {
  static const _sampleRate = 16000;

  @override
  Future<DecodedAudio> decode(String path) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final wavFile = File(
      '${temporaryDirectory.path}/lxmusic-muscriptor-'
      '${DateTime.now().microsecondsSinceEpoch}.wav',
    );

    try {
      final outputPath = await AudioDecoder.convertToWav(
        path,
        wavFile.path,
        sampleRate: _sampleRate,
        channels: 1,
        bitDepth: 16,
      );
      final bytes = await File(outputPath).readAsBytes();
      return _decodePcm16Wav(bytes);
    } finally {
      if (await wavFile.exists()) {
        await wavFile.delete();
      }
    }
  }

  DecodedAudio _decodePcm16Wav(Uint8List bytes) {
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw const FormatException('音频解码器返回了无效的 WAV 文件');
    }

    final data = ByteData.sublistView(bytes);
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitDepth;
    int? pcmOffset;
    int? pcmLength;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkLength = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      if (chunkStart + chunkLength > bytes.length) {
        throw const FormatException('WAV chunk 长度越界');
      }
      if (id == 'fmt ' && chunkLength >= 16) {
        audioFormat = data.getUint16(chunkStart, Endian.little);
        channels = data.getUint16(chunkStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkStart + 4, Endian.little);
        bitDepth = data.getUint16(chunkStart + 14, Endian.little);
      } else if (id == 'data') {
        pcmOffset = chunkStart;
        pcmLength = chunkLength;
      }
      offset = chunkStart + chunkLength + (chunkLength.isOdd ? 1 : 0);
    }

    if (audioFormat != 1 ||
        channels != 1 ||
        sampleRate != _sampleRate ||
        bitDepth != 16 ||
        pcmOffset == null ||
        pcmLength == null) {
      throw FormatException(
        'WAV 参数不符合 MuScriptor 输入要求：'
        'format=$audioFormat channels=$channels '
        'sampleRate=$sampleRate bitDepth=$bitDepth',
      );
    }

    final sampleCount = pcmLength ~/ 2;
    final samples = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(pcmOffset + i * 2, Endian.little) / 32768.0;
    }
    return DecodedAudio(samples: samples, sampleRate: _sampleRate);
  }
}
