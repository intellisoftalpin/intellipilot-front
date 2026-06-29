import 'package:flutter/material.dart';
import 'package:intellipilot/app/theme/app_theme.dart';

/// Human-readable issue key `<PREFIX>-<ref>` (e.g. `PS-12`). Falls back to
/// `#<ref>` before the project prefix is known.
String issueKeyLabel(String prefix, int reference) =>
    prefix.isEmpty ? '#$reference' : '$prefix-$reference';

/// Human-readable epic key `<PREFIX>-E-<ref>` (e.g. `PS-E-3`). Falls back to
/// `EPIC-<ref>` before the project prefix is known.
String epicKeyLabel(String prefix, int reference) =>
    prefix.isEmpty ? 'EPIC-$reference' : '$prefix-E-$reference';

/// Jira-style monospaced key chip: `PS-12`, `PS-E-3`, `ISSUE-2`.
/// Renders as outlined pill with the project's neutral surface tone — meant
/// to be paired with the entity subject as a quiet identifier prefix.
class IssueKeyChip extends StatelessWidget {
  const IssueKeyChip({required this.text, this.padded = true, super.key});

  final String text;

  /// When false, pads tighter — useful in dense table rows.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padded
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        style: AppTheme.mono(context, size: 11).copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Jira-style status pill: tinted background + colored bullet + uppercase
/// label. Falls back to a neutral chip when the taxonomy item has no
/// recognisable color.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.colorHex,
    this.dense = false,
    super.key,
  });

  final String label;
  final String colorHex;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = _parseHex(colorHex) ?? Theme.of(context).colorScheme.outline;
    final theme = Theme.of(context);
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 6 : 8,
            height: dense ? 6 : 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          SizedBox(width: dense ? 6 : 8),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

Color? _parseHex(String hex) {
  var t = hex.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 6) t = 'ff$t';
  if (t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(v);
}
