import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/game_playback_plan_service.dart';

final accessibilityPlaybackPlatformProvider =
    Provider<AccessibilityPlaybackPlatform>((ref) {
      final platform = MethodChannelAccessibilityPlaybackPlatform();
      ref.onDispose(platform.dispose);
      return platform;
    });

typedef AccessibilityPlaybackEventHandler =
    Future<void> Function(Map<String, Object?> event);

class AccessibilityPlaybackResult {
  const AccessibilityPlaybackResult({
    required this.success,
    required this.status,
    this.errorCode,
    this.message,
    this.playbackId,
    this.positionMs,
  });

  final bool success;
  final String status;
  final String? errorCode;
  final String? message;
  final String? playbackId;
  final int? positionMs;

  factory AccessibilityPlaybackResult.fromMap(Map<Object?, Object?> map) {
    final status = map['status'] as String? ?? 'error';
    return AccessibilityPlaybackResult(
      success:
          status == 'started' ||
          status == 'playing' ||
          status == 'paused' ||
          status == 'stopped',
      status: status,
      errorCode: map['errorCode'] as String?,
      message: map['message'] as String?,
      playbackId: map['playbackId'] as String?,
      positionMs: (map['positionMs'] as num?)?.toInt(),
    );
  }
}

abstract interface class AccessibilityPlaybackPlatform {
  Future<AccessibilityPlaybackResult> start({
    required PreparedGamePlayback playback,
    required String playbackId,
    required int positionMs,
    required double speed,
    required int timingOffsetMs,
    required int tapDurationMs,
  });

  Future<AccessibilityPlaybackResult> pause();

  Future<AccessibilityPlaybackResult> stop();

  Future<AccessibilityPlaybackResult> getState();

  void setEventHandler(AccessibilityPlaybackEventHandler? handler);

  void dispose();
}

class MethodChannelAccessibilityPlaybackPlatform
    implements AccessibilityPlaybackPlatform {
  MethodChannelAccessibilityPlaybackPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const String channelName =
      'dev.happyme531.clxmidiplayer.ng/accessibility_playback';

  final MethodChannel channel;
  AccessibilityPlaybackEventHandler? _eventHandler;

  @override
  Future<AccessibilityPlaybackResult> start({
    required PreparedGamePlayback playback,
    required String playbackId,
    required int positionMs,
    required double speed,
    required int timingOffsetMs,
    required int tapDurationMs,
  }) async {
    return AccessibilityPlaybackResult.fromMap(
      await _mapCall('start', <String, Object?>{
        'playbackId': playbackId,
        'plan': playback.executablePlan.toJson(),
        'positionMs': positionMs,
        'speed': speed,
        'timingOffsetMs': timingOffsetMs,
        'orientation': playback.orientation,
        if (playback.targetPackageName != null)
          'targetPackageName': playback.targetPackageName,
        'physicalWidthPx': playback.physicalWidthPx,
        'physicalHeightPx': playback.physicalHeightPx,
        'displayRotation': playback.displayRotation,
        'viewportPx': <double>[
          playback.viewportPx.left,
          playback.viewportPx.top,
          playback.viewportPx.right,
          playback.viewportPx.bottom,
        ],
        'tapDurationMs': tapDurationMs,
      }),
    );
  }

  @override
  Future<AccessibilityPlaybackResult> pause() async {
    return AccessibilityPlaybackResult.fromMap(await _mapCall('pause'));
  }

  @override
  Future<AccessibilityPlaybackResult> stop() async {
    return AccessibilityPlaybackResult.fromMap(await _mapCall('stop'));
  }

  @override
  Future<AccessibilityPlaybackResult> getState() async {
    return AccessibilityPlaybackResult.fromMap(await _mapCall('getState'));
  }

  @override
  void setEventHandler(AccessibilityPlaybackEventHandler? handler) {
    _eventHandler = handler;
    channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'playbackEvent' || call.arguments is! Map) return null;
    await _eventHandler?.call(<String, Object?>{
      for (final entry in (call.arguments as Map).entries)
        entry.key.toString(): entry.value,
    });
    return null;
  }

  @override
  void dispose() {
    _eventHandler = null;
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
