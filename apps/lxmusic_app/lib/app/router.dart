import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/ai_hub_screen.dart';
import '../features/ai/audio_to_midi/audio_to_midi_screen.dart';
import '../features/game_player/overlay/widgets/player_overlay_launcher_button.dart';
import '../features/layout_preview/layout_preview_route.dart';
import '../features/layout_preview/layout_preview_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/models/music_file.dart';
import '../features/preview/preview_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/crash_debug_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/workbench/workbench_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
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
      parentNavigatorKey: rootNavigatorKey,
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
    GoRoute(
      path: '/crash-debug',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CrashDebugScreen(),
    ),
  ],
);

class _AppShell extends StatefulWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  static const _settingsIndex = 4;
  static const _unlockTapCount = 7;
  static const _unlockWindow = Duration(seconds: 4);

  int _settingsTapCount = 0;
  DateTime? _lastSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      floatingActionButton: const PlayerOverlayLauncherButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          if (index == _settingsIndex) _onSettingsDestinationTapped();
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
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

  void _onSettingsDestinationTapped() {
    final now = DateTime.now();
    if (_lastSettingsTap == null ||
        now.difference(_lastSettingsTap!) > _unlockWindow) {
      _settingsTapCount = 0;
    }
    _lastSettingsTap = now;
    _settingsTapCount += 1;

    if (_settingsTapCount >= _unlockTapCount) {
      _settingsTapCount = 0;
      _lastSettingsTap = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/crash-debug');
      });
    }
  }
}
