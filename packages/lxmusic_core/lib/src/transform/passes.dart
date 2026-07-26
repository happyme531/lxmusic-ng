import 'dart:math' as math;

import '../domain/score.dart';
import 'pass_options.dart';
import 'transform_report.dart';

class MergeTracksPass {
  const MergeTracksPass(this.options);

  final MergeTracksOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.length <= 1) {
      return (score: score, report: const TransformReport());
    }

    final selectedTrackIndexes = options.selectedTracks?.isNotEmpty == true
        ? options.selectedTracks!
        : List<int>.generate(score.tracks.length, (index) => index);

    final mergedNotes = <NoteEvent>[];
    for (final trackIndex in selectedTrackIndexes) {
      if (trackIndex < 0 || trackIndex >= score.tracks.length) {
        continue;
      }
      final track = score.tracks[trackIndex];
      if (options.skipPercussion && track.channel == 9) {
        continue;
      }
      mergedNotes.addAll(track.notes);
    }
    mergedNotes.sort((a, b) => a.startMs.compareTo(b.startMs));

    return (
      score: score.copyWith(
        tracks: <Track>[Track(name: 'Merged', channel: 0, notes: mergedNotes)],
      ),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'MergeTracksPass',
            values: <String, Object?>{
              'trackCountBefore': score.tracks.length,
              'trackCountAfter': 1,
              'mergedNoteCount': mergedNotes.length,
            },
          ),
        ],
      ),
    );
  }
}

class RemoveEmptyTracksPass {
  const RemoveEmptyTracksPass();

  ({Score score, TransformReport report}) run(Score score) {
    final filteredTracks = score.tracks
        .where((track) => track.notes.isNotEmpty)
        .toList();
    return (
      score: score.copyWith(tracks: filteredTracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'RemoveEmptyTracksPass',
            values: <String, Object?>{
              'trackCountBefore': score.tracks.length,
              'trackCountAfter': filteredTracks.length,
            },
          ),
        ],
      ),
    );
  }
}

class PitchOffsetPass {
  const PitchOffsetPass(this.options);

  final PitchOffsetOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: track.notes
                .map(
                  (note) => note.copyWith(pitch: note.pitch + options.offset),
                )
                .toList(),
          ),
        )
        .toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'PitchOffsetPass',
            values: <String, Object?>{'offset': options.offset},
          ),
        ],
      ),
    );
  }
}

class LegalizeTargetNoteRangePass {
  const LegalizeTargetNoteRangePass(this.options);

  final LegalizeTargetNoteRangeOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (options.supportedPitches.isEmpty) {
      throw ArgumentError('supportedPitches must not be empty.');
    }

    final supported = options.supportedPitches.toSet();
    final orderedPitches = supported.toList()..sort();
    final minPitch = orderedPitches.first;
    final maxPitch = orderedPitches.last;
    var underFlowedNoteCount = 0;
    var overFlowedNoteCount = 0;
    var roundedNoteCount = 0;
    var wrappedHigherNoteCount = 0;
    var wrappedLowerNoteCount = 0;
    var middleFailedNoteCount = 0;
    var lastWasFloor = false;

