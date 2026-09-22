import 'package:flutter/material.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// A month grid: six weeks starting on the locale's (or the user's chosen)
/// first weekday, each day showing how many meetings it holds.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.countOn,
    required this.onSelect,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  /// First day of the displayed month.
  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final int Function(DateTime day) countOn;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// The 42 days a six-week grid for [month] shows, starting on weekday
  /// index [firstDayOfWeekIndex] (0 = Sunday, as [MaterialLocalizations]).
  static List<DateTime> gridDays(DateTime month, int firstDayOfWeekIndex) {
    final first = DateTime(month.year, month.month);
    // DateTime.weekday: Monday = 1 … Sunday = 7; convert to 0 = Sunday.
    final offset = (first.weekday % 7 - firstDayOfWeekIndex + 7) % 7;
    return [
      for (var i = 0; i < 42; i++)
        DateTime(first.year, first.month, first.day - offset + i),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ml = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final firstIndex = ml.firstDayOfWeekIndex;
    final days = gridDays(month, firstIndex);
    final weekdayNames = [
      for (var i = 0; i < 7; i++) ml.narrowWeekdays[(firstIndex + i) % 7],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: t.meetingsPrevMonth,
              onPressed: onPrevious,
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: t.meetingsNextMonth,
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final name in weekdayNames)
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: _DayCell(
                    day: days[week * 7 + d],
                    inMonth: days[week * 7 + d].month == month.month,
                    selected: _sameDay(days[week * 7 + d], selectedDay),
                    isToday: _sameDay(days[week * 7 + d], today),
                    count: countOn(days[week * 7 + d]),
                    onTap: () => onSelect(days[week * 7 + d]),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.isToday,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool isToday;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = selected
        ? scheme.onPrimary
        : inMonth
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.6);
    final label =
        '${MaterialLocalizations.of(context).formatFullDate(day)}'
        '${count > 0 ? ', ${t.meetingsCountOnDay(count)}' : ''}';
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected ? scheme.primary : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isToday && !selected
                ? BorderSide(color: scheme.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: text.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: isToday ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 14,
                    child: count == 0
                        ? null
                        : _CountMarker(count: count, selected: selected),
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

/// Up to three dots, or a small number from four meetings on.
class _CountMarker extends StatelessWidget {
  const _CountMarker({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onPrimary : scheme.primary;
    if (count > 3) {
      return Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
