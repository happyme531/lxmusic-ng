import 'dart:typed_data';

class DecodedAudio {
  const DecodedAudio({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;

  Duration get duration => Duration(
    microseconds:
        (samples.length * Duration.microsecondsPerSecond) ~/ sampleRate,
  );
}

abstract class AudioPcmDecoder {
  Future<DecodedAudio> decode(String path);
}
