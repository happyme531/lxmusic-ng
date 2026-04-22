import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

import '../layout_key_label_formatter.dart';

class KeyLayoutPreviewCanvas extends StatelessWidget {
  const KeyLayoutPreviewCanvas({
    super.key,
    required this.layout,
    required this.config,
    this.selectedKeyId,
    this.onKeyTap,
  });

  final KeyLayout layout;
  final LayoutPreviewDisplayConfig config;
  final String? selectedKeyId;
  final ValueChanged<KeyDefinition>? onKeyTap;

  @override
  Widget build(BuildContext context) {
    if (layout.keys.isEmpty) {
      return DecoratedBox(
        decoration: _boardDecoration(context),
        child: const SizedBox(
          height: 240,
          child: Center(
            child: Text('这个键位没有可预览的按键'),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _LayoutPreviewMetrics.fromKeys(layout.keys);
        final width = constraints.maxWidth;
        final height = metrics.estimatedHeight;
        final keySize = metrics.keySizeFor(
          width: width,
          height: height,
        );
        final horizontalPadding = keySize * 0.9;
        final verticalPadding = keySize * 0.9;
        final innerWidth = math.max(1.0, width - horizontalPadding * 2);
        final innerHeight = math.max(1.0, height - verticalPadding * 2);

        return DecoratedBox(
          decoration: _boardDecoration(context),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BoardGuidesPainter(
                      rowCount: metrics.rowCount,
                    ),
                  ),
                ),
                for (final key in layout.keys)
                  Positioned(
                    key: ValueKey('layout-key-${key.id}'),
                    left: horizontalPadding +
                        key.normX * innerWidth -
                        keySize / 2,
                    top: verticalPadding +
                        key.normY * innerHeight -
                        keySize / 2,
                    width: keySize,
                    height: keySize,
                    child: _PreviewKeyNode(
                      keyDefinition: key,
                      config: config,
                      selected: selectedKeyId == key.id,
                      onTap: onKeyTap == null ? null : () => onKeyTap!(key),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  BoxDecoration _boardDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          scheme.surface,
          scheme.surfaceContainerHighest,
        ],
      ),
      border: Border.all(
        color: scheme.outlineVariant,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

class _PreviewKeyNode extends StatelessWidget {
  const _PreviewKeyNode({
    required this.keyDefinition,
    required this.config,
    required this.selected,
    this.onTap,
  });

  final KeyDefinition keyDefinition;
  final LayoutPreviewDisplayConfig config;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    final background = selected ? scheme.primary : Colors.white;

    return Tooltip(
      message: keyDefinition.pitch == null
          ? keyDefinition.id
          : '${keyDefinition.id} · ${keyDefinition.pitch}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2.4 : 1.2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: selected ? 0.12 : 0.05),
                  blurRadius: selected ? 18 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildLabel(foreground),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(Color foreground) {
    final pitch = keyDefinition.pitch;
    if (!config.showLabels || pitch == null) {
      return Text(
        keyDefinition.id,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    if (config.labelMode == LayoutLabelMode.numbered) {
      final label = LayoutKeyLabelFormatter.describeNumbered(pitch);
      return _NumberedPitchLabelView(
        label: label,
        color: foreground,
      );
    }

    return Text(
      LayoutKeyLabelFormatter.format(
        pitch: pitch,
        mode: config.labelMode,
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _NumberedPitchLabelView extends StatelessWidget {
  const _NumberedPitchLabelView({
    required this.label,
    required this.color,
  });

  final NumberedPitchLabel label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const dot = '•';
    return DefaultTextStyle(
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 10,
            child: Center(
              child: Text(
                label.upperDotCount > 0
                    ? List<String>.filled(label.upperDotCount, dot).join(' ')
                    : '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          Text(
            label.baseLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          SizedBox(
            height: 10,
            child: Center(
              child: Text(
                label.lowerDotCount > 0
                    ? List<String>.filled(label.lowerDotCount, dot).join(' ')
                    : '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardGuidesPainter extends CustomPainter {
  const _BoardGuidesPainter({required this.rowCount});

  final int rowCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x12000000)
      ..strokeWidth = 1;
    final safeRowCount = math.max(rowCount, 1);
    for (var index = 1; index < safeRowCount; index++) {
      final y = size.height * index / safeRowCount;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardGuidesPainter oldDelegate) {
    return rowCount != oldDelegate.rowCount;
  }
}

class _LayoutPreviewMetrics {
  const _LayoutPreviewMetrics({
    required this.columnCount,
    required this.rowCount,
  });

  final int columnCount;
  final int rowCount;

  double get estimatedHeight => (rowCount * 88.0).clamp(220.0, 420.0);

  double keySizeFor({
    required double width,
    required double height,
  }) {
    final widthBased = width / (columnCount + 1) * 0.68;
    final heightBased = height / (rowCount + 1) * 0.72;
    return math.min(widthBased, heightBased).clamp(16.0, 52.0);
  }

  static _LayoutPreviewMetrics fromKeys(List<KeyDefinition> keys) {
    return _LayoutPreviewMetrics(
      columnCount: _clusterCount(keys.map((key) => key.normX)),
      rowCount: _clusterCount(keys.map((key) => key.normY)),
    );
  }

  static int _clusterCount(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return 1;
    }
    var count = 1;
    var anchor = sorted.first;
    for (final value in sorted.skip(1)) {
      if ((value - anchor).abs() > 0.035) {
        count += 1;
        anchor = value;
      }
    }
    return count;
  }
}
