import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/layout_preview/layout_preview_route.dart';
import 'package:lxmusic_app/features/layout_preview/layout_preview_screen.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/widgets/current_target_action.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets('current target picker can open layout preview page', (
    tester,
  ) async {
    final bundle = loadTestYamlAssetBundle();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            return Scaffold(
              appBar: AppBar(
                actions: const [CurrentTargetAction()],
              ),
            );
          },
        ),
        GoRoute(
          path: LayoutPreviewRoute.path,
          name: LayoutPreviewRoute.name,
          builder: (context, state) {
            return LayoutPreviewScreen(
              profileId: state.pathParameters['profileId']!,
              layoutId: state.pathParameters['layoutId']!,
              initialSelectedKeyId: state.uri.queryParameters['keyId'],
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          persistedTargetSelectionProvider.overrideWithValue(
            const PersistedTargetSelection(),
          ),
          initialPersistedProfileUsageProvider.overrideWithValue(
            const PersistedProfileUsage(<String, int>{}),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('current-target-action')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LxMusic-NG Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('layout-preview-generic_3x7_demo')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('layout-preview-generic_3x7_demo')),
    );
    await tester.pumpAndSettle();

    expect(find.text('3x7 Demo'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-key-C4')), findsOneWidget);
  });
}
