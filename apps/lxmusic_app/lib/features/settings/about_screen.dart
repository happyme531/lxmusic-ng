import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _repoUrl = 'https://github.com/happyme531/lxmusic-ng';
  static const _licenseName = 'GNU Affero General Public License v3.0';
  late final Future<String> _appVersionFuture = _loadAppVersion();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('关于 LxMusic-NG')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LxMusic-NG', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      '留香音乐盒的新实现，当前聚焦跨平台的曲库、工作台与预览体验。',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FutureBuilder<String>(
                          future: _appVersionFuture,
                          builder: (context, snapshot) {
                            return _InfoChip(
                              icon: Icons.sell_outlined,
                              label: '版本',
                              value: snapshot.data ?? '读取中',
                            );
                          },
                        ),
                        _InfoChip(
                          icon: Icons.gavel_outlined,
                          label: '协议',
                          value: 'AGPLv3',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code_outlined),
                    title: const Text('项目仓库'),
                    subtitle: const Text(_repoUrl),
                    trailing: TextButton(
                      onPressed: () =>
                          _copyText(context, _repoUrl, message: '已复制项目链接'),
                      child: const Text('复制'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('开源协议'),
                    subtitle: const Text(_licenseName),
                    trailing: TextButton(
                      onPressed: () =>
                          _copyText(context, _licenseName, message: '已复制协议名称'),
                      child: const Text('复制'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('说明', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    const Text(
                      '本项目代码采用 AGPLv3 开源。分发、修改或提供网络服务时，'
                      '请遵守对应的源代码公开义务。',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final appVersion = await _appVersionFuture;
                        if (!context.mounted) return;
                        showLicensePage(
                          context: context,
                          applicationName: 'LxMusic-NG',
                          applicationVersion: appVersion,
                        );
                      },
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('查看第三方许可'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyText(
    BuildContext context,
    String text, {
    required String message,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final buildNumber = packageInfo.buildNumber.trim();
    if (buildNumber.isEmpty) return packageInfo.version;
    return '${packageInfo.version}+$buildNumber';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: $value'),
        ],
      ),
    );
  }
}
