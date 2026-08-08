import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/core/service_locator.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/providers/audio_to_midi_provider.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_model_repository.dart';
import 'package:lxmusic_app/features/ai/audio_to_midi/services/muscriptor_onnx_runner.dart';
import 'package:lxmusic_app/features/settings/settings_screen.dart';

void main() {
  testWidgets('settings clears AI model cache after confirmation', (
    tester,
  ) async {
    final repository = _FakeModelRepository();
    final runner = _FakeOnnxRunner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameProfilesProvider.overrideWithValue(const []),
          muscriptorModelRepositoryProvider.overrideWithValue(repository),
          muscriptorOnnxRunnerProvider.overrideWithValue(runner),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('清除 AI 模型缓存'), findsOneWidget);
    expect(find.text('MuScriptor Medium W4A32 · 约 213 MiB'), findsOneWidget);

    await tester.tap(find.text('清除 AI 模型缓存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已导出的 MIDI 不受影响'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();

    expect(repository.clearCount, 1);
    expect(runner.closeCount, 1);
    expect(find.text('当前没有已下载的 AI 模型'), findsOneWidget);
    expect(find.text('AI 模型缓存已清除'), findsOneWidget);
  });
}

class _FakeModelRepository implements MuscriptorModelRepository {
  bool cached = true;
  int clearCount = 0;

  @override
  Future<void> clearCache() async {
    clearCount++;
    cached = false;
  }

  @override
  Future<MuscriptorModelPaths> download({
    DownloadProgressCallback? onProgress,
    DownloadStatusCallback? onStatus,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasCache() async => cached;

  @override
  Future<bool> isReady() async => cached;

  @override
  Future<MuscriptorModelPaths> paths() {
    throw UnimplementedError();
  }
}

class _FakeOnnxRunner extends MuscriptorOnnxRunner {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }
}
