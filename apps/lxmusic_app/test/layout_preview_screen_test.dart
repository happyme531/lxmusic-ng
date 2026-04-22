import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/layout_preview/layout_preview_screen.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets('layout preview screen renders keys and supports label switching', (
    tester,
  ) async {
    final bundle = loadTestYamlAssetBundle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
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
  });
}
