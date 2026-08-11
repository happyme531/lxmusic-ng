import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/features/library/platform/external_file_open_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('decodes pending files and releases native cache paths', (
    tester,
  ) async {
    const channel = MethodChannel(
      MethodChannelExternalFileOpenPlatform.channelName,
    );
    MethodCall? releaseCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'consumePendingFiles') {
        return <Object?>[
          <String, Object?>{'fileName': 'song.mid', 'path': '/cache/open-1'},
          <String, Object?>{
            'fileName': 'broken.zip',
            'errorMessage': '无法读取外部应用提供的文件。',
          },
        ];
      }
      if (call.method == 'releaseCachedFiles') {
        releaseCall = call;
        return null;
      }
      throw MissingPluginException();
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final platform = MethodChannelExternalFileOpenPlatform(channel: channel);
    addTearDown(platform.dispose);
    final files = await platform.consumePendingFiles();

    expect(files, hasLength(2));
    expect(files.first.fileName, 'song.mid');
    expect(files.first.isReadable, isTrue);
    expect(files.last.isReadable, isFalse);
    expect(files.last.errorMessage, contains('无法读取'));

    await platform.releaseCachedFiles(<String>['/cache/open-1']);
    expect(releaseCall?.method, 'releaseCachedFiles');
    expect((releaseCall?.arguments as Map<Object?, Object?>)['paths'], <String>[
      '/cache/open-1',
    ]);
  });
}