    final tracks = score.tracks.map((track) {
      final output = <NoteEvent>[];

      for (final note in track.notes) {
        var pitch = note.pitch;

        if (pitch < minPitch) {
          if (pitch >= minPitch - options.wrapLowerOctave * 12) {
            pitch += 12 * ((minPitch - pitch + 11) ~/ 12);
            wrappedLowerNoteCount++;
          } else {
            underFlowedNoteCount++;
            continue;
          }
        }
        if (pitch > maxPitch) {
          if (pitch <= maxPitch + options.wrapHigherOctave * 12) {
            pitch -= 12 * ((pitch - maxPitch + 11) ~/ 12);
            wrappedHigherNoteCount++;
          } else {
            overFlowedNoteCount++;
            continue;
          }
        }

        if (supported.contains(pitch)) {
          output.add(note.copyWith(pitch: pitch));
          continue;
        }

        final legalization = switch (options.semiToneRoundingMode) {
          SemiToneRoundingMode.none => (pitches: <int>[pitch], rounded: 0),
          SemiToneRoundingMode.floor => (
            pitches: supported.contains(pitch - 1)
                ? <int>[pitch - 1]
                : const <int>[],
            rounded: supported.contains(pitch - 1) ? 1 : 0,
          ),
          SemiToneRoundingMode.ceil => (
            pitches: supported.contains(pitch + 1)
                ? <int>[pitch + 1]
                : const <int>[],
            rounded: supported.contains(pitch + 1) ? 1 : 0,
          ),
          SemiToneRoundingMode.drop => (pitches: const <int>[], rounded: 0),
          SemiToneRoundingMode.both => (
            pitches: <int>[
              if (supported.contains(pitch - 1)) pitch - 1,
              if (supported.contains(pitch + 1)) pitch + 1,
            ],
            rounded: supported.contains(pitch - 1) ? 1 : 0,
          ),
          SemiToneRoundingMode.alternating => _pickAlternating(
            pitch: pitch,
            supported: supported,
            lastWasFloor: lastWasFloor,
          ),
        };
        final legalized = legalization.pitches;

        if (legalized.isEmpty) {
          middleFailedNoteCount++;
          continue;
        }

        if (options.semiToneRoundingMode == SemiToneRoundingMode.alternating &&
            legalized.length == 1) {
          lastWasFloor = legalized.single == pitch - 1;
        }

        roundedNoteCount += legalization.rounded;
        for (final value in legalized) {
          output.add(note.copyWith(pitch: value));
        }
      }

      return Track(
        name: track.name,
        channel: track.channel,
        instrumentId: track.instrumentId,
        notes: output,
      );
    }).toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'LegalizeTargetNoteRangePass',
            values: <String, Object?>{
              'underFlowedNoteCount': underFlowedNoteCount,
              'overFlowedNoteCount': overFlowedNoteCount,
              'roundedNoteCount': roundedNoteCount,
              'wrappedHigherNoteCount': wrappedHigherNoteCount,
              'wrappedLowerNoteCount': wrappedLowerNoteCount,
              'middleFailedNoteCount': middleFailedNoteCount,
            },
          ),
        ],
      ),
    );
  }

  ({List<int> pitches, int rounded}) _pickAlternating({
    required int pitch,
    required Set<int> supported,
    required bool lastWasFloor,
  }) {
    if (lastWasFloor) {
      if (supported.contains(pitch + 1)) {
        return (pitches: <int>[pitch + 1], rounded: 1);
      }
      return (pitches: const <int>[], rounded: 0);
    }
    if (supported.contains(pitch - 1)) {
      return (pitches: <int>[pitch - 1], rounded: 1);
    }
    return (pitches: const <int>[], rounded: 0);
  }
}

class NoteToKeyPass {
  const NoteToKeyPass(this.options);

  final NoteToKeyOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    var mappedNoteCount = 0;
    final tracks = score.tracks.map((track) {
      final notes = track.notes.map((note) {
        final keyId = options.pitchToKeyId[note.pitch];
        if (keyId == null) {
          throw StateError('Unable to map pitch ${note.pitch} to a key.');
        }
        mappedNoteCount++;
        return note.copyWith(
          attrs: <String, Object?>{
            ...note.attrs,
            'keyId': keyId,
            'mappedPitch': note.pitch,
          },
        );
      }).toList();

      return Track(
        name: track.name,
        channel: track.channel,
        instrumentId: track.instrumentId,
        notes: notes,
      );
    }).toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'NoteToKeyPass',
            values: <String, Object?>{'mappedNoteCount': mappedNoteCount},
          ),
        ],
      ),
    );
  }
}

class BindLyricsPass {
  const BindLyricsPass(this.options);

