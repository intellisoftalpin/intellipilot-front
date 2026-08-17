import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestones_list_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_detail_sheet.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_edit_dialog.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/progress_ring.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

/// The milestones screen: a two-column board (in progress / completed) or a
/// timeline, whichever the user last used. Clicking a milestone anywhere opens
/// the detail sidebar — there is no separate milestone screen.
class MilestonesListPage extends StatelessWidget {
  const MilestonesListPage({
    required this.projectId,
    this.openMilestoneId,
    super.key,
  });

  final String projectId;

  /// Deep link: open the sidebar on this milestone as soon as the page mounts.
  final String? openMilestoneId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: getIt<ProfileRepository>().getProfile().then(
        (r) => r.valueOrNull,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) {
                final c = ProjectDetailCubit(
                  repo: getIt<ProjectsRepository>(),
                  projectId: projectId,
                  currentUserId: profile.id,
                );
                unawaited(c.load());
                return c;
              },
            ),
            BlocProvider<MilestonesListCubit>(
              create: (_) {
                final c = MilestonesListCubit(
                  repo: getIt<MilestonesRepository>(),
                  backlog: getIt<BacklogRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _MilestonesView(
            projectId: projectId,
            openMilestoneId: openMilestoneId,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// remembered view + zoom
// ---------------------------------------------------------------------------

/// Timeline scales, coarsest last. The pixel budget per day is what actually
/// drives the drawing; the label is what the user picks.
enum GanttZoom {
  days(18),
  weeks(6),
  months(2.2),
  quarters(0.9);

  const GanttZoom(this.pxPerDay);
  final double pxPerDay;
}

/// Per-project, per-device view preferences. Kept local (Hive `ui` box, like
/// the board's collapsed columns) so the page can render its remembered view
/// on the first frame instead of waiting on a round-trip.
class _ViewPrefs {
  _ViewPrefs(this.projectId) : _storage = getIt(instanceName: HiveBoxes.ui);
  final String projectId;
  final KeyValueStorage _storage;

  String get _viewKey => 'milestones.view:$projectId';
  String get _zoomKey => 'milestones.zoom:$projectId';

  bool get gantt => _storage.get<bool>(_viewKey) ?? false;
  Future<void> setGantt({required bool value}) =>
      _storage.set<bool>(_viewKey, value);

  GanttZoom get zoom {
    final raw = _storage.get<int>(_zoomKey);
    if (raw == null || raw < 0 || raw >= GanttZoom.values.length) {
      return GanttZoom.months;
    }
    return GanttZoom.values[raw];
  }

  Future<void> setZoom(GanttZoom value) =>
      _storage.set<int>(_zoomKey, value.index);
}

class _MilestonesView extends StatefulWidget {
  const _MilestonesView({required this.projectId, this.openMilestoneId});
  final String projectId;
  final String? openMilestoneId;

  @override
  State<_MilestonesView> createState() => _MilestonesViewState();
}

class _MilestonesViewState extends State<_MilestonesView> {
  late final _prefs = _ViewPrefs(widget.projectId);
  late bool _gantt = _prefs.gantt;
  late GanttZoom _zoom = _prefs.zoom;

  String get projectId => widget.projectId;

  @override
  void initState() {
    super.initState();
    final deepLink = widget.openMilestoneId;
    if (deepLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_open(deepLink, fromDeepLink: true));
      });
    }
  }

  /// Open the sidebar, keeping the URL in step so the panel is shareable, and
  /// refresh the page underneath only when something actually changed.
  Future<void> _open(String milestoneId, {bool fromDeepLink = false}) async {
    final cubit = context.read<MilestonesListCubit>();
    final router = GoRouter.of(context);
    if (!fromDeepLink) {
      router.go(Routes.milestoneDetailFor(projectId, milestoneId));
    }
    final result = await showMilestoneDetailSheet(
      context,
      projectId: projectId,
      milestoneId: milestoneId,
    );
    if (!mounted) return;
    router.go(Routes.projectMilestonesFor(projectId));
    if (result.deleted) {
      cubit.forget(milestoneId);
    } else if (result.changed) {
      await cubit.load();
    }
  }

  Future<void> _setGantt({required bool value}) async {
    setState(() => _gantt = value);
    await _prefs.setGantt(value: value);
  }

  Future<void> _setZoom(GanttZoom value) async {
    setState(() => _zoom = value);
    await _prefs.setZoom(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.milestonesTitle,
        ),
        actions: [
          if (_gantt) ...[
            IconButton(
              icon: const Icon(Icons.zoom_out),
              tooltip: t.milestoneZoomOut,
              onPressed: _zoom.index >= GanttZoom.values.length - 1
                  ? null
                  : () => _setZoom(GanttZoom.values[_zoom.index + 1]),
            ),
            Tooltip(
              message: t.milestoneZoomLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_zoomLabel(t, _zoom)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: t.milestoneZoomIn,
              onPressed: _zoom.index == 0
                  ? null
                  : () => _setZoom(GanttZoom.values[_zoom.index - 1]),
            ),
            const SizedBox(width: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  tooltip: t.milestonesViewList,
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.view_timeline_outlined, size: 18),
                  tooltip: t.milestonesViewGantt,
                ),
              ],
              selected: {_gantt},
              onSelectionChanged: (s) => _setGantt(value: s.first),
            ),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, s) {
          if (s is! ProjectDetailLoaded || !s.has(Permission.milestoneCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewMilestone),
            onPressed: _create,
          );
        },
      ),
      body: BlocBuilder<MilestonesListCubit, MilestonesListState>(
        builder: (context, state) {
          if (state is MilestonesListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MilestonesListFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.milestonesLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<MilestonesListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! MilestonesListLoaded) return const SizedBox.shrink();
          if (state.milestones.isEmpty) {
            final detail = context.watch<ProjectDetailCubit>().state;
            final canCreate =
                detail is ProjectDetailLoaded &&
                detail.has(Permission.milestoneCreate);
            return EmptyState(
              icon: Icons.flag_outlined,
              title: t.milestonesTitle,
              body: t.milestonesEmpty,
              action: canCreate
                  ? FilledButton.icon(
                      icon: const Icon(Icons.add),
                      onPressed: _create,
                      label: Text(t.actionNewMilestone),
                    )
                  : null,
            );
          }
          final detail = context.watch<ProjectDetailCubit>().state;
          final showBusiness =
              detail is ProjectDetailLoaded &&
              detail.has(Permission.milestoneBusinessReleaseView);
          return _gantt
              ? _MilestonesGantt(
                  state: state,
                  zoom: _zoom,
                  showBusinessRelease: showBusiness,
                  onOpen: _open,
                )
              : _MilestonesBoard(state: state, onOpen: _open);
        },
      ),
    );
  }

  Future<void> _create() async {
    final cubit = context.read<MilestonesListCubit>();
    final body = await showMilestoneEditDialog(context);
    if (body == null) return;
    await cubit.create(body);
  }

  static String _zoomLabel(AppLocalizations t, GanttZoom z) => switch (z) {
    GanttZoom.days => t.milestoneZoomDays,
    GanttZoom.weeks => t.milestoneZoomWeeks,
    GanttZoom.months => t.milestoneZoomMonths,
    GanttZoom.quarters => t.milestoneZoomQuarters,
  };
}

