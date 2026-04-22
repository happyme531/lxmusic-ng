import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/layout_preview/layout_key_label_formatter.dart';

void main() {
  test('formats numbered notation with octave dots and sharps', () {
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 60,
        mode: LayoutLabelMode.numbered,
      ),
      '1',
    );
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 72,
        mode: LayoutLabelMode.numbered,
      ),
      '1\u0307',
    );
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 48,
        mode: LayoutLabelMode.numbered,
      ),
      '1\u0323',
    );
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 61,
        mode: LayoutLabelMode.numbered,
      ),
      '#1',
    );
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 73,
        mode: LayoutLabelMode.numbered,
      ),
      '#1\u0307',
    );
  });

  test('formats pitch names from midi numbers', () {
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 60,
        mode: LayoutLabelMode.pitchName,
      ),
      'C4',
    );
    expect(
      LayoutKeyLabelFormatter.format(
        pitch: 61,
        mode: LayoutLabelMode.pitchName,
      ),
      'C#4',
    );
    expect(LayoutKeyLabelFormatter.formatPitchName(95), 'B6');
  });
}