  final BindLyricsOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    final lyrics = options.lyrics ?? score.lyrics;
    if (lyrics.isEmpty || score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final locatedNotes = <({int trackIndex, int noteIndex, int atMs})>[];
    for (var trackIndex = 0; trackIndex < score.tracks.length; trackIndex++) {
      final track = score.tracks[trackIndex];
      for (var noteIndex = 0; noteIndex < track.notes.length; noteIndex++) {
        final note = track.notes[noteIndex];
        locatedNotes.add((
          trackIndex: trackIndex,
          noteIndex: noteIndex,
          atMs: options.useStoredOriginalTime
              ? (note.attrs['originalTime'] as int?) ?? note.startMs
              : note.startMs,
        ));
      }
    }
    locatedNotes.sort((a, b) => a.atMs.compareTo(b.atMs));
    if (locatedNotes.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: track.notes
                .map(
                  (note) =>
                      note.copyWith(attrs: <String, Object?>{...note.attrs}),
                )
                .toList(),
          ),
        )
        .toList();

    var totalErrorMs = 0;
    for (final lyric in lyrics) {
      final target = _findChordStartAtTime(locatedNotes, lyric.atMs);
      final note = tracks[target.trackIndex].notes[target.noteIndex];
      final existing = note.attrs['lyric'] as String?;
      tracks[target.trackIndex].notes[target.noteIndex] = note.copyWith(
        attrs: <String, Object?>{
          ...note.attrs,
          'lyric': existing == null || existing.isEmpty
              ? lyric.text
              : '$existing\n${lyric.text}',
        },
      );
      totalErrorMs += (target.atMs - lyric.atMs).abs();
    }

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'BindLyricsPass',
            values: <String, Object?>{'totalErrorMs': totalErrorMs},
          ),
        ],
      ),
    );
  }

  ({int trackIndex, int noteIndex, int atMs}) _findChordStartAtTime(
    List<({int trackIndex, int noteIndex, int atMs})> notes,
    int targetMs,
  ) {
    const eps = 1;
    var left = 0;
    var right = notes.length - 1;

    while (left <= right) {
      final mid = (left + right) ~/ 2;
      final atMs = notes[mid].atMs;
      if (atMs == targetMs) {
        var first = mid;
        while (first > 0 &&
            (notes[first].atMs - notes[first - 1].atMs).abs() <= eps) {
          first--;
        }
        return notes[first];
      }
      if (atMs < targetMs) {
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    if (left >= notes.length) {
      var index = notes.length - 1;
      while (index > 0 &&
          (notes[index].atMs - notes[index - 1].atMs).abs() <= eps) {
        index--;
      }
      return notes[index];
    }
    if (left == 0) {
      return notes.first;
    }
    if ((notes[left - 1].atMs - targetMs).abs() <=
        (notes[left].atMs - targetMs).abs()) {
      left--;
    }
    while (left > 0 && (notes[left].atMs - notes[left - 1].atMs).abs() <= eps) {
      left--;
    }
    return notes[left];
  }
}

class StoreCurrentNoteTimePass {
  const StoreCurrentNoteTimePass();

  ({Score score, TransformReport report}) run(Score score) {
    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: track.notes
                .map(
                  (note) => note.copyWith(
                    attrs: <String, Object?>{
                      ...note.attrs,
                      'originalTime': note.startMs,
                    },
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: const TransformReport(
        stats: <PassStat>[PassStat(name: 'StoreCurrentNoteTimePass')],
      ),
    );
  }
}

class MergeNearbyNotesPass {
  const MergeNearbyNotesPass(this.options);

  final MergeNearbyNotesOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final source = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (source.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final output = <NoteEvent>[source.first];
    var droppedSameNoteCount = 0;
    var batchStartTime = source.first.startMs;
    var batchSize = 0;
    var batchPitches = <int>{source.first.pitch};

    for (var index = 1; index < source.length; index++) {
      final note = source[index];
      if (note.startMs - batchStartTime < options.maxIntervalMs &&
          batchSize < options.maxBatchSize) {
        if (batchPitches.contains(note.pitch)) {
          droppedSameNoteCount++;
          continue;
        }
        output.add(note.copyWith(startMs: batchStartTime));
        batchPitches.add(note.pitch);
        batchSize++;
        continue;
      }

      output.add(note);
      batchStartTime = note.startMs;
      batchSize = 0;
      batchPitches = <int>{note.pitch};
    }

    final track = Track(
      name: score.tracks.first.name,
      channel: score.tracks.first.channel,
      instrumentId: score.tracks.first.instrumentId,
      notes: output,
    );

    return (
      score: score.copyWith(tracks: <Track>[track, ...score.tracks.skip(1)]),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'MergeNearbyNotesPass',
            values: <String, Object?>{
              'droppedSameNoteCount': droppedSameNoteCount,
            },
          ),
        ],
      ),
    );
  }
}

