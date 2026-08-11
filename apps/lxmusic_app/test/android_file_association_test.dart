import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest registers score and archive VIEW MIME types', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android:label="@string/open_music_file"'));
    expect(strings, contains('<string name="open_music_file">导入音乐</string>'));
    expect(manifest, contains('android:mimeType="audio/midi"'));
    expect(manifest, contains('android:mimeType="application/json"'));
    expect(manifest, contains('android:mimeType="text/plain"'));
    expect(manifest, contains('android:mimeType="application/zip"'));
    expect(manifest, contains('android:pathPattern=".*\\\\.mid"'));
    expect(manifest, contains('android:pathPattern=".*\\\\.json"'));
    expect(manifest, contains('android:pathPattern=".*\\\\.txt"'));
    expect(manifest, contains('android:pathPattern=".*\\\\.zip"'));
  });
}
