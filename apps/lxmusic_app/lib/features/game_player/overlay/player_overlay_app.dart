import 'package:flutter/material.dart';

import 'platform/player_overlay_bridge.dart';
import 'widgets/player_overlay_panel.dart';

class PlayerOverlayApp extends StatelessWidget {
  const PlayerOverlayApp({super.key, this.bridge});

  final PlayerOverlayBridge? bridge;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF63D3BC),
      brightness: Brightness.dark,
      surface: const Color(0xFF23272C),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        colorScheme: colors,
        brightness: Brightness.dark,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        scaffoldBackgroundColor: Colors.transparent,
        sliderTheme: const SliderThemeData(trackHeight: 3),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.1,
            ),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: PlayerOverlayPanel(
          bridge: bridge ?? MethodChannelPlayerOverlayBridge(),
        ),
      ),
    );
  }
}
