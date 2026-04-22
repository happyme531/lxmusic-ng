import 'dart:typed_data';

import 'package:dart_midi_pro/dart_midi_pro.dart' as midi;

import '../domain/score.dart';

class MidiScoreEncoder {
  const MidiScoreEncoder({
    this.ticksPerBeat = 480,
    this.microsecondsPerBeat = 500000,
  });

  final int ticksPerBeat;
  final int microsecondsPerBeat;

  Uint8List encode(Score score) {
    final tracks = <List<midi.MidiEvent>>[];

    for (var trackIndex = 0; trackIndex < score.tracks.length; trackIndex++) {
      final track = score.tracks[trackIndex];
      final events = <({int tick, midi.MidiEvent event})>[];

      if (trackIndex == 0) {
        final tempo = midi.SetTempoEvent()
          ..deltaTime = 0
          ..microsecondsPerBeat = microsecondsPerBeat
          ..type = 'setTempo';
        events.add((tick: 0, event: tempo));
      }

      final trackName = midi.TrackNameEvent()
        ..deltaTime = 0
        ..text = track.name
        ..type = 'trackName';
      events.add((tick: 0, event: trackName));

      if (track.instrumentId != null) {
        final program = midi.ProgramChangeMidiEvent()
          ..deltaTime = 0
          ..channel = track.channel.clamp(0, 15)
          ..programNumber = track.instrumentId!
          ..type = 'programChange';
        events.add((tick: 0, event: program));
      }

      for (final note in track.notes) {
        final startTick = _msToTick(note.startMs);
        final durationMs =
            note.durationMs ?? (note.attrs['duration'] as int?) ?? 120;
        final endTick = _msToTick(note.startMs + durationMs);

        final noteOn = midi.NoteOnEvent()
          ..channel = track.channel.clamp(0, 15)
          ..noteNumber = note.pitch.clamp(0, 127)
          ..velocity = note.velocity.clamp(1, 127)
          ..type = 'noteOn';
        final noteOff = midi.NoteOffEvent()
          ..channel = track.channel.clamp(0, 15)
          ..noteNumber = note.pitch.clamp(0, 127)
          ..velocity = 0
          ..type = 'noteOff';

        events.add((tick: startTick, event: noteOn));
        events.add((
          tick: endTick > startTick ? endTick : startTick + 1,
          event: noteOff,
        ));
      }

      events.sort((a, b) => a.tick.compareTo(b.tick));
      final midiEvents = <midi.MidiEvent>[];
      var lastTick = 0;
      for (final item in events) {
        item.event.deltaTime = item.tick - lastTick;
        lastTick = item.tick;
        midiEvents.add(item.event);
      }
      midiEvents.add(
        midi.EndOfTrackEvent()
          ..deltaTime = 0
          ..type = 'endOfTrack',
      );
      tracks.add(midiEvents);
    }

    final midiFile = midi.MidiFile(
      tracks,
      midi.MidiHeader(
        format: 1,
        numTracks: tracks.length,
        ticksPerBeat: ticksPerBeat,
      ),
    );
    return Uint8List.fromList(midi.MidiWriter().writeMidiToBuffer(midiFile));
  }
  int _msToTick(int ms) {
    return ((ms * ticksPerBeat * 1000) / microsecondsPerBeat).round();
  }
}
