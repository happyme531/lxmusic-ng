import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_token_decoder.dart';

void main() {
  test('decodes the verified piano token prefix into a note', () {
    final decoder = MuscriptorTokenDecoder()
      ..beginChunk(seekTime: 0, nextSeekTime: null);
    for (final token in const <int>[
      1134, // tie terminator
      217, // shift 2.14 s
      1135, // program 0
      1133, // velocity on
      1076, // pitch 72
      235, // shift 2.32 s
      1132, // velocity off
      1076, // pitch 72
    ]) {
      decoder.feed(token);
    }

    final notes = decoder.finish();

    expect(notes, hasLength(1));
    expect(notes.single.program, 0);
    expect(notes.single.pitch, 72);
    expect(notes.single.onsetSeconds, closeTo(2.14, 1e-9));
    expect(notes.single.offsetSeconds, closeTo(2.32, 1e-9));
  });

  test('tie prologue sustains an open note across chunks', () {
    final decoder = MuscriptorTokenDecoder()
      ..beginChunk(seekTime: 0, nextSeekTime: 5);
    for (final token in const <int>[
      1134,
      103, // 1.00 s
      1135,
      1133,
      1064, // pitch 60
    ]) {
      decoder.feed(token);
    }

    decoder.beginChunk(seekTime: 5, nextSeekTime: null);
    for (final token in const <int>[
      1135,
      1064,
      1134, // the program/pitch pair is tied
      103, // 6.00 s absolute in this chunk
      1135,
      1132,
      1064,
    ]) {
      decoder.feed(token);
    }

    final notes = decoder.finish();
    expect(notes, hasLength(1));
    expect(notes.single.onsetSeconds, 1);
    expect(notes.single.offsetSeconds, 6);
  });

  test('teacher-forced tie prelude matches the PyTorch tokenizer order', () {
    final decoder = MuscriptorTokenDecoder()
      ..beginChunk(seekTime: 0, nextSeekTime: 5);
    for (final token in const <int>[
      1134,
      103,
      1137, // program 2
      1133,
      1068, // pitch 64
      1135, // program 0
      1064, // pitch 60
      1067, // pitch 63
    ]) {
      decoder.feed(token);
    }

    decoder.beginChunk(seekTime: 5, nextSeekTime: null);

    expect(decoder.forcedTiePreludeTokens, const <int>[
      1135, // program 0 sorts first and is emitted once
      1064, // pitch 60
      1067, // pitch 63
      1137, // program 2
      1068, // pitch 64
      1134, // tie terminator
    ]);
  });

  test('an empty teacher-forced prelude still terminates the tie section', () {
    final decoder = MuscriptorTokenDecoder()
      ..beginChunk(seekTime: 0, nextSeekTime: 5)
      ..feed(1134)
      ..beginChunk(seekTime: 5, nextSeekTime: null);

    expect(decoder.forcedTiePreludeTokens, const <int>[1134]);
  });
}
