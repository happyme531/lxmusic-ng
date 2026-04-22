import '../domain/score.dart';

class LrcParser {
  const LrcParser();

  List<LyricEvent> parseFromString(String source) {
    final lines = source.split('\n');
    final lyrics = <LyricEvent>[];
    final timeTagRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    var currentText = '';

    for (final rawLine in lines) {
      final trimmedLine = rawLine.trim();
      if (trimmedLine.isEmpty ||
          trimmedLine.startsWith('[ti:') ||
          trimmedLine.startsWith('[ar:') ||
          trimmedLine.startsWith('[al:')) {
        continue;
      }

      final matches = timeTagRegex.allMatches(trimmedLine).toList();
      if (matches.isEmpty) {
        currentText += '${currentText.isEmpty ? '' : '\n'}$trimmedLine';
        continue;
      }

      if (currentText.isNotEmpty && lyrics.isNotEmpty) {
        final last = lyrics.removeLast();
        lyrics.add(LyricEvent(atMs: last.atMs, text: currentText));
        currentText = '';
      }

      final text = trimmedLine.replaceAll(timeTagRegex, '').trim();
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
        final atMs = minutes * 60000 + seconds * 1000 + milliseconds;
        lyrics.add(LyricEvent(atMs: atMs, text: text));
      }

      if (text.isNotEmpty) {
        currentText = text;
      }
    }

    if (currentText.isNotEmpty && lyrics.isNotEmpty) {
      final last = lyrics.removeLast();
      lyrics.add(LyricEvent(atMs: last.atMs, text: currentText));
    }

    lyrics.sort((a, b) => a.atMs.compareTo(b.atMs));
    return lyrics;
  }
}
