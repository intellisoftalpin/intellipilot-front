import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/cubits/timesheet_cubit.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/team_month_grid.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_dialogs.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// Global personal timesheet: month navigation, completeness summary, vacation
/// balance, the day-by-day entry list, plus log-time / book-absence / export.
class TimesheetPage extends StatefulWidget {
  const TimesheetPage({super.key});

  @override
  State<TimesheetPage> createState() => _TimesheetPageState();
}

class _TimesheetPageState extends State<TimesheetPage> {
  bool _superadmin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final res = await getIt<ProfileRepository>().getProfile();
    final profile = res.valueOrNull;
    if (!mounted || profile == null) return;
    setState(() => _superadmin = profile.isSuperadmin);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return BlocProvider(
      create: (_) {
        final cubit = TimesheetCubit(
          repo: getIt<TimesheetRepository>(),
          year: now.year,
          month: now.month,
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: _TimesheetView(isSuperadmin: _superadmin),
    );
  }
}

class _TimesheetView extends StatefulWidget {
  const _TimesheetView({required this.isSuperadmin});
  final bool isSuperadmin;

  @override
  State<_TimesheetView> createState() => _TimesheetViewState();
}

class _TimesheetViewState extends State<_TimesheetView> {
  bool _global = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppScaffold(
      title: Text(_global ? t.ttAllUsers : t.ttMyTimesheet),
      maxContentWidth: _global ? 1400 : 900,
      actions: [
        if (widget.isSuperadmin)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.ttAllUsers),
                Switch(
                  value: _global,
                  onChanged: (v) => setState(() => _global = v),
                ),
              ],
            ),
          ),
        if (!_global)
          BlocBuilder<TimesheetCubit, TimesheetState>(
            builder: (context, state) => PopupMenuButton<ExportFormat>(
              icon: const Icon(Icons.download_outlined),
              tooltip: t.ttExport,
              enabled: state is TimesheetLoaded,
              onSelected: (fmt) => _export(context, fmt),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: ExportFormat.csv,
                  child: Text(t.ttExportCsv),
                ),
                PopupMenuItem(
                  value: ExportFormat.xlsx,
                  child: Text(t.ttExportXlsx),
                ),
              ],
            ),
          ),
      ],
      body: _global
          ? const _GlobalTimesheetView()
          : BlocBuilder<TimesheetCubit, TimesheetState>(
              builder: (context, state) {
                if (state is TimesheetLoading) return const LoadingIndicator();
                if (state is TimesheetFailed) {
                  return ErrorView(
                    failure: state.failure,
                    onRetry: () => context.read<TimesheetCubit>().load(),
                  );
                }
                state as TimesheetLoaded;
                return _LoadedBody(state: state);
              },
            ),
    );
  }

  Future<void> _export(BuildContext context, ExportFormat fmt) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<TimesheetCubit>().state;
    if (state is! TimesheetLoaded) return;
    final from = isoDate(state.year, state.month, 1);
    final to = isoDate(
      state.year,
      state.month,
      lastDay(state.year, state.month),
    );
    final res = await getIt<TimesheetRepository>().exportMy(
      from: from,
      to: to,
      format: fmt,
    );
    final bytes = res.valueOrNull;
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttExportFailed)));
      return;
    }
    final mime = fmt == ExportFormat.csv
        ? 'text/csv'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final ok = await getIt<FileDownloader>().downloadBytes(
      filename: 'timesheet-${state.year}-${state.month}.${fmt.name}',
      mimeType: mime,
      bytes: bytes,
    );
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttExportUnsupported)));
    }
  }
}

/// Superadmin cross-project month grid (every user, every project).
class _GlobalTimesheetView extends StatefulWidget {
  const _GlobalTimesheetView();

  @override
  State<_GlobalTimesheetView> createState() => _GlobalTimesheetViewState();
}

class _GlobalTimesheetViewState extends State<_GlobalTimesheetView> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<TeamMemberMonth>? _members;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await getIt<TimesheetRepository>().adminGlobalMonth(
      year: _year,
      month: _month,
    );
    if (!mounted) return;
    setState(() {
      _members = res.valueOrNull ?? const [];
      _loading = false;
    });
  }

  Future<void> _changeMonth(int delta) async {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final monthLabel = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime(_year, _month));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _changeMonth(-1),
              ),
              Text(monthLabel, style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const LoadingIndicator()
              : (_members == null || _members!.isEmpty)
              ? Center(child: Text(t.ttNoTeamData))
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: TeamMonthGrid(
                    members: _members!,
                    year: _year,
                    month: _month,
                  ),
                ),
        ),
      ],
    );
  }
}

class _LoadedBody extends StatefulWidget {
  const _LoadedBody({required this.state});
  final TimesheetLoaded state;

  @override
  State<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends State<_LoadedBody> {
  String? _selected;

  TimesheetLoaded get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cubit = context.read<TimesheetCubit>();
    final monthLabel = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime(state.year, state.month));
    final byDate = state.byDate;

