import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/cubits/timesheet_cubit.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_dialogs.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// Global personal timesheet: month navigation, completeness summary, vacation
/// balance, the day-by-day entry list, plus log-time / book-absence / export.
class TimesheetPage extends StatelessWidget {
  const TimesheetPage({super.key});

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
      child: const _TimesheetView(),
    );
  }
}

class _TimesheetView extends StatelessWidget {
  const _TimesheetView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppScaffold(
      title: Text(t.ttMyTimesheet),
      maxContentWidth: 900,
      actions: [
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
      body: BlocBuilder<TimesheetCubit, TimesheetState>(
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

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.state});
  final TimesheetLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cubit = context.read<TimesheetCubit>();
    final monthLabel = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime(state.year, state.month));
    final byDate = state.byDate;
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

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
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(t.ttLogTime),
                onPressed: state.busy ? null : () => _openLog(context, cubit),
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
        if (dates.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(t.ttNoEntries)),
          )
        else
          for (final d in dates)
            _DaySection(date: d, entries: byDate[d]!, cubit: cubit),
      ],
    );
  }

  Future<void> _openLog(BuildContext context, TimesheetCubit cubit) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LogTimeDialog(cubit: cubit),
    );
  }

  Future<void> _openAbsence(BuildContext context, TimesheetCubit cubit) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BookAbsenceDialog(cubit: cubit),
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
