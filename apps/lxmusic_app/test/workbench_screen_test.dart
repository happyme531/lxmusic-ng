import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/library/models/music_file.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/workbench_screen.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets(
    'updates selected file when initial file changes on same screen',
    (tester) async {
      final fileA = MusicFile(
        path: '/tmp/a.mid',
        fileName: 'a.mid',
        formatId: 'midi',
        durationMs: 1000,
      );
      final fileB = MusicFile(
        path: '/tmp/b.mid',
        fileName: 'b.mid',
        formatId: 'midi',
        durationMs: 2000,
      );
      final currentFile = ValueNotifier<MusicFile?>(null);
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              assetBundleProvider.overrideWithValue(
                loadTestYamlAssetBundle(),
              ),
            ],
          ),
          child: MaterialApp(
            home: ValueListenableBuilder<MusicFile?>(
              valueListenable: currentFile,
              builder: (context, file, _) {
                return WorkbenchScreen(initialFile: file);
              },
            ),
          ),
        ),
      );
      addTearDown(container.dispose);

      await tester.pump();
      expect(find.text('从曲库选择文件'), findsOneWidget);

      currentFile.value = fileA;
      await tester.pump();
      await tester.pump();

      expect(find.text('a.mid'), findsOneWidget);
      expect(container.read(selectedFileProvider)?.fileName, 'a.mid');

      currentFile.value = fileB;
      await tester.pump();
      await tester.pump();

      expect(find.text('b.mid'), findsOneWidget);
      expect(container.read(selectedFileProvider)?.fileName, 'b.mid');
    },
  );
}
