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

/// Colours the timeline uses for the segments that are not the bar itself.
/// Fixed hues rather than theme roles: they carry meaning (commercial /
/// overrun / saved) that must not shift with the seed colour, and each is
/// legible on both light and dark surfaces.
abstract final class MilestonePalette {
  /// The commercial release tail. Blue — it is a shipping date, not a
  /// problem, and the previous grey read as disabled.
  static const business = Color(0xFF2F6FED);

  /// Time lost: the stretch between the planned end and a later actual end.
  static const overrun = Color(0xFFE8833A);

  /// Time saved: the stretch between an earlier actual end and the plan.
  static const saved = Color(0xFF2E9E5B);
}

/// The timeline scale, in pixels per day.
///
/// Continuous rather than four fixed stops: the old enum jumped from 18 px/day
/// to 6 to 2.2, so a single click of + or − changed the chart by 3x and there
/// was nothing in between. Each click now multiplies by [step], which is a
/// small enough ratio to feel like zooming and keeps every intermediate scale
/// reachable.
abstract final class GanttZoom {
  /// A whole year fits comfortably at the far end.
  static const double min = 0.3;

  /// Individual days are clearly separated at the near end.
  static const double max = 26;

  /// One click. ~26% per step gives roughly 19 stops across the range.
  static const double step = 1.26;

  /// Opening scale: a few months in view.
  static const double initial = 2.2;

  static double zoomIn(double v) => (v * step).clamp(min, max);
  static double zoomOut(double v) => (v / step).clamp(min, max);

  // Tolerances keep the buttons from staying enabled at a bound that
  // floating-point drift left a hair short of it.
  static bool canZoomIn(double v) => v < max * 0.999;
  static bool canZoomOut(double v) => v > min * 1.001;

  /// Which of the four named scales this pixel budget reads as, for the label
  /// between the buttons and for choosing tick spacing.
  static GanttScale scaleOf(double pxPerDay) {
    if (pxPerDay >= 10) return GanttScale.days;
    if (pxPerDay >= 4) return GanttScale.weeks;
    if (pxPerDay >= 1.4) return GanttScale.months;
    return GanttScale.quarters;
  }
}

