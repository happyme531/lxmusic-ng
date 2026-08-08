import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lxmusic_core/lxmusic_core.dart';

import '../services/muscriptor_token_decoder.dart';

class MuscriptorTranscription {
  const MuscriptorTranscription({
    required this.notes,
    required this.audioDuration,
    required this.chunkCount,
    required this.generatedTokenCount,
    required this.elapsed,
  });

  final List<MuscriptorDecodedNote> notes;
  final Duration audioDuration;
  final int chunkCount;
  final int generatedTokenCount;
  final Duration elapsed;

  int get trackCount => notes.map((note) => note.program).toSet().length;

  Uint8List toMidiBytes() => const MidiScoreEncoder().encode(toScore());

  Score toScore() {
    final cleaned = _trimOverlaps(notes);
    final byProgram = <int, List<MuscriptorDecodedNote>>{};
    for (final note in cleaned) {
      byProgram.putIfAbsent(note.program, () => []).add(note);
    }

    final programs = byProgram.keys.toList()..sort();
    final channels = <int>[
      ...List<int>.generate(9, (index) => index),
      ...List<int>.generate(6, (index) => index + 10),
    ];
    var channelIndex = 0;
    final tracks = <Track>[];
    for (final program in programs) {
      final isDrum = program == 128;
      final channel = isDrum
          ? 9
          : channels[math.min(channelIndex++, channels.length - 1)];
      final programNotes = byProgram[program]!
        ..sort((a, b) => a.onsetSeconds.compareTo(b.onsetSeconds));
      tracks.add(
        Track(
          name: _instrumentName(program),
          channel: channel,
          instrumentId: isDrum ? null : program.clamp(0, 127),
          notes: programNotes
              .map(
                (note) => NoteEvent(
                  pitch: note.pitch.clamp(0, 127),
                  startMs: (note.onsetSeconds * 1000).round(),
                  durationMs: math.max(
                    10,
                    ((note.offsetSeconds - note.onsetSeconds) * 1000).round(),
                  ),
                  velocity: 100,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    if (tracks.isEmpty) {
      tracks.add(
        const Track(name: 'MuScriptor 转录', channel: 0, notes: <NoteEvent>[]),
      );
    }
    return Score(
      tracks: tracks,
      format: SourceFormat.jsonScore,
      metadata: <String, Object?>{
        'generator': 'MuScriptor Medium W4A32 (ONNX Runtime)',
        'source': 'audio-transcription',
      },
    );
  }
}

List<MuscriptorDecodedNote> _trimOverlaps(List<MuscriptorDecodedNote> notes) {
  final grouped =
      <({int program, int pitch, bool drum}), List<MuscriptorDecodedNote>>{};
  for (final note in notes) {
    grouped
        .putIfAbsent((
          program: note.program,
          pitch: note.pitch,
          drum: note.isDrum,
        ), () => <MuscriptorDecodedNote>[])
        .add(note);
  }

  final result = <MuscriptorDecodedNote>[];
  for (final group in grouped.values) {
    group.sort((a, b) => a.onsetSeconds.compareTo(b.onsetSeconds));
    for (var i = 0; i < group.length; i++) {
      var note = group[i];
      if (!note.isDrum && i + 1 < group.length) {
        note = note.copyWith(
          offsetSeconds: math.min(
            note.offsetSeconds,
            group[i + 1].onsetSeconds,
          ),
        );
      }
      if (note.isDrum || note.offsetSeconds > note.onsetSeconds) {
        result.add(note);
      }
    }
  }
  result.sort((a, b) => a.onsetSeconds.compareTo(b.onsetSeconds));
  return result;
}

String _instrumentName(int program) => switch (program) {
  0 => '原声钢琴',
  2 => '电钢琴',
  8 => '半音阶打击乐',
  16 => '风琴',
  24 => '原声吉他',
  26 => '清音电吉他',
  29 => '失真电吉他',
  32 => '原声贝斯',
  33 => '电贝斯',
  40 => '小提琴',
  41 => '中提琴',
  42 => '大提琴',
  43 => '低音提琴',
  46 => '管弦乐竖琴',
  47 => '定音鼓',
  48 => '弦乐合奏',
  50 => '合成弦乐',
  52 => '人声',
  55 => '管弦乐重击',
  56 => '小号',
  57 => '长号',
  58 => '大号',
  60 => '圆号',
  61 => '铜管组',
  64 => '高音/中音萨克斯',
  66 => '次中音萨克斯',
  67 => '上低音萨克斯',
  68 => '双簧管',
  69 => '英国管',
  70 => '巴松',
  71 => '单簧管',
  72 => '长笛组',
  80 => '合成主音',
  88 => '合成音色',
  128 => '鼓组',
  _ => 'MIDI Program $program',
};
