import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/ai_hub_screen.dart';
import '../features/ai/audio_to_midi/audio_to_midi_screen.dart';
import '../features/layout_preview/layout_preview_route.dart';
import '../features/layout_preview/layout_preview_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/models/music_file.dart';
import '../features/preview/preview_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/workbench/workbench_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/library',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return _AppShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/workbench',
              builder: (context, state) {
                final file = state.extra as MusicFile?;
                return WorkbenchScreen(initialFile: file);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/preview',
              builder: (context, state) => const PreviewScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ai',
              builder: (context, state) => const AiHubScreen(),
              routes: [
                GoRoute(
                  path: 'audio-to-midi',
                  builder: (context, state) => const AudioToMidiScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'about',
                  builder: (context, state) => const AboutScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: LayoutPreviewRoute.path,
      name: LayoutPreviewRoute.name,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final profileId = state.pathParameters['profileId']!;
        final layoutId = state.pathParameters['layoutId']!;
        final selectedKeyId = state.uri.queryParameters['keyId'];
        return LayoutPreviewScreen(
          profileId: profileId,
          layoutId: layoutId,
          initialSelectedKeyId: selectedKeyId,
        );
      },
    ),
  ],
);

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: '曲库',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '工作台',
          ),
          NavigationDestination(
            icon: Icon(Icons.piano_outlined),
            selectedIcon: Icon(Icons.piano),
            label: '预览',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