/// The named scale a pixel budget falls into. Drives tick density and the
/// label shown between the zoom buttons.
enum GanttScale { days, weeks, months, quarters }

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

  /// Stored as the scale itself rather than an index, so the remembered value
  /// survives any future change to the range without silently meaning
  /// something else.
  double get zoom {
    final raw = _storage.get<double>(_zoomKey);
    if (raw == null || raw.isNaN) return GanttZoom.initial;
    return raw.clamp(GanttZoom.min, GanttZoom.max);
  }

  Future<void> setZoom(double value) => _storage.set<double>(_zoomKey, value);
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
  late double _zoom = _prefs.zoom;

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

  /// Open the sidebar and refresh the page underneath only when something
  /// actually changed.
  ///
  /// Deliberately does **not** navigate to the detail URL on the way in. The
  /// detail route builds its own `MilestonesListPage`, whose `initState` opens
  /// a second sheet on top of this one — so every close revealed another copy
  /// and the panel had to be dismissed twice. Deep links still work: they
  /// arrive on the detail route, open the sheet once, and return to the list
  /// URL on close.
  Future<void> _open(String milestoneId, {bool fromDeepLink = false}) async {
    final cubit = context.read<MilestonesListCubit>();
    final router = GoRouter.of(context);
    final result = await showMilestoneDetailSheet(
      context,
      projectId: projectId,
      milestoneId: milestoneId,
    );
    if (!mounted) return;
    if (fromDeepLink) {
      router.go(Routes.projectMilestonesFor(projectId));
    }
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

  Future<void> _setZoom(double value) async {
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
              onPressed: GanttZoom.canZoomOut(_zoom)
                  ? () => _setZoom(GanttZoom.zoomOut(_zoom))
                  : null,
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
              onPressed: GanttZoom.canZoomIn(_zoom)
                  ? () => _setZoom(GanttZoom.zoomIn(_zoom))
                  : null,
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
              // Animate between scales so a zoom reads as the timeline
              // stretching rather than as the whole chart being replaced.
              ? TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _zoom),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, _) => _MilestonesGantt(
                    state: state,
                    zoom: scale,
                    showBusinessRelease: showBusiness,
                    onOpen: _open,
                  ),
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

  static String _zoomLabel(AppLocalizations t, double z) =>
      switch (GanttZoom.scaleOf(z)) {
        GanttScale.days => t.milestoneZoomDays,
        GanttScale.weeks => t.milestoneZoomWeeks,
        GanttScale.months => t.milestoneZoomMonths,
        GanttScale.quarters => t.milestoneZoomQuarters,
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
const double _kGanttRowHeight = 60;
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
  final double zoom;
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

    final pxPerDay = zoom;
    final chartWidth = totalDays * pxPerDay;
    double x(DateTime d) => d.difference(min).inDays * pxPerDay;

    // Month ticks across the window; at the coarsest zooms label quarters only
    // so the header does not turn into a smear.
    final everyNMonths = switch (GanttZoom.scaleOf(zoom)) {
      GanttScale.days || GanttScale.weeks => 1,
      GanttScale.months => 1,
      GanttScale.quarters => 3,
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
                          lateLabel: t.milestoneSlipLate,
                          earlyLabel: t.milestoneSlipEarly,
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
    required String lateLabel,
    required String earlyLabel,
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

    // Business-release tail: from the technical end that really happened to
    // the commercial date.
    final business = m.businessReleaseDate;
    final technicalEnd = m.effectiveEndDate;
    if (showBusinessRelease && business != null && technicalEnd != null) {
      final tailLeft = x(technicalEnd) + pxPerDay;
      final tailWidth = (business.difference(technicalEnd).inDays * pxPerDay)
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
                  color: MilestonePalette.business.withValues(alpha: 0.75),
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

    // The gap between plan and reality, drawn over the bar so it reads as part
    // of it. Late slips run past the planned date in the overrun colour; early
    // finishes run back from it in the saved colour, so the two are
    // distinguishable at a glance rather than only by reading the dates.
    final planned = m.endDate;
    final actual = m.actualEndDate;
    if (planned != null && actual != null && planned != actual) {
      final late = actual.isAfter(planned);
      final from = late ? planned : actual;
      final to = late ? actual : planned;
      final gapLeft = x(from) + pxPerDay;
      final gapWidth = (to.difference(from).inDays * pxPerDay).clamp(
        3.0,
        double.infinity,
      );
      widgets.add(
        Positioned(
          left: gapLeft,
          top: top,
          child: Tooltip(
            message: late
                ? '$lateLabel: ${isoDate(planned)} → ${isoDate(actual)}'
                : '$earlyLabel: ${isoDate(actual)} → ${isoDate(planned)}',
            child: IgnorePointer(
              child: Container(
                width: gapWidth,
                height: _kGanttBarHeight,
                decoration: BoxDecoration(
                  color:
                      (late ? MilestonePalette.overrun : MilestonePalette.saved)
                          .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      );
    }
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: completed
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                  _RowDates(milestone: milestone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The planned end date under each timeline row, plus the actual one once it
/// is recorded — coloured by whether it slipped or came in early, so the row
/// says the same thing as its bar without needing the chart to be read.
class _RowDates extends StatelessWidget {
  const _RowDates({required this.milestone});
  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final planned = milestone.endDate;
    final actual = milestone.actualEndDate;
    if (planned == null && actual == null) return const SizedBox.shrink();

    final slip = milestone.slipDays;
    final actualColour = slip == null
        ? theme.colorScheme.onSurfaceVariant
        : (slip > 0 ? MilestonePalette.overrun : MilestonePalette.saved);

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 8,
        children: [
          if (planned != null)
            Text(
              '${t.milestonePlannedShort} ${isoDate(planned)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          if (actual != null)
            Text(
              '${t.milestoneActualShort} ${isoDate(actual)}'
              '${slip == null ? '' : ' (${slip > 0 ? '+' : ''}$slip)'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: actualColour,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
