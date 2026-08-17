import 'package:flutter/material.dart';

/// A circular readiness indicator with the percentage written inside it.
///
/// [value] is a fraction in `[0, 1]`, or `null` when there is nothing to
/// measure (no issues yet) — which renders a muted, empty ring and an em dash
/// rather than a misleading 0%.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    this.size = 44,
    this.completed = false,
    super.key,
  });

  final double? value;
  final double size;

  /// Tints the ring for a completed milestone, matching the muted treatment
  /// completed milestones get in the list and on the timeline.
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = value?.clamp(0.0, 1.0);
    final colour = switch (fraction) {
      null => theme.colorScheme.outlineVariant,
      _ when completed => theme.colorScheme.tertiary,
      _ => theme.colorScheme.primary,
    };
    final label = fraction == null ? '—' : '${(fraction * 100).round()}%';
    return Semantics(
      label: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fraction ?? 0,
                strokeWidth: size >= 56 ? 5 : 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colour),
              ),
            ),
            Text(
              label,
              style:
                  (size >= 56
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.labelSmall)
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
