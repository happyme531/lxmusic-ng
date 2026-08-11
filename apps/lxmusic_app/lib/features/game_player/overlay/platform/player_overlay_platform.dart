import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../models/game_player_snapshot.dart';

final playerOverlayPlatformProvider = Provider<PlayerOverlayPlatform>((ref) {
  final platform = MethodChannelPlayerOverlayPlatform();
  ref.onDispose(platform.dispose);
  return platform;
});

typedef PlayerOverlayActionHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> action);

class PlayerOverlayPlatformState {
  const PlayerOverlayPlatformState({
    required this.supported,
    required this.accessibilityEnabled,
    required this.serviceReady,
    required this.overlayVisible,
  });

  final bool supported;
  final bool accessibilityEnabled;
  final bool serviceReady;
  final bool overlayVisible;

  factory PlayerOverlayPlatformState.fromMap(Map<Object?, Object?> map) {
    return PlayerOverlayPlatformState(
      supported: map['supported'] == true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
      serviceReady: map['serviceReady'] == true,
      overlayVisible: map['overlayVisible'] == true,
    );
  }
}

class PlayerOverlayRequest {
  const PlayerOverlayRequest({
    required this.title,
    required this.durationMs,
    this.profileLabel,
    this.session,
  });

  final String title;
  final int durationMs;
  final String? profileLabel;
  final Map<String, Object?>? session;

  factory PlayerOverlayRequest.fromSnapshot(GamePlayerSnapshot snapshot) {
    final track = snapshot.currentTrack;
    return PlayerOverlayRequest(
      title: track?.displayName ?? '暂无曲目',
      durationMs: track?.durationMs ?? 1,
      profileLabel: snapshot.profileLabel,
      session: snapshot.toMap(),
    );
  }

  Map<String, Object?> toMap() =>
      session ??
      <String, Object?>{
        'title': title,
        'durationMs': durationMs,
        if (profileLabel != null) 'profileLabel': profileLabel,
      };
}

class PlayerOverlayCommandResult {
  const PlayerOverlayCommandResult({required this.success, this.message});

  final bool success;
  final String? message;

  factory PlayerOverlayCommandResult.fromMap(Map<Object?, Object?> map) {
    return PlayerOverlayCommandResult(
      success: map['status'] == 'shown' || map['status'] == 'updated',
      message: map['message'] as String?,
    );
  }
}

abstract interface class PlayerOverlayPlatform {
  Future<PlayerOverlayPlatformState> getState();

  Future<PlayerOverlayCommandResult> showOverlay(PlayerOverlayRequest request);

  Future<void> hideOverlay();

  Future<void> openAccessibilitySettings();

  Future<void> updateOverlay(GamePlayerSnapshot snapshot);

  void setActionHandler(PlayerOverlayActionHandler? handler);

  void dispose();
}

class MethodChannelPlayerOverlayPlatform implements PlayerOverlayPlatform {
  MethodChannelPlayerOverlayPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const String channelName =
      'dev.happyme531.clxmidiplayer.ng/player_overlay';

  final MethodChannel channel;
  PlayerOverlayActionHandler? _actionHandler;
  GamePlayerSnapshot? _lastSentSnapshot;
  GamePlayerSnapshot? _pendingSnapshot;
  Future<void>? _updateLoop;
  bool _disposed = false;

  @override
  Future<PlayerOverlayPlatformState> getState() async {
    return PlayerOverlayPlatformState.fromMap(await _mapCall('getState'));
  }

  @override
  Future<PlayerOverlayCommandResult> showOverlay(
    PlayerOverlayRequest request,
  ) async {
    return PlayerOverlayCommandResult.fromMap(
      await _mapCall('showOverlay', request.toMap()),
    );
  }

  @override
  Future<void> hideOverlay() => channel.invokeMethod<void>('hideOverlay');

  @override
  Future<void> openAccessibilitySettings() =>
      channel.invokeMethod<void>('openAccessibilitySettings');

  @override
  Future<void> updateOverlay(GamePlayerSnapshot snapshot) {
    if (_disposed) return Future<void>.value();
    _pendingSnapshot = snapshot;
    return _updateLoop ??= _drainUpdates();
  }

  Future<void> _drainUpdates() async {
    try {
      while (!_disposed) {
        final snapshot = _pendingSnapshot;
        if (snapshot == null) break;
        _pendingSnapshot = null;
        await channel.invokeMethod<void>(
          'updateOverlay',
          snapshot.toOverlayUpdateMap(_lastSentSnapshot),
        );
        _lastSentSnapshot = snapshot;
      }
    } catch (_) {
      // Force the next attempt to carry a complete catalog if this channel
      // update did not reach the native overlay host.
      _pendingSnapshot = null;
      _lastSentSnapshot = null;
      rethrow;
    } finally {
      _updateLoop = null;
    }
  }

  @override
  void setActionHandler(PlayerOverlayActionHandler? handler) {
    _actionHandler = handler;
    channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'overlayAction' || call.arguments is! Map) return null;
    final action = <String, Object?>{
      for (final entry in (call.arguments as Map).entries)
        entry.key.toString(): entry.value,
    };
    return _actionHandler?.call(action);
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingSnapshot = null;
    _lastSentSnapshot = null;
    _actionHandler = null;
    channel.setMethodCallHandler(null);
  }

  Future<Map<Object?, Object?>> _mapCall(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: '$method returned no result.',
      );
    }
    return result;
  }
}
