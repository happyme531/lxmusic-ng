import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CrashReportStartupPrompt {
  CrashReportStartupPrompt._();

  static const _channel = MethodChannel(
    'dev.happyme531.clxmidiplayer.ng/crash_report',
  );
  static bool _shown = false;

  static Future<void> showIfNeeded(BuildContext context) async {
    if (_shown || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final int count;
    try {
      count = await _channel.invokeMethod<int>('pendingReportCount') ?? 0;
    } on PlatformException {
      return;
    }
    if (count == 0 || !context.mounted) return;
    _shown = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: const Text('检测到上次运行异常'),
        content: Text(
          '已在本机保存 $count 份崩溃报告。你可以打包后通过 QQ 等应用手动分享给开发者；App 不会自动上传。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () async {
              await _deleteReports(dialogContext);
            },
            child: const Text('删除'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _shareReports(dialogContext);
            },
            icon: const Icon(Icons.share_outlined),
            label: const Text('分享报告'),
          ),
        ],
      ),
    );
  }

  static Future<void> _deleteReports(BuildContext context) async {
    try {
      await _channel.invokeMethod<void>('deletePendingReports');
      if (context.mounted) Navigator.pop(context);
    } on PlatformException catch (error) {
      if (context.mounted) _showError(context, error.message ?? '删除失败。');
    }
  }

  static Future<void> _shareReports(BuildContext context) async {
    try {
      await _channel.invokeMethod<void>('sharePendingReports');
      if (context.mounted) Navigator.pop(context);
    } on PlatformException catch (error) {
      if (context.mounted) _showError(context, error.message ?? '报告打包失败。');
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}
