import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:dart_midi_pro/dart_midi_pro.dart' as midi;

import '../../domain/score.dart';
import '../score_parser.dart';

class MidiScoreParser implements ScoreParser {
  const MidiScoreParser();

  @override
  String get formatId => 'midi';

  @override
  Score parse(Uint8List bytes) {
    final parseWatch = Stopwatch()..start();
    _logMidiParse('phase=decoder_start bytes=${bytes.length}');
    try {
      final midiFile = midi.MidiParser().parseMidiFromBuffer(bytes);
      final eventCount = midiFile.tracks.fold<int>(
        0,
        (total, track) => total + track.length,
      );
      _logMidiParse(
        'phase=decoder_done elapsed_ms=${parseWatch.elapsedMilliseconds} '
        'header_tracks=${midiFile.header.numTracks} '
        'decoded_tracks=${midiFile.tracks.length} events=$eventCount',
      );
      final ticksPerQuarter = midiFile.header.ticksPerBeat;
      if (ticksPerQuarter == null) {
        throw const FormatException('SMPTE MIDI timing is not supported.');
      }

      final parsedTracks = <_ParsedTrack>[];
      final tempoEvents = <_TempoEvent>[
        const _TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
      ];

      for (
        var trackIndex = 0;
        trackIndex < midiFile.tracks.length;
        trackIndex++
      ) {
        if (trackIndex == 0 ||
            trackIndex == midiFile.tracks.length - 1 ||
            trackIndex % 16 == 0) {
          _logMidiParse(
            'phase=track_events index=${trackIndex + 1}/${midiFile.tracks.length} '
            'events=${midiFile.tracks[trackIndex].length}',
          );
        }
        final parsedTrack = _parseTrackEvents(
          midiFile.tracks[trackIndex],
          trackIndex,
        );
        parsedTracks.add(parsedTrack);
        tempoEvents.addAll(parsedTrack.tempoEvents);
      }

      final tempoMap = _TempoMap.build(
        ticksPerQuarter: ticksPerQuarter,
        events: tempoEvents,
      );
      _logMidiParse(
        'phase=tempo_map_done elapsed_ms=${parseWatch.elapsedMilliseconds} '
        'tempo_events=${tempoEvents.length} entries=${tempoMap.entries.length}',
      );
      final tracks = <Track>[];

      for (var index = 0; index < parsedTracks.length; index++) {
        final parsedTrack = parsedTracks[index];
        final channelStates = <int, _ChannelTrackState>{};

        for (final event in parsedTrack.events) {
          if (event is _ProgramChangeEvent) {
            final state = channelStates.putIfAbsent(
              event.channel,
              () => _ChannelTrackState(
                name: parsedTrack.name ?? 'Track ${index + 1}',
                channel: event.channel,
              ),
            );
            state.instrumentId = event.program;
            continue;
          }

          if (event is! _NoteEventData) {
            continue;
          }

          final state = channelStates.putIfAbsent(
            event.channel,
            () => _ChannelTrackState(
              name: parsedTrack.name ?? 'Track ${index + 1}',
              channel: event.channel,
            ),
          );

          if (event.isNoteOn) {
            state.pendingNotes
                .putIfAbsent(event.note, () => <_PendingNote>[])
                .add(_PendingNote(tick: event.tick, velocity: event.velocity));
          } else {
            final candidates = state.pendingNotes[event.note];
            if (candidates == null || candidates.isEmpty) {
              continue;
            }
            final noteOn = candidates.removeAt(0);
            final startMs = tempoMap.tickToMs(noteOn.tick);
            final endMs = tempoMap.tickToMs(event.tick);
            state.notes.add(
              NoteEvent(
                pitch: event.note,
                startMs: startMs,
                durationMs: endMs - startMs,
                velocity: noteOn.velocity,
              ),
            );
          }
        }

        for (final state in channelStates.values) {
          state.notes.sort((a, b) => a.startMs.compareTo(b.startMs));
          if (state.notes.isEmpty) {
            continue;
          }
          tracks.add(
            Track(
              name: state.name,
              channel: state.channel,
              instrumentId: state.instrumentId,
              notes: state.notes,
            ),
          );
        }
      }

      final score = Score(
        tracks: tracks,
        format: SourceFormat.jsonScore,
        metadata: <String, Object?>{
          'source': formatId,
          'midiFormat': midiFile.header.format,
          'ticksPerQuarter': ticksPerQuarter,
          'tempoChangeCount': tempoMap.entries.length,
        },
      );
      _logMidiParse(
        'phase=score_done elapsed_ms=${parseWatch.elapsedMilliseconds} '
        'tracks=${score.tracks.length} notes=${score.totalNoteCount} '
        'duration_ms=${score.totalDurationMs}',
      );
      return score;
    } on FormatException {
      rethrow;
    } catch (error, stackTrace) {
      _logMidiParse(
        'phase=parse_error elapsed_ms=${parseWatch.elapsedMilliseconds} '
        'bytes=${bytes.length} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      throw FormatException('Invalid MIDI file: $error');
    }
  }

  _ParsedTrack _parseTrackEvents(List<midi.MidiEvent> events, int trackIndex) {
    var absoluteTick = 0;
    String? name;
    final parsedEvents = <_TimedMidiEvent>[];
    final tempoEvents = <_TempoEvent>[];

    for (final event in events) {
      absoluteTick += event.deltaTime;

      if (event is midi.TrackNameEvent) {
        name = event.text;
        continue;
      }
      if (event is midi.InstrumentNameEvent) {
        name ??= event.text;
        continue;
      }
      if (event is midi.SetTempoEvent) {
        tempoEvents.add(
          _TempoEvent(
            tick: absoluteTick,
            microsecondsPerQuarter: event.microsecondsPerBeat,
          ),
        );
        continue;
      }
      if (event is midi.ProgramChangeMidiEvent) {
        parsedEvents.add(
          _ProgramChangeEvent(
            tick: absoluteTick,
            channel: event.channel,
            program: event.programNumber,
          ),
        );
        continue;
      }
      if (event is midi.NoteOnEvent) {
        parsedEvents.add(
          _NoteEventData(
            tick: absoluteTick,
            channel: event.channel,
            note: event.noteNumber,
            velocity: event.velocity,
            isNoteOn: event.velocity > 0,
          ),
        );
        continue;
      }
      if (event is midi.NoteOffEvent) {
        parsedEvents.add(
          _NoteEventData(
            tick: absoluteTick,
            channel: event.channel,
            note: event.noteNumber,
            velocity: event.velocity,
            isNoteOn: false,
          ),
        );
        continue;
      }
      if (event is midi.NoteAfterTouchEvent ||
          event is midi.ControllerEvent ||
          event is midi.ChannelAfterTouchEvent ||
          event is midi.PitchBendEvent) {
        continue;
      }
    }

    return _ParsedTrack(
      name: name ?? 'Track ${trackIndex + 1}',
      events: parsedEvents,
      tempoEvents: tempoEvents,
    );
  }
}

void _logMidiParse(String message, {Object? error, StackTrace? stackTrace}) {
  developer.log(
    '[MIDI_PARSE] $message',
    name: 'lxmusic.midi',
    error: error,
    stackTrace: stackTrace,
  );
}

class _ParsedTrack {
  const _ParsedTrack({
    required this.name,
    required this.events,
    required this.tempoEvents,
  });

