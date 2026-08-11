enum PlayerOverlayPanelState {
  mini,
  edgeDocked,
  compact,
  quickControls,
  speedEditor,
  songPicker,
  targetPicker,
}

enum PlayerOverlayQuickTab { performance, display }

enum PlayerOverlayDockSide { left, right }

class PlayerOverlayWindowSize {
  const PlayerOverlayWindowSize(this.width, this.height);

  final double width;
  final double height;

  static PlayerOverlayWindowSize forState(PlayerOverlayPanelState state) {
    return switch (state) {
      PlayerOverlayPanelState.mini => const PlayerOverlayWindowSize(104, 58),
      PlayerOverlayPanelState.edgeDocked => const PlayerOverlayWindowSize(
        44,
        58,
      ),
      PlayerOverlayPanelState.compact => const PlayerOverlayWindowSize(420, 82),
      PlayerOverlayPanelState.quickControls => const PlayerOverlayWindowSize(
        420,
        251,
      ),
      PlayerOverlayPanelState.speedEditor => const PlayerOverlayWindowSize(
        420,
        217,
      ),
      PlayerOverlayPanelState.songPicker => const PlayerOverlayWindowSize(
        420,
        309,
      ),
      PlayerOverlayPanelState.targetPicker => const PlayerOverlayWindowSize(
        440,
        300,
      ),
    };
  }
}
