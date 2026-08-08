import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/providers/audio_to_midi_provider.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/models/muscriptor_transcription.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_token_decoder.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
  test('uses the source audio name for the automatic library MIDI', () {
    expect(muscriptorMidiFileName('钢琴录音.final.mp3'), '钢琴录音.final.mid');
    expect(muscriptorMidiFileName(r'C:\Music\demo.wav'), 'demo.mid');
    expect(muscriptorMidiFileName(null), 'transcription.mid');
  });

  test('adds a numbered suffix instead of overwriting a library MIDI', () {
    expect(
      uniqueMuscriptorMidiFileName('demo.mid', const <String>[
        'DEMO.MID',
        'demo (1).mid',
        'another.mid',
      ]),
      'demo (2).mid',
    );
    expect(
      uniqueMuscriptorMidiFileName('new.mid', const <String>['demo.mid']),
      'new.mid',
    );
  });

  test('writes a parseable multi-track MIDI result', () {
    const result = MuscriptorTranscription(
      notes: <MuscriptorDecodedNote>[
        MuscriptorDecodedNote(
          program: 0,
          pitch: 60,
          onsetSeconds: 0.5,
          offsetSeconds: 1.25,
        ),
        MuscriptorDecodedNote(
          program: 40,
          pitch: 67,
          onsetSeconds: 1.0,
          offsetSeconds: 2.0,
        ),
        MuscriptorDecodedNote(
          program: 128,
          pitch: 36,
          onsetSeconds: 0.75,
          offsetSeconds: 0.76,
          isDrum: true,
        ),
      ],
      audioDuration: Duration(seconds: 2),
      chunkCount: 1,
      generatedTokenCount: 12,
      elapsed: Duration(milliseconds: 500),
    );

    final bytes = result.toMidiBytes();
    final parsed = const MidiScoreParser().parse(bytes);

    expect(String.fromCharCodes(bytes.take(4)), 'MThd');
    expect(parsed.totalNoteCount, 3);
    expect(parsed.tracks.map((track) => track.channel), contains(9));
  });
}
