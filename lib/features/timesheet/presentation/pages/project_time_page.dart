import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/team_month_grid.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_dialogs.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// Per-project team timesheet (managers): a compact members × days grid for a
/// month, per-month lock/unlock, CSV/XLSX export, plus quick time logging
/// (for yourself, or — with `time.manage` — on behalf of another member).
class ProjectTimePage extends StatefulWidget {
  const ProjectTimePage({required this.projectId, super.key});
  final String projectId;

  @override
  State<ProjectTimePage> createState() => _ProjectTimePageState();
}

class _ProjectTimePageState extends State<ProjectTimePage> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<TeamMemberMonth>? _members;
  Set<int> _lockedMonths = {};
  bool _loading = true;

  // Logging context, resolved once on first load.
  String? _projectName;
  List<Membership> _projectMembers = const [];
  bool _canManage = false;
  bool _canLog = false;

  TimesheetRepository get _repo => getIt<TimesheetRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
    unawaited(_load());
  }

  Future<void> _loadContext() async {
    final projects = getIt<ProjectsRepository>();
    final profile = (await getIt<ProfileRepository>().getProfile()).valueOrNull;
    final project = (await projects.getProject(widget.projectId)).valueOrNull;
    final members =
        (await projects.listMembers(widget.projectId)).valueOrNull ??
        const <Membership>[];
    final roles =
        (await projects.listRoles(widget.projectId)).valueOrNull ??
        const <Role>[];

    var canManage = false;
    var canLog = false;
    if (profile != null) {
      Membership? mine;
      for (final m in members) {
        if (m.userId == profile.id) {
          mine = m;
          break;
        }
      }
      if (mine != null) {
        for (final r in roles) {
          if (r.id == mine.roleId) {
            canManage =
                r.isAdmin || r.permissions.contains(Permission.timeManage);
            canLog =
                r.isAdmin ||
                r.permissions.contains(Permission.timeLog) ||
                canManage;
            break;
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _projectName = project?.name;
      _projectMembers = members;
      _canManage = canManage;
      _canLog = canLog;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final team = await _repo.teamMonth(
      widget.projectId,
      year: _year,
      month: _month,
    );
    final locks = await _repo.listLocks(widget.projectId);
    if (!mounted) return;
    setState(() {
      _members = team.valueOrNull ?? const [];
      _lockedMonths = {
        for (final l in (locks.valueOrNull ?? const <PeriodLock>[]))
          if (l.year == _year) l.month,
      };
      _loading = false;
    });
  }

  bool get _isLocked => _lockedMonths.contains(_month);

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

  Future<void> _toggleLock() async {
    final res = _isLocked
        ? await _repo.unlockPeriod(widget.projectId, year: _year, month: _month)
        : await _repo.lockPeriod(widget.projectId, year: _year, month: _month);
    if (res.isOk) await _load();
  }

  /// Self-logging submit: posts to `/me/time-entries` (project pre-scoped).
  Future<AppFailure?> _selfSubmit({
    required String date,
    required int minutes,
    EntryKind kind = EntryKind.work,
    String? issueId,
    String? projectId,
    String? meetingType,
    String? note,
  }) async {
    final res = await _repo.logTime(
      kind: kind,
      issueId: issueId,
      projectId: projectId,
      meetingType: meetingType,
      date: date,
      minutes: minutes,
      note: note,
    );
    return res.failureOrNull;
  }

  Future<void> _openSelfLog() async {
    // Pre-fill the viewed month, not blindly "today": when the manager has
    // navigated to another month, that month's first day is the intent.
    final now = DateTime.now();
    final viewedMonth = (_year == now.year && _month == now.month)
        ? now
        : DateTime(_year, _month);
    await showDialog<void>(
      context: context,
      builder: (_) => LogTimeDialog(
        onSubmit: _selfSubmit,
        initialDate: viewedMonth,
        scopedProjectId: widget.projectId,
        scopedProjectName: _projectName,
      ),
    );
    await _load();
  }

  Future<void> _openMemberLog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LogForMemberDialog(
        projectId: widget.projectId,
        members: _projectMembers,
      ),
    );
    await _load();
  }

  /// Manager drill-in: open a member's day, then edit or delete their entries.
  Future<void> _openMemberDay(TeamMemberMonth member, String isoDate) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MemberDaySheet(
        projectId: widget.projectId,
        member: member,
        date: isoDate,
      ),
    );
    await _load();
  }

  Future<void> _export(ExportFormat fmt) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final from = isoDate(_year, _month, 1);
    final to = isoDate(_year, _month, lastDay(_year, _month));
    final res = await _repo.exportProject(
      widget.projectId,
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
      filename: 'team-$_year-$_month.${fmt.name}',
      mimeType: mime,
      bytes: bytes,
    );
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttExportUnsupported)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final monthLabel = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime(_year, _month));

    return Scaffold(
      appBar: AppBar(
        title: Text(t.ttTeamTimesheet),
        actions: [
          if (_canLog) _logButton(t),
          PopupMenuButton<ExportFormat>(
            icon: const Icon(Icons.download_outlined),
            tooltip: t.ttExport,
            onSelected: _export,
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
                const Spacer(),
                if (_isLocked)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: const Icon(Icons.lock_outline, size: 16),
                      label: Text(t.ttLockedBadge),
                    ),
                  ),
                OutlinedButton.icon(
                  icon: Icon(
                    _isLocked ? Icons.lock_open_outlined : Icons.lock_outline,
                  ),
                  label: Text(_isLocked ? t.ttUnlockMonth : t.ttLockMonth),
                  onPressed: _toggleLock,
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
                      onTapDay: _canManage ? _openMemberDay : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _logButton(AppLocalizations t) {
    if (!_canManage) {
      return IconButton(
        icon: const Icon(Icons.add),
        tooltip: t.ttLogTime,
        onPressed: _openSelfLog,
      );
    }
    return PopupMenuButton<int>(
      icon: const Icon(Icons.add),
      tooltip: t.ttLogTime,
      onSelected: (v) => v == 0 ? _openSelfLog() : _openMemberLog(),
      itemBuilder: (_) => [
        PopupMenuItem(value: 0, child: Text(t.ttLogMyTime)),
        PopupMenuItem(value: 1, child: Text(t.ttLogForMember)),
      ],
    );
  }
}

/// Manager-only dialog to log time on behalf of a project member via
/// `/projects/{id}/time-entries`.
class _LogForMemberDialog extends StatefulWidget {
  const _LogForMemberDialog({required this.projectId, required this.members});
  final String projectId;
  final List<Membership> members;

  @override
  State<_LogForMemberDialog> createState() => _LogForMemberDialogState();
}

class _LogForMemberDialogState extends State<_LogForMemberDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _userId;
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
      title: Text(t.ttLogForMember),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _userId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.ttMember),
                items: [
                  for (final m in widget.members)
                    DropdownMenuItem(
                      value: m.userId,
                      child: Text(
                        m.fullName.isNotEmpty ? m.fullName : m.username,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _userId = v),
              ),
              const SizedBox(height: 8),
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
    final userId = _userId;
    if (userId == null) {
      setState(() => _error = t.ttSelectMember);
      return;
    }
    final h = double.tryParse(_hours.text.replaceAll(',', '.'));
    if (h == null || h <= 0) {
      setState(() => _error = t.ttInvalidHours);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await getIt<TimesheetRepository>().adminLogTime(
      widget.projectId,
      userId: userId,
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
    Navigator.pop(context);
  }
}

/// Manager-only bottom sheet: lists one member's entries for a single day and
/// lets a manager edit (via `correctEntry`) or delete (via `adminDeleteEntry`)
/// each one. Both endpoints require `time.manage` and bypass period locks.
class _MemberDaySheet extends StatefulWidget {
  const _MemberDaySheet({
    required this.projectId,
    required this.member,
    required this.date,
  });
  final String projectId;
  final TeamMemberMonth member;
  final String date;

  @override
  State<_MemberDaySheet> createState() => _MemberDaySheetState();
}

class _MemberDaySheetState extends State<_MemberDaySheet> {
  TimesheetRepository get _repo => getIt<TimesheetRepository>();
  List<TimeEntry>? _entries;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final res = await _repo.listProjectEntries(
      widget.projectId,
      from: widget.date,
      to: widget.date,
      userId: widget.member.userId,
    );
    if (!mounted) return;
    setState(() => _entries = res.valueOrNull ?? const []);
  }

  Future<void> _edit(TimeEntry e) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EditEntryDialog(
        entry: e,
        onSubmit: ({required minutes, required version, note, date}) async =>
            (await _repo.correctEntry(
              widget.projectId,
              entryId: e.id,
              minutes: minutes,
              version: version,
              note: note,
              date: date,
            )).failureOrNull,
      ),
    );
    await _reload();
  }

  Future<void> _delete(TimeEntry e) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.actionDelete),
        content: Text(t.ttConfirmDeleteEntry),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final res = await _repo.adminDeleteEntry(widget.projectId, e.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.isErr) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = _entries;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.member.displayName} · ${widget.date}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (entries == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(t.ttNoEntries)),
              )
            else
              for (final e in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kindIcon(e.kind)),
                  title: Text(e.label),
                  subtitle: e.note.isEmpty ? null : Text(e.note),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fmtMins(e.minutes)),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: _busy ? null : () => _edit(e),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _busy ? null : () => _delete(e),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
