import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Dashboard banner warning the user about unfilled working days this month.
/// Renders nothing while loading, on error, or when the month is complete.
class TimesheetWarningCard extends StatefulWidget {
  const TimesheetWarningCard({super.key});

  @override
  State<TimesheetWarningCard> createState() => _TimesheetWarningCardState();
}

class _TimesheetWarningCardState extends State<TimesheetWarningCard> {
  TimesheetSummary? _summary;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    // Best-effort dashboard card: never let a failed/absent endpoint crash the
    // page that embeds it.
    try {
      final res = await getIt<TimesheetRepository>().mySummary(
        year: now.year,
        month: now.month,
      );
      if (!mounted) return;
      setState(() => _summary = res.valueOrNull);
    } on Object {
      // Ignore — the card simply renders nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (s == null || !s.hasGaps) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
        title: Text(
          t.ttMissingTitle,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        subtitle: Text(
          t.ttMissingBody(s.missingDays.length),
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        trailing: TextButton(
          onPressed: () => context.push(Routes.timesheet),
          child: Text(t.ttOpenTimesheet),
        ),
      ),
    );
  }
}
