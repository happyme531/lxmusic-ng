import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AiHubScreen extends StatelessWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 创作实验室')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFF5ECD8), Color(0xFFE6F2EF)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            const SizedBox(height: 12),
            _FeatureCard(
              title: 'AI 音频转 MIDI',
              subtitle: '把钢琴或多乐器录音变成可编辑、可演奏的 MIDI 音轨',
              onTap: () => context.go('/ai/audio-to-midi'),
            ),
            const SizedBox(height: 16),
            const _ComingSoonCard(),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.arrow_forward_rounded,
                size: 32,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
      child: const ListTile(
        leading: Icon(Icons.add_circle_outline),
        title: Text('更多 AI 功能正在路上'),
        subtitle: Text('敬请期待…'),
      ),
    );
  }
}
