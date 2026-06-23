import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Time-tracking panel shown on the task detail screen: the user's logged time
/// on this task, the task total (when permitted), and a quick "log time"
/// action that posts against this task.
class LogTimeSection extends StatefulWidget {
  const LogTimeSection({
    required this.projectId,
    required this.issueId,
    super.key,
  });
  final String projectId;
  final String issueId;

  @override
  State<LogTimeSection> createState() => _LogTimeSectionState();
}

class _LogTimeSectionState extends State<LogTimeSection> {
  IssueTimeSummary? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final res = await getIt<TimesheetRepository>().issueTime(
      widget.projectId,
      widget.issueId,
    );
    if (!mounted) return;
    setState(() {
      _data = res.valueOrNull;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = _data;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text(
                  t.ttTimeTracking,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t.ttLogTime),
                  onPressed: _openLog,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (data == null)
              Text(t.ttActionFailed)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _stat(context, t.ttMyTime, fmtMins(data.myMinutes)),
                  ),
                  if (data.canSeeAll)
                    Expanded(
                      child: _stat(
                        context,
                        t.ttTaskTotal,
                        fmtMins(data.totalMinutes),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );

  Future<void> _openLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickLogDialog(issueId: widget.issueId),
    );
    if (ok ?? false) await _load();
  }
}

class _QuickLogDialog extends StatefulWidget {
  const _QuickLogDialog({required this.issueId});
  final String issueId;

  @override
  State<_QuickLogDialog> createState() => _QuickLogDialogState();
}

class _QuickLogDialogState extends State<_QuickLogDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.ttLogTime),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: t.ttDate),
                child: Text(isoFrom(_date)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hours,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: t.ttHours),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: t.ttNote),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(t.ttSave)),
      ],
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final h = double.tryParse(_hours.text.replaceAll(',', '.'));
    if (h == null || h <= 0) {
      setState(() => _error = t.ttInvalidHours);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await getIt<TimesheetRepository>().logTime(
      issueId: widget.issueId,
      date: isoFrom(_date),
      minutes: (h * 60).round().clamp(1, 1440),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    if (res.isErr) {
      setState(() {
        _busy = false;
        _error = t.ttActionFailed;
      });
      return;
    }
    Navigator.pop(context, true);
  }
}
