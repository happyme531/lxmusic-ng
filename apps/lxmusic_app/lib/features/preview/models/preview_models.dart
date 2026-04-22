import 'package:lxmusic_core/lxmusic_core.dart';

import '../../library/models/music_file.dart';
import '../../workbench/models/song_config.dart';

class PreviewSessionData {
  const PreviewSessionData({
    required this.file,
    required this.profile,
    required this.variant,
    required this.layout,
    required this.config,
    required this.rawScore,
    required this.transformedScore,
    required this.semanticPlan,
  });

  final MusicFile file;
  final GameProfile profile;
  final InstrumentVariant variant;
  final KeyLayout layout;
  final SongConfig config;
  final Score rawScore;
  final Score transformedScore;
  final SemanticPlan semanticPlan;

  String get sessionKey =>
      '${file.fileName}__${profile.id}__${variant.id}__${layout.id}';
}

class PreviewLaneNote {
  const PreviewLaneNote({
    required this.keyId,
    required this.pitch,
    required this.startMs,
    required this.durationMs,
    required this.velocity,
    required this.isPoint,
  });

  final String keyId;
  final int pitch;
  final int startMs;
  final int durationMs;
  final int velocity;
  final bool isPoint;
}

class PreviewKeyboardKey {
  const PreviewKeyboardKey({required this.key, required this.laneIndex});

  final KeyDefinition key;
  final int laneIndex;
}

class PreviewLayoutGeometry {
  PreviewLayoutGeometry._({
    required this.laneKeys,
    required this.keyboardKeys,
    required this.laneIndexByKeyId,
  });

  final List<PreviewKeyboardKey> laneKeys;
  final List<KeyDefinition> keyboardKeys;
  final Map<String, int> laneIndexByKeyId;

  int get laneCount => laneKeys.length;

  double laneCenter(int laneIndex) {
    if (laneCount == 0) return 0.5;
    return (laneIndex + 0.5) / laneCount;
  }

  factory PreviewLayoutGeometry.fromLayout(KeyLayout layout) {
    final laneOrdered = layout.keys.where((key) => key.pitch != null).toList()
      ..sort((a, b) {
        final pitch = a.pitch!.compareTo(b.pitch!);
        if (pitch != 0) return pitch;
        final x = a.normX.compareTo(b.normX);
        if (x != 0) return x;
        final y = a.normY.compareTo(b.normY);
        if (y != 0) return y;
        return a.id.compareTo(b.id);
      });
    if (laneOrdered.isEmpty) {
      return PreviewLayoutGeometry._(
        laneKeys: const <PreviewKeyboardKey>[],
        keyboardKeys: layout.keys,
        laneIndexByKeyId: const <String, int>{},
      );
    }
    final laneIndexByKeyId = <String, int>{};
    final laneKeys = <PreviewKeyboardKey>[
      for (var index = 0; index < laneOrdered.length; index++)
        PreviewKeyboardKey(key: laneOrdered[index], laneIndex: index),
    ];
    for (final key in laneKeys) {
      laneIndexByKeyId[key.key.id] = key.laneIndex;
    }
    return PreviewLayoutGeometry._(
      laneKeys: laneKeys,
      keyboardKeys: layout.keys,
      laneIndexByKeyId: laneIndexByKeyId,
    );
  }
}