  final String? name;
  final List<_TimedMidiEvent> events;
  final List<_TempoEvent> tempoEvents;
}

sealed class _TimedMidiEvent {
  const _TimedMidiEvent({required this.tick, required this.channel});

  final int tick;
  final int channel;
}

class _NoteEventData extends _TimedMidiEvent {
  const _NoteEventData({
    required super.tick,
    required super.channel,
    required this.note,
    required this.velocity,
    required this.isNoteOn,
  });

  final int note;
  final int velocity;
  final bool isNoteOn;
}

class _ProgramChangeEvent extends _TimedMidiEvent {
  const _ProgramChangeEvent({
    required super.tick,
    required super.channel,
    required this.program,
  });

  final int program;
}

class _TempoEvent {
  const _TempoEvent({required this.tick, required this.microsecondsPerQuarter});

  final int tick;
  final int microsecondsPerQuarter;
}

class _TempoMapEntry {
  const _TempoMapEntry({
    required this.tick,
    required this.microsecondsPerQuarter,
    required this.accumulatedMicroseconds,
  });

  final int tick;
  final int microsecondsPerQuarter;
  final int accumulatedMicroseconds;
}

class _TempoMap {
  const _TempoMap(this.entries, this.ticksPerQuarter);

  final List<_TempoMapEntry> entries;
  final int ticksPerQuarter;

  factory _TempoMap.build({
    required int ticksPerQuarter,
    required List<_TempoEvent> events,
  }) {
    final sorted = events.toList()..sort((a, b) => a.tick.compareTo(b.tick));
    final deduped = <_TempoEvent>[];
    for (final event in sorted) {
      if (deduped.isNotEmpty && deduped.last.tick == event.tick) {
        deduped[deduped.length - 1] = event;
      } else {
        deduped.add(event);
      }
    }

    final entries = <_TempoMapEntry>[];
    var accumulated = 0;
    for (var index = 0; index < deduped.length; index++) {
      final event = deduped[index];
      if (index > 0) {
        final previous = deduped[index - 1];
        accumulated +=
            ((event.tick - previous.tick) *
                    previous.microsecondsPerQuarter /
                    ticksPerQuarter)
                .round();
      }
      entries.add(
        _TempoMapEntry(
          tick: event.tick,
          microsecondsPerQuarter: event.microsecondsPerQuarter,
          accumulatedMicroseconds: accumulated,
        ),
      );
    }
    return _TempoMap(entries, ticksPerQuarter);
  }

  int tickToMs(int tick) {
    var entry = entries.first;
    for (final candidate in entries) {
      if (candidate.tick > tick) {
        break;
      }
      entry = candidate;
    }
    final deltaTicks = tick - entry.tick;
    final microseconds =
        entry.accumulatedMicroseconds +
        (deltaTicks * entry.microsecondsPerQuarter / ticksPerQuarter).round();
    return (microseconds / 1000).round();
  }
}

class _ChannelTrackState {
  _ChannelTrackState({required this.name, required this.channel});

  final String name;
  final int channel;
  int? instrumentId;
  final List<NoteEvent> notes = <NoteEvent>[];
  final Map<int, List<_PendingNote>> pendingNotes = <int, List<_PendingNote>>{};
}

class _PendingNote {
  const _PendingNote({required this.tick, required this.velocity});

  final int tick;
  final int velocity;
}
