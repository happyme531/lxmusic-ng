import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_audio_frontend.dart';

void main() {
  test('log-mel frontend matches the bundled NumPy reference', () {
    final audio = Float32List(muscriptorSegmentSamples);
    for (var i = 0; i < audio.length; i++) {
      final time = i / muscriptorSampleRate;
      audio[i] = 0.1 * math.sin(2 * math.pi * 440 * time);
    }

    final mel = buildMuscriptorLogMel(audio);

    expect(mel, hasLength(muscriptorFramesPerChunk * muscriptorMelBins));
    expect(mel[0], closeTo(-13.8155107, 1e-4));
    expect(mel[100], closeTo(2.8179591, 2e-3));
    expect(mel[110], closeTo(1.2067127, 2e-3));
    expect(mel[muscriptorMelBins + 110], closeTo(1.1516504, 2e-3));
    expect(mel[250 * muscriptorMelBins + 110], closeTo(-3.8957250, 2e-2));
    expect(mel[500 * muscriptorMelBins + 110], closeTo(1.1929122, 2e-3));
  });
}
