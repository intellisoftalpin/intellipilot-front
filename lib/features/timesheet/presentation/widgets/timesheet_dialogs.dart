import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/cubits/timesheet_cubit.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Submit signature for [LogTimeDialog]. Matches `TimesheetCubit.logTime` so
/// the personal timesheet can pass its cubit method directly, while the
/// project view supplies a repository-backed closure. Returns a failure (or
/// null on success).
typedef LogTimeSubmit =
    Future<AppFailure?> Function({
      required String date,
      required int minutes,
      EntryKind kind,
      String? issueId,
      String? projectId,
      String? meetingType,
      String? note,
    });

int? _minutesFromHours(String raw) {
  final h = double.tryParse(raw.replaceAll(',', '.'));
  if (h == null || h <= 0) return null;
  final m = (h * 60).round();
  return m.clamp(1, 1440);
}

/// Log worked time (against a task or a project) or a meeting. Decoupled from
/// any cubit: the caller passes [onSubmit] — the personal timesheet forwards
/// `TimesheetCubit.logTime`, the project view a repository closure.
class LogTimeDialog extends StatefulWidget {
  const LogTimeDialog({
    required this.onSubmit,
    this.initialDate,
    this.scopedProjectId,
    this.scopedProjectName,
    super.key,
  });

  final LogTimeSubmit onSubmit;
  final DateTime? initialDate;

  /// When set, the dialog is locked to this project (project time page):
  /// work entries attach to it and the project picker is hidden.
  final String? scopedProjectId;
  final String? scopedProjectName;

  @override
  State<LogTimeDialog> createState() => _LogTimeDialogState();
}

