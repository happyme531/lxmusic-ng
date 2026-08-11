import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../../core/service_locator.dart';
import 'platform/calibration_platform.dart';
import 'providers/calibration_provider.dart';

Future<CalibrationSessionResult?> launchCalibration({
  required BuildContext context,
  required WidgetRef ref,
  required GameProfile profile,
  required KeyLayout layout,
  CalibrationLaunchOrigin launchOrigin = CalibrationLaunchOrigin.mainApp,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final manager = ref.read(calibrationManagerProvider.notifier);

  try {
    final platform = await ref.read(calibrationPlatformProvider).getState();
    if (!context.mounted) {
      return null;
    }
    if (!platform.canCalibrate) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前平台不支持 Android 悬浮层校准')),
      );
      return null;
    }
    if (!platform.accessibilityEnabled) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('启用键位校准服务'),
          content: const Text(
            '校准需要在游戏上方显示参考点。请先启用 LxMusic-NG 键位校准服务，返回后再点一次校准。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('打开设置'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await manager.openAccessibilitySettings();
      }
      return null;
    }

    final targets = await manager.findTargets(profile);
    if (!context.mounted) {
      return null;
    }
    String? targetPackageName;
    if (targets.length == 1) {
      targetPackageName = targets.single.packageName;
    } else if (targets.length > 1) {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('选择目标游戏'),
          children: [
            for (final target in targets)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(target.packageName),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sports_esports_outlined),
                  title: Text(target.label),
                  subtitle: Text(target.packageName),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('手动切换到目标游戏'),
            ),
          ],
        ),
      );
      if (selected == null) {
        return null;
      }
      targetPackageName = selected.isEmpty ? null : selected;
    }

    final result = await manager.startSession(
      profile: profile,
      layout: layout,
      launchOrigin: launchOrigin,
      targetPackageName: targetPackageName,
    );
    if (!context.mounted) {
      return result;
    }
    final message = switch (result.status) {
      CalibrationSessionStatus.started =>
        targetPackageName == null ? '校准悬浮条已启动，请切换到目标游戏' : '校准悬浮条已启动，正在切换到目标游戏',
      CalibrationSessionStatus.saved => '校准已保存',
      CalibrationSessionStatus.cancelled => '校准已取消',
      CalibrationSessionStatus.error =>
        result.message ?? '无法开始校准：${result.errorCode ?? 'unknown'}',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return result;
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('无法开始校准：$error')));
    }
    return null;
  }
}
