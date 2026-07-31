import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/calibration/platform/calibration_platform.dart';
import 'package:lxmusic_app/features/workbench/providers/workbench_provider.dart';
import 'package:lxmusic_app/features/workbench/widgets/current_target_action.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import 'test_yaml_assets.dart';

void main() {
  testWidgets('picker keeps committed config separate from draft selection', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bundle = loadTestYamlAssetBundle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          calibrationPlatformProvider.overrideWithValue(
            const _FakeCalibrationPlatform(),
          ),
          calibrationRepositoryProvider.overrideWithValue(
            _MemoryCalibrationRepository(),
          ),
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
            appBar: AppBar(actions: const [CurrentTargetAction()]),
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('current-target-action')),
        matching: find.text(' (未校准)'),
      ),
      findsOneWidget,
    );
    final targetLabel = tester.renderObject<RenderParagraph>(
      find.text('LxMusic-NG Demo / 默认 / 3x7 Demo'),
    );
    expect(targetLabel.didExceedMaxLines, isFalse);
    await tester.tap(find.byKey(const ValueKey('current-target-action')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('LxMusic-NG Demo / 默认 / 3x7 Demo'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calibrate-current-target')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const ValueKey('calibrate-current-target'))),
      isA<FilledButton>(),
    );
    expect(find.text('校准'), findsOneWidget);
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
    expect(_statusText(tester, 'generic_3x7_demo'), '未校准');
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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('existing calibration uses a subdued recalibrate action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bundle = loadTestYamlAssetBundle();
    final repository = _MemoryCalibrationRepository(
      Calibration(
        key: const CalibrationKey(
          profileId: 'generic_demo',
          layoutId: 'generic_3x7_demo',
          deviceId: 'android-test',
        ),
        orientation: 'portrait',
        leftTopPx: (10, 20),
        rightBottomPx: (100, 200),
        capturedAt: DateTime.utc(2026, 7, 31),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          calibrationPlatformProvider.overrideWithValue(
            const _FakeCalibrationPlatform(),
          ),
          calibrationRepositoryProvider.overrideWithValue(repository),
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
            appBar: AppBar(actions: const [CurrentTargetAction()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('current-target-action')),
        matching: find.text(' (未校准)'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('current-target-action')));
    await tester.pumpAndSettle();

    expect(find.text('重新校准'), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('calibrate-current-target'))),
      isA<TextButton>(),
    );
    await tester.tap(find.text('LxMusic-NG Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();
    expect(_statusText(tester, 'generic_3x7_demo'), '已校准');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('layout list reports calibrated and uncalibrated items', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bundle = loadTestYamlAssetBundle();
    final repository = _MemoryCalibrationRepository(
      Calibration(
        key: const CalibrationKey(
          profileId: 'sky',
          layoutId: 'sky_3x5',
          deviceId: 'android-test',
        ),
        orientation: 'portrait',
        leftTopPx: (10, 20),
        rightBottomPx: (100, 200),
        capturedAt: DateTime.utc(2026, 7, 31),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assetBundleProvider.overrideWithValue(bundle),
          calibrationPlatformProvider.overrideWithValue(
            const _FakeCalibrationPlatform(),
          ),
          calibrationRepositoryProvider.overrideWithValue(repository),
          persistedTargetSelectionProvider.overrideWithValue(
            const PersistedTargetSelection(
              profileId: 'sky',
              variantId: 'default',
              layoutId: 'sky_2x4',
            ),
          ),
          initialPersistedProfileUsageProvider.overrideWithValue(
            const PersistedProfileUsage(<String, int>{}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [CurrentTargetAction()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('current-target-action')),
        matching: find.text(' (未校准)'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('current-target-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('target-filter-profile')),
      '光遇',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '光遇'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();

    expect(_statusText(tester, 'sky_3x5'), '已校准');
    expect(_statusText(tester, 'sky_2x4'), '未校准');
    debugDefaultTargetPlatformOverride = null;
  });
}

class _FakeCalibrationPlatform extends MethodChannelCalibrationPlatform {
  const _FakeCalibrationPlatform();

  @override
  Future<CalibrationPlatformState> getState() async {
    return const CalibrationPlatformState(
      supported: true,
      accessibilityEnabled: true,
      apiLevel: 36,
      deviceId: 'android-test',
      deviceDisplayName: 'Android Test',
      viewportWidthPx: 1080,
      viewportHeightPx: 1920,
      density: 1,
      displayRotation: 0,
    );
  }
}

class _MemoryCalibrationRepository implements MutableCalibrationRepository {
  _MemoryCalibrationRepository([Calibration? calibration])
    : _calibration = calibration;

  Calibration? _calibration;

  @override
  Future<void> delete(CalibrationKey key) async {
    if (_calibration?.key == key) {
      _calibration = null;
    }
  }

  @override
  List<Calibration> list() => <Calibration>[?_calibration];

  @override
  Calibration? load(CalibrationKey key) =>
      _calibration?.key == key ? _calibration : null;

  @override
  Future<void> save(Calibration calibration) async {
    _calibration = calibration;
  }
}

String _chipText(WidgetTester tester, String key) {
  final chipFinder = find.byKey(ValueKey(key));
  final text = find.descendant(of: chipFinder, matching: find.byType(Text));
  return tester.widgetList<Text>(text).first.data ?? '';
}

VoidCallback? _chipOnPressed(WidgetTester tester, String key) {
  return tester.widget<ActionChip>(find.byKey(ValueKey(key))).onPressed;
}

String _statusText(WidgetTester tester, String layoutId) {
  final status = find.byKey(ValueKey('layout-calibration-status-$layoutId'));
  return tester
          .widgetList<Text>(
            find.descendant(of: status, matching: find.byType(Text)),
          )
          .single
          .data ??
      '';
}