class _LogTimeDialogState extends State<LogTimeDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();
  final _search = TextEditingController();
  late DateTime _date = widget.initialDate ?? DateTime.now();

  EntryKind _mode = EntryKind.work;
  AssignedTask? _task;
  String? _projectId;
  MeetingType? _meetingType;

  List<Project> _projects = const [];
  List<AssignedTask> _results = const [];
  Timer? _debounce;
  bool _searching = false;
  String? _error;
  bool _busy = false;

  bool get _scoped => widget.scopedProjectId != null;

  @override
  void initState() {
    super.initState();
    _projectId = widget.scopedProjectId;
    unawaited(_loadProjects());
    unawaited(_runSearch(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hours.dispose();
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final res = await getIt<ProjectsRepository>().listProjects();
    if (!mounted) return;
    setState(() => _projects = res.valueOrNull ?? const []);
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_runSearch(q)),
    );
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final res = await getIt<TimesheetRepository>().searchLoggableIssues(
      q.trim().isEmpty ? null : q.trim(),
      projectId: widget.scopedProjectId,
    );
    if (!mounted) return;
    setState(() {
      _results = res.valueOrNull ?? const [];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.ttLogTime),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<EntryKind>(
                segments: [
                  ButtonSegment(
                    value: EntryKind.work,
                    icon: const Icon(Icons.work_outline, size: 18),
                    label: Text(t.ttModeWork),
                  ),
                  ButtonSegment(
                    value: EntryKind.meeting,
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: Text(t.ttModeMeeting),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == EntryKind.work)
                ..._workFields(t)
              else
                ..._meetingFields(t),
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
                decoration: InputDecoration(
                  labelText: _noteRequired ? t.ttNoteRequired : t.ttNote,
                ),
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

  /// A work entry with no task requires a note (backend rule).
  bool get _noteRequired => _mode == EntryKind.work && _task == null;

  List<Widget> _workFields(AppLocalizations t) {
    if (_task != null) {
      final task = _task!;
      return [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(
              task.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${task.projectName} · #${task.reference}'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.ttNoTask,
              onPressed: () => setState(() => _task = null),
            ),
          ),
        ),
      ];
    }
    return [
      TextField(
        controller: _search,
        decoration: InputDecoration(
          labelText: t.ttSearchTask,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        onChanged: _onSearchChanged,
      ),
      const SizedBox(height: 4),
      if (_results.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final task in _results)
                  ListTile(
                    dense: true,
                    title: Text(
                      task.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${task.projectName} · #${task.reference}'),
                    onTap: () => setState(() {
                      _task = task;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ),
        )
      else if (!_searching)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            t.ttNoTasksFound,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      // No-task entries need a project (unless already scoped to one).
      if (!_scoped) ...[
        const SizedBox(height: 8),
        _projectPicker(t, label: t.ttProjectForNoTask),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${t.ttProject}: ${widget.scopedProjectName ?? ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }

  List<Widget> _meetingFields(AppLocalizations t) {
    return [
      DropdownButtonFormField<MeetingType?>(
        initialValue: _meetingType,
        isExpanded: true,
        decoration: InputDecoration(labelText: t.ttMeetingType),
        items: [
          DropdownMenuItem(value: null, child: Text(t.ttMeetingUnset)),
          for (final m in MeetingType.values)
            DropdownMenuItem(value: m, child: Text(meetingTypeLabel(t, m))),
        ],
        onChanged: (v) => setState(() => _meetingType = v),
      ),
      const SizedBox(height: 8),
      if (!_scoped)
        _projectPicker(t, label: t.ttProjectOptional)
      else
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${t.ttProject}: ${widget.scopedProjectName ?? ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }

  Widget _projectPicker(AppLocalizations t, {required String label}) {
    return DropdownButtonFormField<String?>(
      initialValue: _projectId,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: null, child: Text(t.ttProjectNone)),
        for (final p in _projects)
          DropdownMenuItem(value: p.id, child: Text(p.name)),
      ],
      onChanged: (v) => setState(() {
        _projectId = v;
        _error = null;
      }),
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final minutes = _minutesFromHours(_hours.text);
    final note = _note.text.trim();
    final effectiveProject = widget.scopedProjectId ?? _projectId;

    if (_mode == EntryKind.work && _task == null && effectiveProject == null) {
      setState(() => _error = t.ttNeedTaskOrProject);
      return;
    }
    if (_noteRequired && note.isEmpty) {
      setState(() => _error = t.ttNoteRequiredError);
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
    final fail = await widget.onSubmit(
      kind: _mode,
      issueId: _mode == EntryKind.work ? _task?.id : null,
      projectId: _task != null ? null : effectiveProject,
      meetingType: _mode == EntryKind.meeting ? _meetingType?.wire : null,
      date: isoFrom(_date),
      minutes: minutes,
      note: note.isEmpty ? null : note,
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
/// Submit signature for [EditEntryDialog]. The personal timesheet forwards
/// `TimesheetCubit.editEntry`; the team view supplies a `correctEntry` closure.
/// Returns a failure (or null on success).
typedef EditEntrySubmit =
    Future<AppFailure?> Function({
      required int minutes,
      required int version,
      String? note,
    });

/// Edit an existing entry's hours + note. A read-only header shows the linked
/// task (work) or the meeting type so the editor sees what they are changing.
/// Reused for both self-editing and manager corrections via [onSubmit].
class EditEntryDialog extends StatefulWidget {
  const EditEntryDialog({
    required this.entry,
    required this.onSubmit,
    super.key,
  });
  final TimeEntry entry;
  final EditEntrySubmit onSubmit;

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
            _EntryContextHeader(entry: widget.entry),
            const SizedBox(height: 12),
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
    final fail = await widget.onSubmit(
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

/// Read-only context line at the top of [EditEntryDialog]: the linked task
/// (work), the meeting type (meeting), or the leave kind (absence).
class _EntryContextHeader extends StatelessWidget {
  const _EntryContextHeader({required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isWork = entry.kind == EntryKind.work;
    final primary = entry.kind.isAbsence
        ? kindLabel(t, entry.kind)
        : entry.label;

    String? secondary;
    if (isWork) {
      secondary = entry.projectName;
    } else if (entry.kind == EntryKind.meeting) {
      final mt = MeetingType.fromWire(entry.meetingType);
      secondary = mt != null ? meetingTypeLabel(t, mt) : null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            kindIcon(entry.kind),
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isWork && entry.issueRef != null
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
                if (secondary != null && secondary.isNotEmpty)
                  Text(
                    secondary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
