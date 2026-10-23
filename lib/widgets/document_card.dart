import 'package:flutter/material.dart';
import 'package:yangi_alifbo/document.dart';

/// One document and where it is: waiting, converting, saved or not converted, with a button to show it in the file
/// manager, or to share it on a phone, once it is saved.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    this.onAction,
    this.actionLabel = 'Show in folder',
    this.actionIcon = Icons.folder_open_rounded,
  });

  final Document document;

  /// Shows the saved document in the file manager, or shares it; no button when null.
  final VoidCallback? onAction;
  final String actionLabel;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (Color tint, Color ink) = switch (document.status) {
      DocumentStatus.waiting => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
      DocumentStatus.converting => (colors.tertiaryContainer, colors.onTertiaryContainer),
      DocumentStatus.saved => (colors.primaryContainer, colors.onPrimaryContainer),
      DocumentStatus.failed => (colors.errorContainer, colors.onErrorContainer),
    };
    final badge = switch (document.status) {
      DocumentStatus.waiting => Icon(Icons.schedule_rounded, color: ink, size: 22),
      DocumentStatus.converting => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: ink),
      ),
      DocumentStatus.saved => Icon(Icons.check_rounded, color: ink, size: 24),
      DocumentStatus.failed => Icon(Icons.priority_high_rounded, color: ink, size: 22),
    };
    return _FadeIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: badge),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        document.status == DocumentStatus.converting ? 'Converting…' : document.outcome,
                        if (document.finishedAt case final at?) _when(at),
                      ].join('  ·  '),
                      style: text.bodySmall?.copyWith(
                        color: document.status == DocumentStatus.failed ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(tooltip: actionLabel, onPressed: onAction, icon: Icon(actionIcon, size: 20)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 14:02 for today, 23.10 14:02 for earlier this year, 23.10.2025 14:02 before that.
String _when(DateTime at) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  if (at.year == now.year && at.month == now.month && at.day == now.day) return time;
  final day = '${two(at.day)}.${two(at.month)}';
  return at.year == now.year ? '$day $time' : '$day.${at.year} $time';
}

// Fades and slides a card in the first time it is built.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, shown, child) => Opacity(
        opacity: shown,
        child: Transform.translate(offset: Offset(0, 8 * (1 - shown)), child: child),
      ),
      child: child,
    );
  }
}
