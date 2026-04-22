import 'package:lxmusic_core/lxmusic_core.dart';
import 'package:test/test.dart';

void main() {
  const parser = LrcParser();

  test('parses simple lrc', () {
    const source = '''
[00:00.00]Test lyrics
[00:05.20]Second line
[00:10.50]Third line
''';

    final result = parser.parseFromString(source);
    expect(
      result.map((item) => (item.atMs, item.text)).toList(),
      <(int, String)>[
        (0, 'Test lyrics'),
        (5200, 'Second line'),
        (10500, 'Third line'),
      ],
    );
  });

  test('handles multiple time tags', () {
    const source = '''
[00:00.00][00:05.00]Repeated line
[00:10.00]Normal line
''';

    final result = parser.parseFromString(source);
    expect(
      result.map((item) => (item.atMs, item.text)).toList(),
      <(int, String)>[
        (0, 'Repeated line'),
        (5000, 'Repeated line'),
        (10000, 'Normal line'),
      ],
    );
  });

  test('handles multiline lyric body', () {
    const source = '''
[00:00.00]l0
[00:00.20]l1
l2
l3
[00:00.40]l4
''';

    final result = parser.parseFromString(source);
    expect(
      result.map((item) => (item.atMs, item.text)).toList(),
      <(int, String)>[(0, 'l0'), (200, 'l1\nl2\nl3'), (400, 'l4')],
    );
  });
}
