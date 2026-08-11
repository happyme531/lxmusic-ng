import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../models/player_overlay_state.dart';

typedef PlayerOverlaySessionHandler =
    Future<void> Function(Map<String, Object?> session);

abstract interface class PlayerOverlayBridge {
  Future<Map<String, Object?>> loadInitialSession();

  void setSessionHandler(PlayerOverlaySessionHandler? handler);

  Future<void> resize(PlayerOverlayWindowSize size, {bool animate = true});

  Future<void> moveBy(double deltaX, double deltaY);

  Future<void> setResizeMode(bool enabled);

  Future<void> setTextInputActive(bool active);

  Future<void> setTargetPickerActive(bool active);

  Future<Map<String, Object?>> sendAction(Map<String, Object?> action);

  Future<void> close();

  void dispose();
}

class MethodChannelPlayerOverlayBridge implements PlayerOverlayBridge {
  MethodChannelPlayerOverlayBridge({
    this.channel = const MethodChannel(channelName),
  });

  static const String channelName =
      'dev.happyme531.clxmidiplayer.ng/player_overlay/control';

  final MethodChannel channel;
  PlayerOverlaySessionHandler? _sessionHandler;
  int _actionTraceId = 0;

  @override
  Future<Map<String, Object?>> loadInitialSession() async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'getInitialSession',
    );
    return _stringKeyed(result);
  }

  @override
  void setSessionHandler(PlayerOverlaySessionHandler? handler) {
    _sessionHandler = handler;
    channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'updateSession') return null;
    final arguments = call.arguments;
    if (arguments is! Map) return null;
    await _sessionHandler?.call(
      _stringKeyed(Map<Object?, Object?>.from(arguments)),
    );
    return null;
  }

  @override
  Future<void> resize(PlayerOverlayWindowSize size, {bool animate = true}) {
    return channel.invokeMethod<void>('resize', <String, Object?>{
      'widthDp': size.width,
      'heightDp': size.height,
      'animate': animate,
    });
  }

  @override
  Future<void> moveBy(double deltaX, double deltaY) {
    return channel.invokeMethod<void>('moveBy', <String, Object?>{
      'deltaX': deltaX,
      'deltaY': deltaY,
    });
  }

  @override
  Future<void> setResizeMode(bool enabled) {
    return channel.invokeMethod<void>('setResizeMode', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  Future<void> setTextInputActive(bool active) {
    return channel.invokeMethod<void>('setTextInputActive', <String, Object?>{
      'active': active,
    });
  }

  @override
  Future<void> setTargetPickerActive(bool active) {
    return channel.invokeMethod<void>(
      'setTargetPickerActive',
      <String, Object?>{'active': active},
    );
  }

  @override
  Future<Map<String, Object?>> sendAction(Map<String, Object?> action) async {
    final traceId = ++_actionTraceId;
    final type = action['type'] ?? 'unknown';
    final commandId = action['commandId'];
    final watch = Stopwatch()..start();
    _logAction(
      'side=overlay phase=send_start trace=$traceId type=$type '
      'command_id=$commandId',
    );
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'playerAction',
        action,
      );
      final mapped = _stringKeyed(result);
      _logAction(
        'side=overlay phase=send_done trace=$traceId type=$type '
        'command_id=$commandId elapsed_ms=${watch.elapsedMilliseconds} '
        'status=${mapped['status']} keys=${mapped.keys.join(',')}',
      );
      return mapped;
    } catch (error, stackTrace) {
      _logAction(
        'side=overlay phase=send_error trace=$traceId type=$type '
        'command_id=$commandId elapsed_ms=${watch.elapsedMilliseconds} '
        'error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> close() => channel.invokeMethod<void>('close');

  @override
  void dispose() {
    _sessionHandler = null;
    channel.setMethodCallHandler(null);
  }

  static Map<String, Object?> _stringKeyed(Map<Object?, Object?>? source) {
    if (source == null) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in source.entries) entry.key.toString(): entry.value,
    };
  }

  static void _logAction(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      '[OVERLAY_ACTION] $message',
      name: 'lxmusic.overlay.action',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
