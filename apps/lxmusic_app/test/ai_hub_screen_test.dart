import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lxmusic_app/features/ai/ai_hub_screen.dart';

void main() {
  testWidgets('AI card opens the audio-to-MIDI feature', (tester) async {
    final router = GoRouter(
      initialLocation: '/ai',
      routes: <RouteBase>[
        GoRoute(
          path: '/ai',
          builder: (context, state) => const AiHubScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'audio-to-midi',
              builder: (context, state) =>
                  const Scaffold(body: Text('audio-to-midi-detail')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('AI 音频转 MIDI'), findsOneWidget);
    expect(find.textContaining('把钢琴或多乐器录音变成'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded)).size,
      32,
    );
    await tester.tap(find.text('AI 音频转 MIDI'));
    await tester.pumpAndSettle();

    expect(find.text('audio-to-midi-detail'), findsOneWidget);
  });
}
