import 'package:flutter/material.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Compact members × days month grid, shared by the per-project team view and
/// the superadmin cross-project view. The member-name (+ total) column is
/// frozen on the left; the narrow day columns scroll horizontally only when a
/// month is too wide for the viewport.
class TeamMonthGrid extends StatelessWidget {
  const TeamMonthGrid({
    required this.members,
    required this.year,
    required this.month,
    this.onTapDay,
    this.excludedMembers,
    super.key,
  });

  final List<TeamMemberMonth> members;
  final int year;
  final int month;

  /// How many members the server withheld from this grid because they are
  /// excluded from timesheet reports. Rendered as a quiet footer note so a
  /// deliberately absent row doesn't read as a bug. `null` (or zero) shows
  /// nothing — the API omits the count for callers not entitled to it.
  final int? excludedMembers;

  /// When set, cells with logged time become tappable — used by managers to
  /// drill into a member's day and edit/delete their entries.
  final void Function(TeamMemberMonth member, String isoDate)? onTapDay;

  static const double _dayWidth = 30;
  static const double _rowHeight = 32;
  static const double _headHeight = 38;
  static const double _nameWidth = 176;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = [for (var d = 1; d <= lastDay(year, month); d++) d];

    final excluded = excludedMembers ?? 0;
    final grid = SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frozen member (+ total) column.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _nameWidth,
                height: _headHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: _headDecoration(theme),
                child: Text(
                  t.ttMember,
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final m in members)
                Container(
                  width: _nameWidth,
                  height: _rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: _rowDecoration(theme),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.displayName,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        fmtMins(m.totalMinutes),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // Scrollable day columns.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final d in days) _dayHead(context, d),
                    ],
                  ),
                  for (final m in members)
                    Row(
                      children: [
                        for (final d in days) _cell(context, m, d),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (excluded == 0) return grid;
    // Quiet, name-free note: tells whoever set the flag that the
    // missing row is deliberate, without exposing who is hidden.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: grid),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(
            t.ttExcludedMembers(excluded),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _headDecoration(ThemeData theme) => BoxDecoration(
    border: Border(
      bottom: BorderSide(color: theme.colorScheme.outlineVariant),
    ),
  );

  BoxDecoration _rowDecoration(ThemeData theme) => BoxDecoration(
    border: Border(
      bottom: BorderSide(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    ),
  );

  Widget _dayHead(BuildContext context, int day) {
    final theme = Theme.of(context);
    final date = DateTime(year, month, day);
    final weekend = date.weekday >= DateTime.saturday;
    return Container(
      width: _dayWidth,
      height: _headHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: weekend
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : null,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        '$day',
        style: theme.textTheme.labelSmall?.copyWith(
          color: weekend
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, TeamMemberMonth member, int day) {
    final theme = Theme.of(context);
    final iso = isoDate(year, month, day);
    final minutes = member.days[iso] ?? 0;
    if (minutes == 0) {
      return SizedBox(
        width: _dayWidth,
        height: _rowHeight,
        child: Center(
          child: Text(
            '·',
            style: TextStyle(color: theme.colorScheme.outlineVariant),
          ),
        ),
      );
    }
    final hours = minutes / 60;
    // Light heatmap: deeper as the day fills toward 8h.
    final alpha = (hours / 8).clamp(0.0, 1.0) * 0.5;
    final cell = Container(
      width: _dayWidth,
      height: _rowHeight,
      alignment: Alignment.center,
      color: theme.colorScheme.primary.withValues(alpha: alpha),
      child: Text(
        hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1),
        style: theme.textTheme.labelSmall,
      ),
    );
    if (onTapDay == null) return cell;
    return InkWell(onTap: () => onTapDay!(member, iso), child: cell);
  }
}
