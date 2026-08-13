import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class CrashDebugScreen extends StatelessWidget {
  const CrashDebugScreen({super.key});

  static const _channel = MethodChannel(
    'dev.happyme531.clxmidiplayer.ng/crash_test',
  );

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('调试菜单')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('崩溃报告测试', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('报告仅保存在本机，不会自动上传。闪退后重新打开 App，应出现手动分享提示。'),
          const SizedBox(height: 16),
          _DebugActionCard(
            title: '生成 Dart 测试报告',
            description: '记录一条 Dart 异常但不退出 App，用于检查本地保存链路。',
            icon: Icons.bug_report_outlined,
            enabled: _supported,
            onPressed: () => _captureDartReport(context),
          ),
          const SizedBox(height: 12),
          _DebugActionCard(
            title: '触发 Kotlin 崩溃',
            description: '让 Android 主线程抛出未捕获异常，App 会立即闪退。',
            icon: Icons.android,
            enabled: _supported,
            destructive: true,
            onPressed: () => _confirmCrash(
              context,
              title: '确认触发 Kotlin 崩溃？',
              onConfirmed: () => _channel.invokeMethod<void>('crashKotlin'),
            ),
          ),
          const SizedBox(height: 12),
          _DebugActionCard(
            title: '触发 native 段错误',
            description: '向当前进程发送真实 SIGSEGV，验证 C/C++/ONNX Runtime 同类崩溃的捕获链路。',
            icon: Icons.memory,
            enabled: _supported,
            destructive: true,
            onPressed: () => _confirmCrash(
              context,
              title: '确认触发 native SIGSEGV？',
              onConfirmed: () =>
                  _channel.invokeMethod<void>('crashNativeSigsegv'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureDartReport(BuildContext context) async {
    final error = StateError('LxMusic-NG manual Dart crash-report test');
    await Sentry.captureException(error, stackTrace: StackTrace.current);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('测试报告已保存；重新打开 App 可验证分享提示。')));
  }

  Future<void> _confirmCrash(
    BuildContext context, {
    required String title,
    required FutureOr<void> Function() onConfirmed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('App 将立即关闭。请随后重新打开，检查是否出现崩溃报告分享提示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即测试'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Future<void>.sync(onConfirmed);
    }
  }
}

class _DebugActionCard extends StatelessWidget {
  const _DebugActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.destructive = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool enabled;
  final bool destructive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: enabled ? onPressed : null,
      ),
    );
  }
}
