import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/service_locator.dart';
import '../../../calibration/calibration_launcher.dart';
import '../../../calibration/platform/calibration_platform.dart';
import '../../../calibration/providers/calibration_provider.dart';
import '../../../workbench/providers/workbench_provider.dart';
import '../../providers/game_player_provider.dart';
import '../platform/player_overlay_platform.dart';

class PlayerOverlayLauncherButton extends ConsumerStatefulWidget {
  const PlayerOverlayLauncherButton({super.key});

  @override
  ConsumerState<PlayerOverlayLauncherButton> createState() =>
      _PlayerOverlayLauncherButtonState();
}

class _PlayerOverlayLauncherButtonState
    extends ConsumerState<PlayerOverlayLauncherButton>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _launchWhenResumed = false;
  late final PlayerOverlayPlatform _platform;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform = ref.read(playerOverlayPlatformProvider);
    _platform.setActionHandler(_handleOverlayAction);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _platform.setActionHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _launchWhenResumed) {
      unawaited(_resumePendingLaunch());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gamePlayerProvider, (_, snapshot) {
      unawaited(_platform.updateOverlay(snapshot).catchError((_) {}));
    });
    return FloatingActionButton(
      key: const ValueKey('player-overlay-launcher'),
      tooltip: '打开悬浮播放器',
      onPressed: _busy ? null : _openOverlay,
      child: _busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : const Icon(Icons.picture_in_picture_alt_rounded),
    );
  }

  Future<void> _openOverlay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final platform = _platform;
      final state = await platform.getState();
      if (!mounted) return;
      if (!state.supported) {
        _showMessage('当前设备不支持游戏内悬浮播放器。');
        return;
      }
      if (!state.accessibilityEnabled) {
        final openSettings = await _confirmAccessibilityPermission();
        if (!mounted || openSettings != true) return;
        _launchWhenResumed = true;
        await platform.openAccessibilitySettings();
        return;
      }
      await _showOverlay(platform);
    } catch (error) {
      _launchWhenResumed = false;
      if (mounted) _showMessage('无法打开悬浮播放器：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumePendingLaunch() async {
    if (_busy) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted && _launchWhenResumed) {
          unawaited(_resumePendingLaunch());
        }
      });
      return;
    }
    _launchWhenResumed = false;
    setState(() => _busy = true);
    try {
      final platform = _platform;
      for (var attempt = 0; attempt < 5; attempt++) {
        final state = await platform.getState();
        if (!mounted || !state.accessibilityEnabled) return;
        if (state.serviceReady) {
          await _showOverlay(platform);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      if (mounted) _showMessage('无障碍服务仍在启动，请再点一次悬浮按钮。');
    } catch (error) {
      if (mounted) _showMessage('无法打开悬浮播放器：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOverlay(PlayerOverlayPlatform platform) async {
    final snapshot = ref.read(gamePlayerProvider);
    final result = await platform.showOverlay(
      PlayerOverlayRequest.fromSnapshot(snapshot),
    );
    if (!mounted || result.success) return;
    _showMessage(result.message ?? '悬浮播放器启动失败。');
  }

  Future<Map<String, Object?>> _handleOverlayAction(
    Map<String, Object?> action,
  ) async {
    final type = action['type'] ?? 'unknown';
    final commandId = action['commandId'];
    final watch = Stopwatch()..start();
    _logOverlayAction(
      'side=main phase=receive type=$type command_id=$commandId '
      'deadline=${action['deadlineUnixMs']}',
    );
    try {
      final result = await _dispatchOverlayAction(action);
      _logOverlayAction(
        'side=main phase=reply type=$type command_id=$commandId '
        'elapsed_ms=${watch.elapsedMilliseconds} status=${result['status']} '
        'keys=${result.keys.join(',')}',
      );
      return result;
    } catch (error, stackTrace) {
      _logOverlayAction(
        'side=main phase=error type=$type command_id=$commandId '
        'elapsed_ms=${watch.elapsedMilliseconds} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _dispatchOverlayAction(
    Map<String, Object?> action,
  ) async {
    final deadlineUnixMs = (action['deadlineUnixMs'] as num?)?.toInt();
    if (deadlineUnixMs != null &&
        DateTime.now().millisecondsSinceEpoch > deadlineUnixMs) {
      throw StateError('悬浮窗操作已超时。');
    }
    switch (action['type']) {
      case 'calibrationGetState':
        return (await ref.read(calibrationPlatformProvider).getState()).toMap();
      case 'calibrationFindTargets':
        final hints = (action['packageNameHints'] as List? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false);
        final targets = await ref
            .read(calibrationPlatformProvider)
            .findLaunchableTargets(hints);
        return <String, Object?>{
          'status': 'ok',
          'targets': targets.map((target) => target.toMap()).toList(),
        };
      case 'calibrationOpenAccessibilitySettings':
        await ref
            .read(calibrationManagerProvider.notifier)
            .openAccessibilitySettings();
        return const <String, Object?>{'status': 'ok'};
      case 'calibrationStartCurrentTarget':
        final profile = ref.read(selectedProfileProvider);
        final layout = ref.read(selectedLayoutProvider);
        if (profile == null || layout == null) {
          throw StateError('请先选择游戏、乐器和键位布局。');
        }
        _logOverlayAction(
          'side=main phase=calibration_launch_start '
          'profile=${profile.id} layout=${layout.id}',
        );
        final result = await launchCalibration(
          context: context,
          ref: ref,
          profile: profile,
          layout: layout,
          launchOrigin: CalibrationLaunchOrigin.playerOverlay,
        );
        _logOverlayAction(
          'side=main phase=calibration_launch_done '
          'profile=${profile.id} layout=${layout.id} '
          'status=${result?.status.name}',
        );
        return result?.toMap() ??
            const <String, Object?>{'status': 'cancelled'};
      case 'calibrationStartSession':
        final profileId = action['profileId'] as String?;
        final layoutId = action['layoutId'] as String?;
        if (profileId == null || layoutId == null) {
          throw StateError('校准请求缺少游戏或键位 ID。');
        }
        final profile = ref.read(profileRepositoryProvider).load(profileId);
        final layout = ref.read(layoutRepositoryProvider).load(layoutId);
        if (profile.layoutById(layout.id) == null) {
          throw StateError('所选键位不属于当前游戏配置。');
        }
        final requestedPackage = (action['targetPackageName'] as String?)
            ?.trim();
        _logOverlayAction(
          'side=main phase=calibration_session_start '
          'profile=$profileId layout=$layoutId '
          'target=${requestedPackage ?? 'manual'}',
        );
        final result = await ref
            .read(calibrationManagerProvider.notifier)
            .startSession(
              profile: profile,
              layout: layout,
              launchOrigin: CalibrationLaunchOrigin.playerOverlay,
              targetPackageName:
                  requestedPackage == null || requestedPackage.isEmpty
                  ? null
                  : requestedPackage,
            );
        _logOverlayAction(
          'side=main phase=calibration_session_done '
          'profile=$profileId layout=$layoutId status=${result.status.name} '
          'error_code=${result.errorCode}',
        );
        return result.toMap();
      case 'calibrationCancelSession':
        await ref.read(calibrationPlatformProvider).cancelSession();
        return const <String, Object?>{'status': 'ok'};
      case 'calibrationConsumePendingResult':
        final result = await ref
            .read(calibrationManagerProvider.notifier)
            .refresh();
        return <String, Object?>{
          'hasResult': result != null,
          if (result != null) ...result.toMap(),
        };
      default:
        _logOverlayAction(
          'side=main phase=player_action_start type=${action['type']} '
          'command_id=${action['commandId']}',
        );
        final result = await ref
            .read(gamePlayerProvider.notifier)
            .handleOverlayAction(action);
        _logOverlayAction(
          'side=main phase=player_action_done type=${action['type']} '
          'command_id=${action['commandId']}',
        );
        return result;
    }
  }

  static void _logOverlayAction(
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

  Future<bool?> _confirmAccessibilityPermission() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('启用游戏内悬浮播放器'),
        content: const Text(
          '悬浮播放器通过 LxMusic-NG 无障碍服务显示在游戏上方。'
          '请在系统设置中启用服务，返回后会自动打开播放器。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