// ---------------------------------------------------------------------------
// board view — In progress / Completed
// ---------------------------------------------------------------------------

class _MilestonesBoard extends StatelessWidget {
  const _MilestonesBoard({required this.state, required this.onOpen});
  final MilestonesListLoaded state;
  final Future<void> Function(String milestoneId) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          _BoardColumn(
            title: t.milestoneColumnInProgress,
            emptyLabel: t.milestoneColumnInProgressEmpty,
            milestones: state.inProgress,
            state: state,
            onOpen: onOpen,
          ),
          _BoardColumn(
            title: t.milestoneColumnCompleted,
            emptyLabel: t.milestoneColumnCompletedEmpty,
            milestones: state.completed,
            state: state,
            onOpen: onOpen,
          ),
        ];
        // Below ~840px the two columns would each be too narrow to read, so
        // they stack instead of shrinking.
        if (constraints.maxWidth < 840) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: c,
                ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in columns) ...[
                Expanded(child: c),
                if (c != columns.last) const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.emptyLabel,
    required this.milestones,
    required this.state,
    required this.onOpen,
  });
  final String title;
  final String emptyLabel;
  final List<Milestone> milestones;
  final MilestonesListLoaded state;
  final Future<void> Function(String milestoneId) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                '${milestones.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (milestones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          for (final m in milestones)
            _MilestoneCard(
              milestone: m,
              progress: state.progressFor(m.id),
              epicCount: state.epicCountFor(m.id),
              onTap: () => onOpen(m.id),
            ),
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.progress,
    required this.epicCount,
    required this.onTap,
  });
  final Milestone milestone;
  final double? progress;
  final int epicCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final completed = milestone.closed;
    final dates = [
      if (milestone.startDate != null) isoDate(milestone.startDate!),
      if (milestone.endDate != null) isoDate(milestone.endDate!),
    ].join(' → ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: completed ? theme.colorScheme.surfaceContainerHighest : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProgressRing(value: progress, completed: completed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      milestone.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: completed
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (dates.isNotEmpty) dates,
                        t.milestoneEpicCount(epicCount),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAtRisk(milestone))
                Tooltip(
                  message: t.milestoneOverdue,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A milestone still in progress whose technical release date has passed.
bool isAtRisk(Milestone m) {
  if (m.closed) return false;
  final end = m.endDate;
  if (end == null) return false;
  final now = DateTime.now();
  return end.isBefore(DateTime(now.year, now.month, now.day));
}

// ---------------------------------------------------------------------------
// Gantt view
// ---------------------------------------------------------------------------

const double _kGanttLabelWidth = 260;
const double _kGanttRowHeight = 48;
const double _kGanttHeaderHeight = 36;
const double _kGanttBarHeight = 20;

/// Timeline of milestones as horizontal bars over a shared month axis.
///
/// In-progress milestones occupy the upper band; completed ones sit in their
/// own band underneath, sharing the same axis so the two are comparable.
/// Missing dates use the display defaults (start = today, end = +7 days) and
/// render semi-transparent to signal an estimate. When the viewer may see it,
/// the stretch between the technical end date and the business release date is
/// drawn as a distinct trailing segment.
class _MilestonesGantt extends StatelessWidget {
  const _MilestonesGantt({
    required this.state,
    required this.zoom,
    required this.showBusinessRelease,
    required this.onOpen,
  });

  final MilestonesListLoaded state;
  final GanttZoom zoom;
  final bool showBusinessRelease;
  final Future<void> Function(String milestoneId) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final open = state.inProgress;
    final done = state.completed;
    final ordered = [...open, ...done];
    if (ordered.isEmpty) return const SizedBox.shrink();

    // Window: every bar, the business-release tails, and today.
    final ranges = {for (final m in ordered) m.id: effectiveRange(m)};
    var min = ranges.values.first.start;
    var max = ranges.values.first.end;
    for (final r in ranges.values) {
      if (r.start.isBefore(min)) min = r.start;
      if (r.end.isAfter(max)) max = r.end;
    }
    if (showBusinessRelease) {
      for (final m in ordered) {
        final b = m.businessReleaseDate;
        if (b != null && b.isAfter(max)) max = b;
      }
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(min)) min = today;
    if (today.isAfter(max)) max = today;
    min = min.subtract(const Duration(days: 3));
    max = max.add(const Duration(days: 7));
    final totalDays = max.difference(min).inDays.clamp(1, 3650);

    final pxPerDay = zoom.pxPerDay;
    final chartWidth = totalDays * pxPerDay;
    double x(DateTime d) => d.difference(min).inDays * pxPerDay;

    // Month ticks across the window; at the coarsest zooms label quarters only
    // so the header does not turn into a smear.
    final everyNMonths = switch (zoom) {
      GanttZoom.days || GanttZoom.weeks => 1,
      GanttZoom.months => 1,
      GanttZoom.quarters => 3,
    };
    final months = <DateTime>[];
    var tick = DateTime(min.year, min.month);
    while (!tick.isAfter(max)) {
      if (!tick.isBefore(min) && (tick.month - 1) % everyNMonths == 0) {
        months.add(tick);
      }
      tick = DateTime(tick.year, tick.month + 1);
    }
    final monthFmt = DateFormat.yMMM(
      Localizations.localeOf(context).toLanguageTag(),
    );

    // Row layout: in-progress band, then a separator row, then completed.
    final hasSeparator = done.isNotEmpty && open.isNotEmpty;
    final rows = <_GanttRow>[
      for (final m in open) _GanttRow.milestone(m),
      if (hasSeparator) const _GanttRow.separator(),
      for (final m in done) _GanttRow.milestone(m),
    ];
    final chartHeight = _kGanttHeaderHeight + rows.length * _kGanttRowHeight;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed name column — full titles, wrapped rather than truncated.
          SizedBox(
            width: _kGanttLabelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: _kGanttHeaderHeight),
                for (final row in rows)
                  SizedBox(
                    height: _kGanttRowHeight,
                    child: row.milestone == null
                        ? _BandLabel(text: t.milestoneColumnCompleted)
                        : _GanttLabel(
                            milestone: row.milestone!,
                            progress: state.progressFor(row.milestone!.id),
                            onTap: () => onOpen(row.milestone!.id),
                          ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: chartHeight,
                child: Stack(
                  children: [
                    for (final month in months)
                      Positioned(
                        left: x(month),
                        top: 0,
                        bottom: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              monthFmt.format(month),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                width: 1,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Band separator, drawn across the whole chart.
                    if (hasSeparator)
                      Positioned(
                        left: 0,
                        right: 0,
                        top:
                            _kGanttHeaderHeight +
                            open.length * _kGanttRowHeight +
                            _kGanttRowHeight / 2,
                        child: Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    Positioned(
                      left: x(today),
                      top: _kGanttHeaderHeight - 6,
                      bottom: 0,
                      child: Tooltip(
                        message: isoDate(today),
                        child: Container(
                          width: 2,
                          color: theme.colorScheme.error.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    for (var i = 0; i < rows.length; i++)
                      if (rows[i].milestone != null)
                        ..._bars(
                          context,
                          rows[i].milestone!,
                          ranges[rows[i].milestone!.id]!,
                          top:
                              _kGanttHeaderHeight +
                              i * _kGanttRowHeight +
                              (_kGanttRowHeight - _kGanttBarHeight) / 2,
                          x: x,
                          pxPerDay: pxPerDay,
                          estimatedLabel: t.milestonesDatesEstimated,
                          businessLabel: t.milestoneFieldBusinessRelease,
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The main bar plus, when visible, the business-release tail behind it.
  List<Widget> _bars(
    BuildContext context,
    Milestone m,
    ({DateTime start, DateTime end, bool estimated}) range, {
    required double top,
    required double Function(DateTime) x,
    required double pxPerDay,
    required String estimatedLabel,
    required String businessLabel,
  }) {
    final theme = Theme.of(context);
    final completed = m.closed;
    final colour = completed
        ? theme.colorScheme.outline
        : (isAtRisk(m) ? theme.colorScheme.error : theme.colorScheme.primary);
    final left = x(range.start);
    final width = ((range.end.difference(range.start).inDays + 1) * pxPerDay)
        .clamp(6.0, double.infinity);
    final label =
        '${isoDate(range.start)} → ${isoDate(range.end)}'
        '${range.estimated ? ' · $estimatedLabel' : ''}';

    final widgets = <Widget>[];

    // Business-release tail: from the technical end to the commercial date.
    final business = m.businessReleaseDate;
    if (showBusinessRelease && business != null && m.endDate != null) {
      final tailLeft = x(m.endDate!) + pxPerDay;
      final tailWidth = (business.difference(m.endDate!).inDays * pxPerDay)
          .clamp(2.0, double.infinity);
      widgets.add(
        Positioned(
          left: tailLeft,
          top: top,
          child: Tooltip(
            message: '$businessLabel: ${isoDate(business)}',
            child: InkWell(
              onTap: () => onOpen(m.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: tailWidth,
                height: _kGanttBarHeight,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    widgets.add(
      Positioned(
        left: left,
        top: top,
        child: Tooltip(
          message: '${m.name}\n$label',
          child: InkWell(
            onTap: () => onOpen(m.id),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: width,
              height: _kGanttBarHeight,
              decoration: BoxDecoration(
                color: colour.withValues(alpha: range.estimated ? 0.35 : 0.85),
                borderRadius: BorderRadius.circular(6),
                border: range.estimated
                    ? Border.all(color: colour, width: 1)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    return widgets;
  }
}

/// One timeline row: either a milestone, or the header of the completed band.
class _GanttRow {
  const _GanttRow.milestone(Milestone this.milestone);
  const _GanttRow.separator() : milestone = null;
  final Milestone? milestone;
}

class _BandLabel extends StatelessWidget {
  const _BandLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GanttLabel extends StatelessWidget {
  const _GanttLabel({
    required this.milestone,
    required this.progress,
    required this.onTap,
  });
  final Milestone milestone;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = milestone.closed;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          children: [
            ProgressRing(value: progress, size: 28, completed: completed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                milestone.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: completed ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