class FoldFrequentSameNotePass {
  const FoldFrequentSameNotePass(this.options);

  final FoldFrequentSameNoteOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final notes = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final consumed = <int>{};
    final output = <NoteEvent>[];

    for (var index = 0; index < notes.length; index++) {
      if (consumed.contains(index)) {
        continue;
      }
      final current = notes[index];
      final matching = <int>[index];
      var lastStartTime = current.startMs;

      for (var cursor = index + 1; cursor < notes.length; cursor++) {
        if (notes[cursor].startMs - lastStartTime >= options.maxIntervalMs) {
          break;
        }
        if (notes[cursor].pitch == current.pitch) {
          matching.add(cursor);
          lastStartTime = notes[cursor].startMs;
        }
      }

      if (matching.length > 1) {
        final endTime = notes[matching.last].startMs;
        output.add(
          current.copyWith(
            durationMs: endTime - current.startMs,
            attrs: <String, Object?>{
              ...current.attrs,
              'duration': endTime - current.startMs,
            },
          ),
        );
        consumed.addAll(matching.skip(1));
      } else {
        output.add(current);
      }
    }

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: output,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: const TransformReport(
        stats: <PassStat>[PassStat(name: 'FoldFrequentSameNotePass')],
      ),
    );
  }
}

class EstimateNoteDurationPass {
  const EstimateNoteDurationPass(this.options);

  final EstimateNoteDurationOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }
    final notes = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (notes.length < 2) {
      return (score: score, report: const TransformReport());
    }

    final grouped = _groupChordIndexes(notes);
    for (var groupIndex = 0; groupIndex < grouped.length - 1; groupIndex++) {
      final currentGroup = grouped[groupIndex];
      final nextGroup = grouped[groupIndex + 1];
      final deltaMs =
          notes[nextGroup.first].startMs - notes[currentGroup.first].startMs;
      final durationMs = (deltaMs * options.multiplier).round();
      for (final noteIndex in currentGroup) {
        final note = notes[noteIndex];
        if (note.durationMs == null && note.attrs['duration'] == null) {
          notes[noteIndex] = note.copyWith(
            durationMs: durationMs,
            attrs: <String, Object?>{...note.attrs, 'duration': durationMs},
          );
        }
      }
    }

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: notes,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: const TransformReport(
        stats: <PassStat>[PassStat(name: 'EstimateNoteDurationPass')],
      ),
    );
  }
}

class SplitLongNotePass {
  const SplitLongNotePass(this.options);

  final SplitLongNoteOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final output = <NoteEvent>[];
    for (final note in score.tracks.first.notes) {
      final durationMs = note.durationMs ?? (note.attrs['duration'] as int?);
      if (durationMs == null || durationMs < options.minDurationMs) {
        output.add(note);
        continue;
      }

      final endMs = note.startMs + durationMs;
      output.add(
        note.copyWith(
          durationMs: options.splitDurationMs,
          attrs: <String, Object?>{
            ...note.attrs,
            'duration': options.splitDurationMs,
          },
        ),
      );
      for (
        var atMs = note.startMs + options.splitDurationMs;
        atMs < endMs;
        atMs += options.splitDurationMs
      ) {
        output.add(
          NoteEvent(
            pitch: note.pitch,
            startMs: atMs,
            durationMs: options.splitDurationMs,
            velocity: note.velocity,
            attrs: <String, Object?>{'duration': options.splitDurationMs},
          ),
        );
      }
    }
    output.sort((a, b) => a.startMs.compareTo(b.startMs));

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: output,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: const TransformReport(
        stats: <PassStat>[PassStat(name: 'SplitLongNotePass')],
      ),
    );
  }
}

