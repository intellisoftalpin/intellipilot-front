import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// Per-project team timesheet (managers): a members × days grid for a month,
/// with per-month lock/unlock and CSV/XLSX export.
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

  TimesheetRepository get _repo => getIt<TimesheetRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
                : _grid(context),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final t = AppLocalizations.of(context);
    final days = [for (var d = 1; d <= lastDay(_year, _month); d++) d];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columns: [
            DataColumn(label: Text(t.ttMember)),
            DataColumn(label: Text(t.ttTotal)),
            for (final d in days) DataColumn(label: Text('$d')),
          ],
          rows: [
            for (final m in _members!)
              DataRow(
                cells: [
                  DataCell(Text(m.displayName)),
                  DataCell(
                    Text(
                      fmtMins(m.totalMinutes),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final d in days)
                    DataCell(
                      _cell(context, m.days[isoDate(_year, _month, d)] ?? 0),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int minutes) {
    if (minutes == 0) return const Text('·');
    final hours = minutes / 60;
    final theme = Theme.of(context);
    // Light heatmap: deeper as the day fills up toward 8h.
    final alpha = (hours / 8).clamp(0.0, 1.0) * 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: theme.colorScheme.primary.withValues(alpha: alpha),
      child: Text(
        hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1),
      ),
    );
  }
}
