import 'audio_pcm_decoder.dart';

AudioPcmDecoder createAudioPcmDecoder() => _UnsupportedAudioPcmDecoder();

class _UnsupportedAudioPcmDecoder implements AudioPcmDecoder {
  @override
  Future<DecodedAudio> decode(String path) {
    throw UnsupportedError('当前平台暂不支持音频解码');
  }
}