    // Default the selected day to today (when in this month) so its entries
    // show immediately; otherwise none is selected.
    final today = DateTime.now();
    final selected =
        _selected ??
        ((today.year == state.year && today.month == state.month)
            ? isoFrom(today)
            : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => cubit.changeMonth(-1),
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => cubit.changeMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SummaryCard(summary: state.summary),
        const SizedBox(height: 8),
        _BalanceCard(balance: state.balance),
        const SizedBox(height: 12),
        _MonthCalendar(
          year: state.year,
          month: state.month,
          byDate: byDate,
          targetMinutes: state.summary.workMinutesPerDay,
          missingDays: state.summary.missingDays.toSet(),
          selected: selected,
          onSelect: (d) => setState(() => _selected = d),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(t.ttLogTime),
                onPressed: state.busy
                    ? null
                    : () => _openLog(context, cubit, selected),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.beach_access_outlined),
                label: Text(t.ttBookAbsence),
                onPressed: state.busy
                    ? null
                    : () => _openAbsence(context, cubit),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (selected != null && (byDate[selected]?.isNotEmpty ?? false))
          _DaySection(
            date: selected,
            entries: byDate[selected]!,
            cubit: cubit,
          )
        else
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(t.ttNoEntries)),
          ),
      ],
    );
  }

  Future<void> _openLog(
    BuildContext context,
    TimesheetCubit cubit,
    String? day,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LogTimeDialog(
        onSubmit: cubit.logTime,
        initialDate: day == null ? null : DateTime.tryParse(day),
      ),
    );
  }

  Future<void> _openAbsence(BuildContext context, TimesheetCubit cubit) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BookAbsenceDialog(cubit: cubit),
    );
  }
}

/// A month grid: each in-month day shows logged hours or an absence marker;
/// complete days are tinted, missing working days are outlined, today is
/// ringed, and the selected day is highlighted. Tapping a day selects it.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.year,
    required this.month,
    required this.byDate,
    required this.targetMinutes,
    required this.missingDays,
    required this.selected,
    required this.onSelect,
  });

  final int year;
  final int month;
  final Map<String, List<TimeEntry>> byDate;
  final int targetMinutes;
  final Set<String> missingDays;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Weekday headers Mon..Sun (2024-01-01 was a Monday).
    final dow = DateFormat.E(locale);
    final headers = [
      for (var i = 0; i < 7; i++) dow.format(DateTime(2024, 1, 1 + i)),
    ];

    final first = DateTime(year, month);
    final lead = first.weekday - 1; // Mon=1 → 0 leading blanks
    final days = lastDay(year, month);
    final todayIso = isoFrom(DateTime.now());

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= days; d++) {
      final iso = isoDate(year, month, d);
      final entries = byDate[iso] ?? const <TimeEntry>[];
      final work = entries
          .where((e) => e.kind == EntryKind.work)
          .fold<int>(0, (s, e) => s + e.minutes);
      final absence = entries
          .where((e) => e.kind != EntryKind.work)
          .map((e) => e.kind)
          .firstOrNull;
      cells.add(
        _DayCell(
          day: d,
          workMinutes: work,
          absence: absence,
          target: targetMinutes,
          isMissing: missingDays.contains(iso),
          isToday: iso == todayIso,
          isSelected: iso == selected,
          onTap: () => onSelect(iso),
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 7; j++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: cells[i + j],
                ),
              ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                for (final h in headers)
                  Expanded(
                    child: Center(
                      child: Text(
                        h,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.workMinutes,
    required this.absence,
    required this.target,
    required this.isMissing,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final int day;
  final int workMinutes;
  final EntryKind? absence;
  final int target;
  final bool isMissing;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = workMinutes >= target && target > 0;
    Color? bg;
    if (isSelected) {
      bg = theme.colorScheme.primaryContainer;
    } else if (absence != null) {
      bg = theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5);
    } else if (complete) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.12);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday
                ? theme.colorScheme.primary
                : (isMissing
                      ? theme.colorScheme.error.withValues(alpha: 0.6)
                      : theme.colorScheme.outlineVariant),
            width: isToday ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$day', style: theme.textTheme.labelSmall),
            const Spacer(),
            if (absence != null)
              Center(child: Icon(kindIcon(absence!), size: 16))
            else if (workMinutes > 0)
              Center(
                child: Text(
                  fmtMins(workMinutes),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: complete
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final TimesheetSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ok = !summary.hasGaps;
    final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          color: color,
        ),
        title: Text(ok ? t.ttComplete : t.ttMissingTitle),
        subtitle: Text(
          ok
              ? t.ttLoggedOf(
                  fmtMins(summary.loggedMinutes),
                  fmtMins(summary.requiredMinutes),
                )
              : t.ttMissingBody(summary.missingDays.length),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});
  final VacationBalance balance;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (balance.years.isEmpty) return const SizedBox.shrink();
    final y = balance.years.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.ttVacationBalance} · ${y.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _stat(context, t.ttRemaining, y.remainingDays),
                _stat(context, t.ttUsed, y.usedDays),
                _stat(context, t.ttAllowance, y.allowanceDays),
                _stat(context, t.ttCarriedOver, y.carriedOverDays),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(
        value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ],
  );
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.date,
    required this.entries,
    required this.cubit,
  });
  final String date;
  final List<TimeEntry> entries;
  final TimesheetCubit cubit;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (s, e) => s + e.minutes);
    return Card(
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(date, style: Theme.of(context).textTheme.titleSmall),
            trailing: Text(
              fmtMins(total),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          for (final e in entries)
            ListTile(
              leading: Icon(kindIcon(e.kind)),
              title: Text(e.label),
              subtitle: e.note.isEmpty ? null : Text(e.note),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmtMins(e.minutes)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _edit(context, e),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _delete(context, e),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, TimeEntry e) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EditEntryDialog(cubit: cubit, entry: e),
    );
  }

  Future<void> _delete(BuildContext context, TimeEntry e) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (e.bookingId != null) {
      // Single-day delete still works; booking-wide cancel is from the entry.
    }
    final fail = await cubit.deleteEntry(e.id);
    if (fail != null) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
    }
  }
}
