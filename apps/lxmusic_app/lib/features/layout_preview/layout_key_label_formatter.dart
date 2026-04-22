enum LayoutLabelMode { numbered, pitchName }

class NumberedPitchLabel {
  const NumberedPitchLabel({
    required this.baseLabel,
    this.upperDotCount = 0,
    this.lowerDotCount = 0,
  });

  final String baseLabel;
  final int upperDotCount;
  final int lowerDotCount;
}

class LayoutPreviewDisplayConfig {
  const LayoutPreviewDisplayConfig({
    this.labelMode = LayoutLabelMode.numbered,
    this.showLabels = true,
  });

  final LayoutLabelMode labelMode;
  final bool showLabels;
}

class LayoutKeyLabelFormatter {
  const LayoutKeyLabelFormatter._();

  static const List<String> _pitchNames = <String>[
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

  static const List<String> _numberedNames = <String>[
    '1',
    '#1',
    '2',
    '#2',
    '3',
    '4',
    '#4',
    '5',
    '#5',
    '6',
    '#6',
    '7',
  ];

  static String format({
    required int pitch,
    required LayoutLabelMode mode,
  }) {
    return switch (mode) {
      LayoutLabelMode.numbered => formatNumbered(pitch),
      LayoutLabelMode.pitchName => formatPitchName(pitch),
    };
  }

  static String formatPitchName(int pitch) {
    final octave = pitch ~/ 12 - 1;
    return '${_pitchNames[pitch % 12]}$octave';
  }

  static String formatNumbered(int pitch) {
    final label = describeNumbered(pitch);
    final suffix = label.upperDotCount > 0
        ? List<String>.filled(label.upperDotCount, '\u0307').join()
        : label.lowerDotCount > 0
            ? List<String>.filled(label.lowerDotCount, '\u0323').join()
            : '';
    return '${label.baseLabel}$suffix';
  }

  static NumberedPitchLabel describeNumbered(int pitch) {
    final octave = pitch ~/ 12 - 1;
    final dots = octave - 4;
    return NumberedPitchLabel(
      baseLabel: _numberedNames[pitch % 12],
      upperDotCount: dots > 0 ? dots : 0,
      lowerDotCount: dots < 0 ? -dots : 0,
    );
  }
}
