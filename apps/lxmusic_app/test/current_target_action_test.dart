import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/widgets/current_target_action.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets('picker keeps committed config separate from draft selection', (
    tester,
  ) async {
    final bundle = loadTestYamlAssetBundle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          persistedTargetSelectionProvider.overrideWithValue(
            const PersistedTargetSelection(
              profileId: 'generic_demo',
              variantId: 'default',
              layoutId: 'generic_3x7_demo',
            ),
          ),
          initialPersistedProfileUsageProvider.overrideWithValue(
            const PersistedProfileUsage(<String, int>{}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [CurrentTargetAction()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('current-target-action')),
        matching: find.text('LxMusic-NG Demo / 默认 / 3x7 Demo'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('current-target-action')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('LxMusic-NG Demo / 默认 / 3x7 Demo'),
      ),
      findsOneWidget,
    );
    expect(_chipText(tester, 'target-summary-profile'), '选择游戏');
    expect(_chipText(tester, 'target-summary-variant'), '选择乐器');
    expect(_chipText(tester, 'target-summary-layout'), '选择键位');
    expect(_chipOnPressed(tester, 'target-summary-profile'), isNotNull);
    expect(_chipOnPressed(tester, 'target-summary-variant'), isNull);
    expect(_chipOnPressed(tester, 'target-summary-layout'), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('target-filter-profile')),
      'Demo',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('LxMusic-NG Demo'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('target-filter-variant')), findsOneWidget);
    expect(_chipText(tester, 'target-summary-profile'), 'LxMusic-NG Demo');
    expect(_chipText(tester, 'target-summary-variant'), '选择乐器');
    expect(_chipText(tester, 'target-summary-layout'), '选择键位');
    expect(_chipOnPressed(tester, 'target-summary-variant'), isNotNull);
    expect(_chipOnPressed(tester, 'target-summary-layout'), isNull);

    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('target-filter-layout')), findsOneWidget);
    expect(_chipText(tester, 'target-summary-profile'), 'LxMusic-NG Demo');
    expect(_chipText(tester, 'target-summary-variant'), '默认');
    expect(_chipText(tester, 'target-summary-layout'), '选择键位');
    expect(_chipOnPressed(tester, 'target-summary-layout'), isNotNull);

    await tester.tap(find.byTooltip('返回上一级'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('target-filter-variant')), findsOneWidget);
    expect(_chipText(tester, 'target-summary-profile'), 'LxMusic-NG Demo');
    expect(_chipText(tester, 'target-summary-variant'), '默认');
    expect(_chipText(tester, 'target-summary-layout'), '选择键位');
    expect(_chipOnPressed(tester, 'target-summary-layout'), isNotNull);

    await tester.tap(find.byTooltip('返回上一级'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('target-filter-profile')), findsOneWidget);
    expect(_chipText(tester, 'target-summary-profile'), 'LxMusic-NG Demo');
    expect(_chipText(tester, 'target-summary-variant'), '选择乐器');
    expect(_chipText(tester, 'target-summary-layout'), '选择键位');
    expect(_chipOnPressed(tester, 'target-summary-variant'), isNotNull);
    expect(_chipOnPressed(tester, 'target-summary-layout'), isNull);
  });
}

String _chipText(WidgetTester tester, String key) {
  final chipFinder = find.byKey(ValueKey(key));
  final text = find.descendant(
    of: chipFinder,
    matching: find.byType(Text),
  );
  return tester.widgetList<Text>(text).first.data ?? '';
}

VoidCallback? _chipOnPressed(WidgetTester tester, String key) {
  return tester.widget<ActionChip>(find.byKey(ValueKey(key))).onPressed;
}
