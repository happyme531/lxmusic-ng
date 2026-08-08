import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

const muscriptorSampleRate = 16000;
const muscriptorSegmentSamples = 5 * muscriptorSampleRate;
const muscriptorFftSize = 2048;
const muscriptorHopLength = 160;
const muscriptorMelBins = 512;
const muscriptorFramesPerChunk = 501;

/// NumPy/PyTorch-compatible MuScriptor log-mel frontend.
///
/// The returned flat tensor has shape `[1, 501, 512]` in row-major order.
Float32List buildMuscriptorLogMel(Float32List input) {
  final audio = Float32List(muscriptorSegmentSamples);
  audio.setRange(0, math.min(input.length, audio.length), input);

  final fft = FFT(muscriptorFftSize);
  final window = Float64List(muscriptorFftSize);
  for (var i = 0; i < window.length; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / muscriptorFftSize);
  }
  final filters = _buildSparseMelFilters();
  final frame = Float64List(muscriptorFftSize);
  final output = Float32List(muscriptorFramesPerChunk * muscriptorMelBins);
  const reflectionPadding = muscriptorFftSize ~/ 2;

  for (
    var frameIndex = 0;
    frameIndex < muscriptorFramesPerChunk;
    frameIndex++
  ) {
    final frameStart = frameIndex * muscriptorHopLength - reflectionPadding;
    for (var i = 0; i < muscriptorFftSize; i++) {
      final sourceIndex = frameStart + i;
      final reflectedIndex = sourceIndex < 0
          ? -sourceIndex
          : sourceIndex >= audio.length
          ? 2 * audio.length - 2 - sourceIndex
          : sourceIndex;
      frame[i] = audio[reflectedIndex] * window[i];
    }

    final magnitudes = fft.realFft(frame).discardConjugates().magnitudes();
    final outputOffset = frameIndex * muscriptorMelBins;
    for (var melIndex = 0; melIndex < muscriptorMelBins; melIndex++) {
      var value = 0.0;
      final filter = filters[melIndex];
      for (var i = 0; i < filter.binIndices.length; i++) {
        value += magnitudes[filter.binIndices[i]] * filter.weights[i];
      }
      output[outputOffset + melIndex] = math.log(value + 1e-6);
    }
  }
  return output;
}

List<_SparseMelFilter> _buildSparseMelFilters() {
  double hzToMel(double frequency) =>
      2595.0 * math.log(1.0 + frequency / 700.0) / math.ln10;
  double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

  final melMin = hzToMel(0);
  final melMax = hzToMel(muscriptorSampleRate / 2);
  final points = List<double>.generate(
    muscriptorMelBins + 2,
    (index) =>
        melToHz(melMin + (melMax - melMin) * index / (muscriptorMelBins + 1)),
    growable: false,
  );
  final binWidth = muscriptorSampleRate / muscriptorFftSize;

  return List<_SparseMelFilter>.generate(muscriptorMelBins, (melIndex) {
    final left = points[melIndex];
    final center = points[melIndex + 1];
    final right = points[melIndex + 2];
    final firstBin = math.max(0, (left / binWidth).ceil());
    final lastBin = math.min(
      muscriptorFftSize ~/ 2,
      (right / binWidth).floor(),
    );
    final indices = <int>[];
    final weights = <double>[];
    for (var bin = firstBin; bin <= lastBin; bin++) {
      final frequency = bin * binWidth;
      final down = (frequency - left) / (center - left);
      final up = (right - frequency) / (right - center);
      final weight = math.max(0.0, math.min(down, up));
      if (weight > 0) {
        indices.add(bin);
        weights.add(weight);
      }
    }
    return _SparseMelFilter(
      Int32List.fromList(indices),
      Float64List.fromList(weights),
    );
  }, growable: false);
}

class _SparseMelFilter {
  const _SparseMelFilter(this.binIndices, this.weights);

  final Int32List binIndices;
  final Float64List weights;
}