class SpeedChangePass {
  const SpeedChangePass(this.options);

  final SpeedChangeOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: track.notes
                .map(
                  (note) => note.copyWith(
                    startMs: (note.startMs / options.speed).round(),
                    durationMs: note.durationMs == null
                        ? null
                        : (note.durationMs! / options.speed).round(),
                    attrs: note.attrs['duration'] == null
                        ? note.attrs
                        : <String, Object?>{
                            ...note.attrs,
                            'duration':
                                ((note.attrs['duration'] as num) /
                                        options.speed)
                                    .round(),
                          },
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'SpeedChangePass',
            values: <String, Object?>{'speed': options.speed},
          ),
        ],
      ),
    );
  }
}

class LimitBlankDurationPass {
  const LimitBlankDurationPass(this.options);

  final LimitBlankDurationOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: _limitBlankDuration(track.notes, options.maxBlankDurationMs),
          ),
        )
        .toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'LimitBlankDurationPass',
            values: <String, Object?>{
              'maxBlankDurationMs': options.maxBlankDurationMs,
            },
          ),
        ],
      ),
    );
  }
}

class SkipIntroPass {
  const SkipIntroPass(this.options);

  final SkipIntroOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty || score.tracks.first.notes.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final introMs = score.tracks.first.notes.first.startMs;
    if (introMs < options.maxIntroMs) {
      return (score: score, report: const TransformReport());
    }

    final deltaMs = introMs - options.maxIntroMs;
    final tracks = score.tracks
        .map(
          (track) => Track(
            name: track.name,
            channel: track.channel,
            instrumentId: track.instrumentId,
            notes: track.notes
                .map((note) => note.copyWith(startMs: note.startMs - deltaMs))
                .toList(),
          ),
        )
        .toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'SkipIntroPass',
            values: <String, Object?>{'deltaMs': deltaMs},
          ),
        ],
      ),
    );
  }
}

class SingleKeyFrequencyLimitPass {
  const SingleKeyFrequencyLimitPass(this.options);

  final SingleKeyFrequencyLimitOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final notes = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final output = <NoteEvent>[];
    final lastAcceptedTime = <int, int>{};
    var droppedNoteCount = 0;

    for (final note in notes) {
      final previousTime = lastAcceptedTime[note.pitch];
      if (previousTime != null &&
          note.startMs - previousTime < options.minIntervalMs) {
        droppedNoteCount++;
        continue;
      }
      output.add(note);
      lastAcceptedTime[note.pitch] = note.startMs;
    }

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: output,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'SingleKeyFrequencyLimitPass',
            values: <String, Object?>{'droppedNoteCount': droppedNoteCount},
          ),
        ],
      ),
    );
  }
}

class NoteFrequencySoftLimitPass {
  const NoteFrequencySoftLimitPass(this.options);

  final NoteFrequencySoftLimitOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final notes = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (notes.isEmpty) {
      return (score: score, report: const TransformReport());
    }

    final grouped = _groupChordIndexes(notes);
    final output = List<NoteEvent>.from(notes);
    final chordStarts = grouped
        .map((group) => notes[group.first].startMs.toDouble())
        .toList();
    final adjustedStarts = <int>[chordStarts.first.round()];
    var delayedChordCount = 0;
    var delayedNoteCount = 0;
    var totalDelayMs = 0;
    var maxDelayMs = 0;

