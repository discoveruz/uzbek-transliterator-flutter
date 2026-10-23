import 'dart:ui';

import 'package:flutter/material.dart';

/// The place to drop Word documents on, with a button to choose them instead. It lights up while something is dragged
/// over the window, and is smaller once there are documents to show below it.
class DropZone extends StatelessWidget {
  const DropZone({
    super.key,
    required this.dragging,
    required this.canDrop,
    required this.compact,
    required this.saveTo,
    required this.onChoose,
  });

  final bool dragging;

  /// Whether this platform can take dropped files; iOS cannot.
  final bool canDrop;
  final bool compact;

  /// The folder the documents are saved in, as people read it.
  final String? saveTo;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = dragging ? colors.primary : colors.outlineVariant;
    return AnimatedScale(
      scale: dragging ? 1.02 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: CustomPaint(
        foregroundPainter: _DashedBorder(color: accent, width: dragging ? 2.5 : 1.5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: compact ? 190 : 340,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            color: dragging ? colors.primaryContainer.withValues(alpha: 0.55) : colors.surfaceContainerLow,
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: compact ? 52 : 76,
                    height: compact ? 52 : 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dragging ? colors.primary : colors.primaryContainer,
                    ),
                    child: Icon(
                      dragging ? Icons.file_download_outlined : Icons.upload_file_rounded,
                      size: compact ? 26 : 36,
                      color: dragging ? colors.onPrimary : colors.onPrimaryContainer,
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 20),
                  Text(
                    dragging
                        ? 'Drop to convert'
                        : canDrop
                        ? 'Drop Word documents here'
                        : 'Choose Word documents',
                    style: (compact ? text.titleMedium : text.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    Text(
                      'As many as you like. Each one is saved in the new alphabet${saveTo == null ? '' : ' to $saveTo'}.',
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  SizedBox(height: compact ? 12 : 24),
                  FilledButton.icon(
                    onPressed: onChoose,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Choose files'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _radius = 24.0;

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final inset = width / 2;
    final border = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, size.width - width, size.height - width),
          const Radius.circular(_radius),
        ),
      );
    const dash = 10.0, gap = 7.0;
    for (final PathMetric metric in border.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += dash + gap) {
        canvas.drawPath(metric.extractPath(start, start + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.width != width;
}
