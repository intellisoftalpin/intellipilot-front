import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/cubits/timesheet_cubit.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

int? _minutesFromHours(String raw) {
  final h = double.tryParse(raw.replaceAll(',', '.'));
  if (h == null || h <= 0) return null;
  final m = (h * 60).round();
  return m.clamp(1, 1440);
}

/// Log worked time against one of the caller's assigned tasks.
class LogTimeDialog extends StatefulWidget {
  const LogTimeDialog({required this.cubit, super.key});
  final TimesheetCubit cubit;

  @override
  State<LogTimeDialog> createState() => _LogTimeDialogState();
}

class _LogTimeDialogState extends State<LogTimeDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  AssignedTask? _task;
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
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder(
                future: getIt<TimesheetRepository>().listAssignedIssues(),
                builder: (context, snap) {
                  final tasks =
                      snap.data?.valueOrNull ?? const <AssignedTask>[];
                  if (snap.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (tasks.isEmpty) return Text(t.ttNoAssignedTasks);
                  return DropdownButtonFormField<AssignedTask>(
                    initialValue: _task,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t.ttPickTask),
                    items: [
                      for (final task in tasks)
                        DropdownMenuItem(
                          value: task,
                          child: Text(
                            task.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _task = v),
                  );
                },
              ),
              const SizedBox(height: 8),
              _DateField(
                label: t.ttDate,
                value: _date,
                onChanged: (d) => setState(() => _date = d),
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
                maxLines: 2,
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(t.ttSave)),
      ],
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final minutes = _minutesFromHours(_hours.text);
    if (_task == null) {
      setState(() => _error = t.ttSelectTaskFirst);
      return;
    }
    if (minutes == null) {
      setState(() => _error = t.ttInvalidHours);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final fail = await widget.cubit.logTime(
      issueId: _task!.id,
      date: isoFrom(_date),
      minutes: minutes,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    if (fail != null) {
      setState(() {
        _busy = false;
        _error = t.ttActionFailed;
      });
      return;
    }
    Navigator.pop(context);
  }
}

/// Edit an existing entry's hours / note.
class EditEntryDialog extends StatefulWidget {
  const EditEntryDialog({required this.cubit, required this.entry, super.key});
  final TimesheetCubit cubit;
  final TimeEntry entry;

  @override
  State<EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<EditEntryDialog> {
  late final _hours = TextEditingController(
    text: (widget.entry.minutes / 60).toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.entry.note);
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
      title: Text(t.actionEdit),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              maxLines: 2,
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(t.ttSave)),
      ],
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final minutes = _minutesFromHours(_hours.text);
    if (minutes == null) {
      setState(() => _error = t.ttInvalidHours);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final fail = await widget.cubit.editEntry(
      id: widget.entry.id,
      minutes: minutes,
      version: widget.entry.version,
      note: _note.text.trim(),
    );
    if (!mounted) return;
    if (fail != null) {
      setState(() {
        _busy = false;
        _error = t.ttActionFailed;
      });
      return;
    }
    Navigator.pop(context);
  }
}

/// Book vacation / illness / day-off / holiday over a date range.
class BookAbsenceDialog extends StatefulWidget {
  const BookAbsenceDialog({required this.cubit, super.key});
  final TimesheetCubit cubit;

  @override
  State<BookAbsenceDialog> createState() => _BookAbsenceDialogState();
}

class _BookAbsenceDialogState extends State<BookAbsenceDialog> {
  EntryKind _kind = EntryKind.vacation;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  final _hours = TextEditingController();
  final _note = TextEditingController();
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
      title: Text(t.ttBookAbsenceTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<EntryKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.ttAbsenceKind),
                items: [
                  for (final k in EntryKind.values.where((k) => k.isAbsence))
                    DropdownMenuItem(value: k, child: Text(kindLabel(t, k))),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 8),
              _DateField(
                label: t.ttStartDate,
                value: _start,
                onChanged: (d) => setState(() => _start = d),
              ),
              const SizedBox(height: 8),
              _DateField(
                label: t.ttEndDate,
                value: _end,
                onChanged: (d) => setState(() => _end = d),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hours,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: t.ttHoursPerDayOptional),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(t.ttSave)),
      ],
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (_end.isBefore(_start)) {
      setState(() => _error = t.ttEndBeforeStart);
      return;
    }
    final perDay = _hours.text.trim().isEmpty
        ? null
        : _minutesFromHours(_hours.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    final fail = await widget.cubit.bookAbsence(
      kind: _kind,
      startDate: isoFrom(_start),
      endDate: isoFrom(_end),
      minutesPerDay: perDay,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    if (fail != null) {
      setState(() {
        _busy = false;
        _error = t.ttActionFailed;
      });
      return;
    }
    Navigator.pop(context);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2015),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(isoFrom(value)),
      ),
    );
  }
}