    for (var groupIndex = 1; groupIndex < grouped.length; groupIndex++) {
      final group = grouped[groupIndex];
      final deltaMs = chordStarts[groupIndex] - chordStarts[groupIndex - 1];
      final frequency = 1000 / deltaMs;
      final mappedFrequency = _saturationMap(frequency, options.minIntervalMs);
      final adjustedDeltaMs = (1000 / mappedFrequency).round();
      final adjustedStart = adjustedStarts.last + adjustedDeltaMs;
      adjustedStarts.add(adjustedStart);
      final originalStart = notes[group.first].startMs;
      final delay = adjustedStart - originalStart;
      if (delay > 0) {
        delayedChordCount++;
        delayedNoteCount += group.length;
        totalDelayMs += delay;
        if (delay > maxDelayMs) {
          maxDelayMs = delay;
        }
      }
      for (final index in group) {
        output[index] = notes[index].copyWith(startMs: adjustedStart);
      }
    }

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: output,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'NoteFrequencySoftLimitPass',
            values: <String, Object?>{
              'delayedChordCount': delayedChordCount,
              'delayedNoteCount': delayedNoteCount,
              'totalDelayMs': totalDelayMs,
              'maxDelayMs': maxDelayMs,
            },
          ),
        ],
      ),
    );
  }

  double _saturationMap(double frequency, int minIntervalMs) {
    final limitHz = 1000 / minIntervalMs;
    final normalized = frequency / limitHz;
    final e2x = math.exp(2 * normalized);
    return limitHz * ((e2x - 1) / (e2x + 1));
  }
}

class ChordNoteCountLimitPass {
  const ChordNoteCountLimitPass(this.options);

  final ChordNoteCountLimitOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (score.tracks.isEmpty) {
      return (score: score, report: const TransformReport());
    }
    if (options.maxNoteCount <= 0) {
      throw ArgumentError('maxNoteCount must be greater than zero.');
    }

    final notes = List<NoteEvent>.from(score.tracks.first.notes)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final grouped = _groupChordIndexes(notes);
    final output = <NoteEvent>[];
    final random = math.Random(options.randomSeed);
    var limitedChordCount = 0;
    var droppedNoteCount = 0;
    var splitNoteCount = 0;

    for (final group in grouped) {
      if (group.length <= options.maxNoteCount) {
        output.addAll(group.map((index) => notes[index]));
        continue;
      }

      limitedChordCount++;
      final selected = group.map((index) => notes[index]).toList();
      final ordered = _orderChordNotes(selected, random);
      final kept = ordered.take(options.maxNoteCount).toList();
      final overflow = ordered.skip(options.maxNoteCount).toList();

      output.addAll(kept..sort((a, b) => a.pitch.compareTo(b.pitch)));

      switch (options.limitMode) {
        case 'delete':
          droppedNoteCount += overflow.length;
          break;
        case 'split':
          for (var index = 0; index < overflow.length; index++) {
            final note = overflow[index];
            output.add(
              note.copyWith(
                startMs: note.startMs + options.splitDelayMs * (index + 1),
              ),
            );
            splitNoteCount++;
          }
          break;
        default:
          throw ArgumentError(
            'Unsupported chord limit mode "${options.limitMode}".',
          );
      }
    }

    output.sort((a, b) {
      final timeOrder = a.startMs.compareTo(b.startMs);
      if (timeOrder != 0) {
        return timeOrder;
      }
      return a.pitch.compareTo(b.pitch);
    });

    return (
      score: score.copyWith(
        tracks: <Track>[
          Track(
            name: score.tracks.first.name,
            channel: score.tracks.first.channel,
            instrumentId: score.tracks.first.instrumentId,
            notes: output,
          ),
          ...score.tracks.skip(1),
        ],
      ),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'ChordNoteCountLimitPass',
            values: <String, Object?>{
              'limitedChordCount': limitedChordCount,
              'droppedNoteCount': droppedNoteCount,
              'splitNoteCount': splitNoteCount,
              'limitMode': options.limitMode,
              'selectMode': options.effectiveSelectMode,
            },
          ),
        ],
      ),
    );
  }

  List<NoteEvent> _orderChordNotes(List<NoteEvent> notes, math.Random random) {
    final ordered = List<NoteEvent>.from(notes);
    switch (options.effectiveSelectMode) {
      case 'high':
        ordered.sort((a, b) {
          final pitchOrder = b.pitch.compareTo(a.pitch);
          if (pitchOrder != 0) {
            return pitchOrder;
          }
          return b.velocity.compareTo(a.velocity);
        });
        return ordered;
      case 'low':
        ordered.sort((a, b) {
          final pitchOrder = a.pitch.compareTo(b.pitch);
          if (pitchOrder != 0) {
            return pitchOrder;
          }
          return b.velocity.compareTo(a.velocity);
        });
        return ordered;
      case 'random':
        for (var index = ordered.length - 1; index > 0; index--) {
          final swapIndex = random.nextInt(index + 1);
          final tmp = ordered[index];
          ordered[index] = ordered[swapIndex];
          ordered[swapIndex] = tmp;
        }
        return ordered;
      default:
        throw ArgumentError(
          'Unsupported chord select mode "${options.effectiveSelectMode}".',
        );
    }
  }
}

