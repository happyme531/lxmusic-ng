import 'audio_pcm_decoder.dart';
import 'audio_pcm_decoder_stub.dart'
    if (dart.library.io) 'audio_pcm_decoder_io.dart'
    as platform;

AudioPcmDecoder createAudioPcmDecoder() => platform.createAudioPcmDecoder();
