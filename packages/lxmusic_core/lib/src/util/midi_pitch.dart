class MidiPitch {
  const MidiPitch._();

  static const List<int> scaleOffsets = <int>[0, 2, 4, 5, 7, 9, 11];

  static int nameToMidiPitch(String name) {
    final normalized = name.trim().toUpperCase();
    final match = RegExp(r'^([A-G])([0-9])([#]?)$').firstMatch(normalized);
    if (match == null) {
      throw FormatException('Invalid note name: $name');
    }
    const pitchMap = <String, int>{
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    final accidental = match.group(3)! == '#' ? 1 : 0;
    return pitchMap[match.group(1)]! +
        accidental +
        (int.parse(match.group(2)!) + 1) * 12;
  }

  static String midiPitchToName(int midiPitch) {
    const noteNames = <String>[
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = midiPitch ~/ 12 - 1;
    final noteIndex = midiPitch % 12;
    return '${noteNames[noteIndex]}$octave';
  }

  static bool isHalf(int pitch) {
    final mod = pitch % 12;
    return mod == 1 || mod == 3 || mod == 6 || mod == 8 || mod == 10;
  }
}