class HumanifyPass {
  const HumanifyPass(this.options);

  final HumanifyOptions options;

  ({Score score, TransformReport report}) run(Score score) {
    if (options.noteAbsTimeStdDev < 0) {
      throw ArgumentError('noteAbsTimeStdDev must be non-negative.');
    }
    if (score.tracks.isEmpty || options.noteAbsTimeStdDev == 0) {
      return (
        score: score,
        report: TransformReport(
          stats: <PassStat>[
            PassStat(
              name: 'HumanifyPass',
              values: <String, Object?>{
                'noteAbsTimeStdDev': options.noteAbsTimeStdDev,
                'adjustedNoteCount': 0,
              },
            ),
          ],
        ),
      );
    }

    final random = options.randomSeed == null
        ? math.Random()
        : math.Random(options.randomSeed);
    var adjustedNoteCount = 0;

    final tracks = score.tracks.map((track) {
      final notes = track.notes.map((note) {
        final offsetMs = _nextGaussian(
          random,
          options.noteAbsTimeStdDev,
        ).round();
        final startMs = math.max(0, note.startMs + offsetMs);
        if (startMs != note.startMs) {
          adjustedNoteCount++;
        }
        return note.copyWith(startMs: startMs);
      }).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));

      return Track(
        name: track.name,
        channel: track.channel,
        instrumentId: track.instrumentId,
        notes: notes,
      );
    }).toList();

    return (
      score: score.copyWith(tracks: tracks),
      report: TransformReport(
        stats: <PassStat>[
          PassStat(
            name: 'HumanifyPass',
            values: <String, Object?>{
              'noteAbsTimeStdDev': options.noteAbsTimeStdDev,
              'adjustedNoteCount': adjustedNoteCount,
            },
          ),
        ],
      ),
    );
  }

  double _nextGaussian(math.Random random, double stddev) {
    var u = 0.0;
    var v = 0.0;
    while (u == 0) {
      u = random.nextDouble();
    }
    while (v == 0) {
      v = random.nextDouble();
    }
    final num = math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
    return num * stddev;
  }
}

List<List<int>> _groupChordIndexes(List<NoteEvent> notes) {
  final groups = <List<int>>[];
  var index = 0;
  while (index < notes.length) {
    final startMs = notes[index].startMs;
    final group = <int>[index];
    index++;
    while (index < notes.length && notes[index].startMs == startMs) {
      group.add(index);
      index++;
    }
    groups.add(group);
  }
  return groups;
}

List<NoteEvent> _limitBlankDuration(
  List<NoteEvent> notes,
  int maxBlankDurationMs,
) {
  if (notes.isEmpty) {
    return notes;
  }

  final sorted = List<NoteEvent>.from(notes)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final output = <NoteEvent>[];
  var previousOriginalTime = 0;
  var previousAdjustedTime = 0;
  for (final note in sorted) {
    final gap = note.startMs - previousOriginalTime;
    final adjustedTime =
        previousAdjustedTime +
        (gap > maxBlankDurationMs ? maxBlankDurationMs : gap);
    output.add(note.copyWith(startMs: adjustedTime));
    previousOriginalTime = note.startMs;
    previousAdjustedTime = adjustedTime;
  }
  return output;
}
