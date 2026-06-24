import 'package:flutter/material.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';

/// Fallback palette for taxonomy items that have no stored color.
const List<Color> _palette = [
  Color(0xFF1565C0),
  Color(0xFF6A1B9A),
  Color(0xFF2E7D32),
  Color(0xFFAD1457),
  Color(0xFFEF6C00),
  Color(0xFF00838F),
  Color(0xFF4527A0),
  Color(0xFFC62828),
  Color(0xFF558B2F),
  Color(0xFF00695C),
];

/// Parse a `#rrggbb` / `rrggbb` / `aarrggbb` hex string, else [fallback].
Color dashboardColor(String hex, Color fallback) {
  var t = hex.trim();
  if (t.isEmpty) return fallback;
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 6) t = 'ff$t';
  if (t.length != 8) return fallback;
  final v = int.tryParse(t, radix: 16);
  return v == null ? fallback : Color(v);
}

Color _bucketColor(String hex, int index) =>
    dashboardColor(hex, _palette[index % _palette.length]);

/// A compact metric card: icon, big value, label. Fixed width so several
/// tiles flow nicely in a [Wrap].
class KpiTile extends StatelessWidget {
  const KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.primary;
    return SizedBox(
      width: 156,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const Spacer(),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card wrapper with a titled header used for every dashboard panel.
class DashboardSection extends StatelessWidget {
  const DashboardSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A segmented horizontal bar of status counts plus a legend.
class StatusBarChart extends StatelessWidget {
  const StatusBarChart({
    required this.buckets,
    required this.emptyLabel,
    super.key,
  });

  final List<StatusBucket> buckets;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = buckets.where((b) => b.count > 0).toList();
    final total = shown.fold<int>(0, (a, b) => a + b.count);
    if (total == 0) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Expanded(
                    flex: shown[i].count,
                    child: ColoredBox(
                      color: _bucketColor(shown[i].color, i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (var i = 0; i < shown.length; i++)
              _LegendDot(
                color: _bucketColor(shown[i].color, i),
                label: shown[i].name,
                count: shown[i].count,
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label  $count', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Per-item proportional bars for an issue-type / priority breakdown.
class BreakdownList extends StatelessWidget {
  const BreakdownList({
    required this.items,
    required this.emptyLabel,
    super.key,
  });

  final List<NamedCount> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = items.where((b) => b.count > 0).toList();
    if (shown.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final max = shown.fold<int>(1, (a, b) => b.count > a ? b.count : a);
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    shown[i].name,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: shown[i].count / max,
                      minHeight: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _bucketColor(shown[i].color, i),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${shown[i].count}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single epic's readiness as a labelled progress bar.
class EpicProgressTile extends StatelessWidget {
  const EpicProgressTile({required this.epic, super.key});

  final EpicReadiness epic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dashboardColor(epic.color, theme.colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  epic.subject,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${epic.done}/${epic.total} · ${epic.percent}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: epic.percent / 100,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical bars of issues closed per week (Kanban throughput).
class ThroughputChart extends StatelessWidget {
  const ThroughputChart({required this.weeks, super.key});

  final List<WeekCount> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = weeks.fold<int>(1, (a, b) => b.closed > a ? b.closed : a);
    const barArea = 64.0;
    return SizedBox(
      height: barArea + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in weeks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${w.closed}', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Container(
                      height: w.closed == 0 ? 2 : barArea * (w.closed / max),
                      decoration: BoxDecoration(
                        color: w.closed == 0
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _weekLabel(w.weekStart),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `2026-06-22` → `06-22` (compact axis tick).
  String _weekLabel(String iso) =>
      iso.length >= 10 ? iso.substring(5) : iso;
}
