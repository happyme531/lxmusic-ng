import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/layout_preview/layout_preview_screen.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets(
    'layout preview screen renders keys and supports label switching',
    (tester) async {
      final bundle = loadTestYamlAssetBundle();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetBundleProvider.overrideWithValue(bundle),
            layoutPreviewOrientationSupportedProvider.overrideWith(
              (ref) async => false,
            ),
          ],
          child: const MaterialApp(
            home: LayoutPreviewScreen(
              profileId: 'generic_demo',
              layoutId: 'generic_3x7_demo',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3x7 Demo'), findsOneWidget);
      expect(find.byKey(const ValueKey('layout-key-C4')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('layout-key-C4')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('音名'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('layout-key-C4')),
          matching: find.text('C4'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('layout-key-G5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('selected-key-id')), findsOneWidget);
      expect(find.text('G5'), findsAtLeastNWidgets(1));
      expect(find.text('79'), findsOneWidget);
    },
  );

  testWidgets('wide layout is scaled to fit without horizontal scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bundle = loadTestYamlAssetBundle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          layoutPreviewOrientationSupportedProvider.overrideWith(
            (ref) async => false,
          ),
        ],
        child: const MaterialApp(
          home: LayoutPreviewScreen(
            profileId: 'harrypotter',
            layoutId: 'hpma_yinterleaved3x12',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontalScrollViews = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((view) => view.scrollDirection == Axis.horizontal);
    expect(horizontalScrollViews, isEmpty);
    expect(
      find.byKey(const ValueKey('layout-preview-orientation-toggle')),
      findsNothing,
    );

    final frame = tester.getSize(
      find.byKey(const ValueKey('layout-preview-fit-frame')),
    );
    final naturalCanvas = tester.getSize(
      find.byKey(const ValueKey('layout-preview-natural-canvas')),
    );
    expect(frame.width, lessThan(naturalCanvas.width));
    expect(naturalCanvas.width / naturalCanvas.height, closeTo(16 / 9, 0.001));
    expect(
      frame.width / naturalCanvas.width,
      closeTo(frame.height / naturalCanvas.height, 0.001),
    );
    expect(
      tester
          .getTopRight(find.byKey(const ValueKey('layout-preview-fit-frame')))
          .dx,
      lessThanOrEqualTo(tester.view.physicalSize.width),
    );
  });

  testWidgets('orientation action toggles between landscape and portrait', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orientationRequests = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationRequests.add(List<Object?>.from(call.arguments as List));
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final bundle = loadTestYamlAssetBundle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          layoutPreviewOrientationSupportedProvider.overrideWith(
            (ref) async => true,
          ),
        ],
        child: const MaterialApp(
          home: LayoutPreviewScreen(
            profileId: 'generic_demo',
            layoutId: 'generic_3x7_demo',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('横屏'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('layout-preview-orientation-toggle')),
    );
    await tester.pump();
    expect(find.text('横屏'), findsOneWidget);
    expect(orientationRequests.last, const <Object?>[
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);

    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpAndSettle();
    expect(find.text('竖屏'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('layout-preview-orientation-toggle')),
    );
    await tester.pump();
    expect(find.text('竖屏'), findsOneWidget);
    expect(orientationRequests.last, const <Object?>[
      'DeviceOrientation.portraitUp',
      'DeviceOrientation.portraitDown',
    ]);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(find.text('横屏'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(orientationRequests.last, isEmpty);
  });
}
